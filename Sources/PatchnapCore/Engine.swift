import Foundation

public actor Engine {
    private let storage: Storage
    private let providers: any UpdateBackend
    private let conditions: @Sendable () async -> Conditions
    public init(storage: Storage = Storage(), providers: any UpdateBackend = Providers(),
                conditions: @escaping @Sendable () async -> Conditions = { await SystemConditions.read() }) {
        self.storage = storage; self.providers = providers; self.conditions = conditions
    }

    public func run(forceCheck: Bool = false, install: Bool = true) async throws -> Snapshot {
        let lock = try storage.lock()
        defer { withExtendedLifetime(lock) {} }
        let settings = try storage.loadSettings()
        var state = try storage.loadSnapshot()
        let now = Date()
        if forceCheck || state.lastCheck.map({ now.timeIntervalSince($0) >= max(900, settings.checkInterval) }) ?? true {
            let discovery = await providers.discover(refresh: true)
            state.apps = discovery.apps; state.providerErrors = discovery.errors; state.lastCheck = now
        }
        state.lastRun = now
        guard install, settings.enabled else {
            state.message = settings.enabled ? "Check complete. Updates will wait for idle time." : "Background updates are paused."
            try storage.saveSnapshot(state)
            return state
        }
        var completed = 0
        for original in state.apps where original.needsUpdate {
            // Reload user choices so an exclusion or pause takes effect between installs.
            let currentSettings = try storage.loadSettings()
            let conditions = await self.conditions()
            guard Policy.evaluate(original, settings: currentSettings, conditions: conditions, attempt: state.attempts[original.id]) == .eligible else { continue }
            do {
                // Re-discover without refreshing catalog metadata, then check the exact candidate again.
                let fresh = await providers.discover(refresh: false)
                guard !fresh.failedProviders.contains(original.provider) else { throw PatchnapError.message("An update source could not be verified. Waiting for a successful check.") }
                guard let candidate = fresh.apps.first(where: { $0.id == original.id }),
                      candidate.availableVersion == original.availableVersion else { continue }
                let finalSettings = try storage.loadSettings()
                let finalConditions = await self.conditions()
                guard Policy.evaluate(candidate, settings: finalSettings, conditions: finalConditions, attempt: state.attempts[candidate.id]) == .eligible else { continue }
                let identityBefore = try await providers.signingIdentity(candidate)
                try await providers.install(candidate)
                let identityAfter = try await providers.signingIdentity(candidate)
                guard identityBefore == identityAfter else { throw PatchnapError.message("The updated app has a different developer identity. Review it before using the app.") }
                let actual = try await providers.installedVersion(candidate)
                guard let target = candidate.availableVersion,
                      actual.compare(target, options: .numeric) != .orderedAscending,
                      actual != candidate.installedVersion else { throw PatchnapError.message("The installer finished, but the new app version could not be verified.") }
                state.attempts[candidate.id] = nil
                if let i = state.apps.firstIndex(where: { $0.id == candidate.id }) { state.apps[i].installedVersion = actual; state.apps[i].availableVersion = nil }
                state.record(HistoryEntry(appID: candidate.id, appName: candidate.name, outcome: .updated, message: "\(candidate.installedVersion) → \(actual), verified on disk."))
                completed += 1
            } catch {
                state.attempts[original.id] = Attempt.failed(previous: state.attempts[original.id], now: Date())
                state.record(HistoryEntry(appID: original.id, appName: original.name, outcome: .needsAttention, message: error.localizedDescription))
            }
            try storage.saveSnapshot(state)
        }
        state.message = completed > 0 ? "\(completed) update\(completed == 1 ? "" : "s") handled. Rest easy." : "Waiting for the next eligible update."
        try storage.saveSnapshot(state)
        return state
    }
}
