import Foundation
import AppKit
import ServiceManagement
import Observation
import PatchnapCore

@MainActor @Observable final class AppModel {
    static let shared = AppModel()
    let storage = Storage()
    let engine = Engine()
    var settings = Settings()
    var snapshot = Snapshot()
    var checking = false
    var error: String?
    var registration = "Not enabled"
    var helperInstalled = false
    var helperBusy = false
    var demo: Bool
    var filters = AppListFilters()
    var tab = 0
    init() {
        demo = CommandLine.arguments.contains("--demo")
        if let argument = CommandLine.arguments.first(where: { $0.hasPrefix("--demo-tab=") }), let value = Int(argument.dropFirst("--demo-tab=".count)), (0...3).contains(value) { tab = value }
        if demo {
            if let argument = CommandLine.arguments.first(where: { $0.hasPrefix("--demo-source=") }) {
                filters.source = Provider(rawValue: String(argument.dropFirst("--demo-source=".count)))
            }
            if let argument = CommandLine.arguments.first(where: { $0.hasPrefix("--demo-status=") }) {
                filters.status = AppStatus(rawValue: String(argument.dropFirst("--demo-status=".count)))
            }
            if let argument = CommandLine.arguments.first(where: { $0.hasPrefix("--demo-search=") }) {
                filters.search = String(argument.dropFirst("--demo-search=".count))
            }
            settings.enabled = true; snapshot.lastCheck = Date(); snapshot.message = "Updates handled. Rest easy."
            snapshot.apps = [
                InstalledApp(id: "store:1", name: "Things", bundleID: "com.culturedcode.ThingsMac", path: "", installedVersion: "3.22", provider: .appStore, token: "1"),
                InstalledApp(id: "brew:firefox", name: "Firefox", bundleID: "org.mozilla.firefox", path: "", installedVersion: "145.0", availableVersion: "146.0", provider: .homebrew, token: "firefox"),
                InstalledApp(id: "bundle:demo", name: "A standalone app", bundleID: "demo.app", path: "", installedVersion: "2.1", provider: .unsupported, token: "", automatic: false, reason: "No supported update source yet.")
            ]
            snapshot.record(HistoryEntry(appID: "store:1", appName: "Things", outcome: .updated, message: "3.21 → 3.22, verified on disk. (Demo)"))
        } else { reload() }
    }
    var pending: Int { snapshot.apps.filter(\.needsUpdate).count }
    var covered: Int { snapshot.apps.filter { $0.provider != .unsupported && $0.automatic }.count }
    var service: SMAppService { .agent(plistName: "com.patchnap.agent.plist") }
    func reload() {
        guard !demo else { return }
        do { settings = try storage.loadSettings(); snapshot = try storage.loadSnapshot() }
        catch { self.error = "Local settings could not be read. \(error.localizedDescription)" }
        refreshService()
    }
    func refreshService() {
        switch service.status {
        case .enabled: registration = "Enabled"
        case .requiresApproval: registration = "Waiting for approval in Login Items"
        case .notRegistered: registration = "Not enabled"
        case .notFound: registration = "Move Patchnap to Applications first"
        @unknown default: registration = "Unknown registration state"
        }
        helperInstalled = FileManager.default.isExecutableFile(atPath: ToolPaths().helper)
    }
    func save() {
        guard !demo else { return }
        do { try storage.saveSettings(settings) } catch { self.error = error.localizedDescription }
    }
    func setEnabled(_ enabled: Bool) {
        guard !demo else { return }
        do {
            if enabled {
                guard Bundle.main.bundleURL.path.hasPrefix("/Applications/") else { throw PatchnapError.message("Move Patchnap.app into Applications before enabling background updates.") }
                try service.register()
            }
            settings.enabled = enabled; try storage.saveSettings(settings)
            refreshService()
        } catch { self.error = error.localizedDescription }
    }
    func removeBackground() async {
        guard !demo else { return }
        settings.enabled = false; save()
        do {
            let registration = SMAppService.agent(plistName: "com.patchnap.agent.plist")
            try await registration.unregister()
            refreshService()
        } catch { self.error = error.localizedDescription }
    }
    func check() async {
        guard !checking else { return }
        if demo { return }
        checking = true
        defer { checking = false }
        do { snapshot = try await engine.run(forceCheck: true, install: false) }
        catch { self.error = error.localizedDescription }
    }
    func exclude(_ app: InstalledApp) {
        if settings.excluded.contains(app.id) { settings.excluded.remove(app.id) } else { settings.excluded.insert(app.id) }
        save()
    }
    func hold(_ app: InstalledApp) {
        if settings.heldVersions[app.id] != nil { settings.heldVersions[app.id] = nil } else { settings.heldVersions[app.id] = app.installedVersion }
        save()
    }
    var visibleApps: [InstalledApp] {
        let running = SystemConditions.read().runningBundleIDs
        let now = Date()
        return snapshot.apps.filter { app in
            filters.matches(app, status: AppStatus.classify(app, settings: settings, attempt: snapshot.attempts[app.id], runningBundleIDs: running, now: now))
        }
    }
    func status(_ app: InstalledApp) -> String {
        AppStatus.classify(app, settings: settings, attempt: snapshot.attempts[app.id],
                           runningBundleIDs: SystemConditions.read().runningBundleIDs).label
    }
    func clearFilters() { filters = AppListFilters() }
    func configureHelper(remove: Bool = false) async {
        guard !demo, !helperBusy else { return }
        helperBusy = true; defer { helperBusy = false; refreshService() }
        do {
            let resource = remove ? "remove-store-helper.sh" : "install-store-helper.sh"
            guard let script = Bundle.main.url(forResource: resource, withExtension: nil) else { throw PatchnapError.message("The helper installer is missing from this build.") }
            if !remove {
                let source = try String(contentsOf: script, encoding: .utf8)
                guard !source.contains("__PATCHNAP_TEAM_ID__") else { throw PatchnapError.message("App Store installation authority requires a Developer ID signed build. Homebrew checks still work in source builds.") }
            }
            func quote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
            let command = "/bin/bash " + quote(script.path) + (remove ? "" : " " + quote(Bundle.main.bundleURL.path) + " " + quote(NSUserName()))
            let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let result = try await CommandRunner().run("/usr/bin/osascript", ["-e", "do shell script \"\(escaped)\" with administrator privileges"], timeout: 300)
            guard result.status == 0 else { throw PatchnapError.message("The installation helper was not changed. Approve the administrator prompt to continue, or check that this is a signed Patchnap build.") }
        } catch { self.error = error.localizedDescription }
    }
}
