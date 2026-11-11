import Foundation

public enum Provider: String, Codable, CaseIterable, Sendable { case appStore, homebrew, catalog, unsupported }
public enum Outcome: String, Codable, Sendable { case current, available, deferred, updated, needsAttention, unsupported }

public struct InstalledApp: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var bundleID: String
    public var path: String
    public var installedVersion: String
    public var availableVersion: String?
    public var provider: Provider
    public var token: String
    public var automatic: Bool
    public var download: CatalogDownload?
    public var reason: String?
    public var needsUpdate: Bool { availableVersion.map { $0 != installedVersion } ?? false }
    public init(id: String, name: String, bundleID: String, path: String, installedVersion: String,
                availableVersion: String? = nil, provider: Provider, token: String, automatic: Bool = true, reason: String? = nil) {
        self.id = id; self.name = name; self.bundleID = bundleID; self.path = path
        self.installedVersion = installedVersion; self.availableVersion = availableVersion
        self.provider = provider; self.token = token; self.automatic = automatic; self.reason = reason; self.download = nil
    }
}

public struct Settings: Codable, Equatable, Sendable {
    public var enabled = false
    public var idleSeconds: TimeInterval = 600
    public var checkInterval: TimeInterval = 10_800
    public var excluded: Set<String> = []
    public var heldVersions: [String: String] = [:]
    public init() {}
}

public struct Attempt: Codable, Sendable {
    public var failures: Int
    public var retryAfter: Date
    public init(failures: Int, retryAfter: Date) { self.failures = failures; self.retryAfter = retryAfter }
    public static func failed(previous: Attempt?, now: Date) -> Attempt {
        let count = min((previous?.failures ?? 0) + 1, 12)
        return Attempt(failures: count, retryAfter: now.addingTimeInterval(min(86_400, 900 * pow(2, Double(count - 1)))))
    }
}

public struct HistoryEntry: Codable, Identifiable, Sendable {
    public var id = UUID()
    public var date = Date()
    public var appID: String
    public var appName: String
    public var outcome: Outcome
    public var message: String
    public init(appID: String, appName: String, outcome: Outcome, message: String) {
        self.appID = appID; self.appName = appName; self.outcome = outcome; self.message = message
    }
}

public struct Snapshot: Codable, Sendable {
    public var apps: [InstalledApp] = []
    public var history: [HistoryEntry] = []
    public var attempts: [String: Attempt] = [:]
    public var lastCheck: Date?
    public var lastRun: Date?
    public var message = "Ready for your first check."
    public var providerErrors: [String] = []
    public init() {}
    public mutating func record(_ entry: HistoryEntry) {
        history.insert(entry, at: 0)
        if history.count > 300 { history.removeLast(history.count - 300) }
    }
}

public struct Conditions: Equatable, Sendable {
    public var onPower: Bool?
    public var idleSeconds: TimeInterval?
    public var runningBundleIDs: Set<String>?
    public init(onPower: Bool?, idleSeconds: TimeInterval?, runningBundleIDs: Set<String>?) {
        self.onPower = onPower; self.idleSeconds = idleSeconds; self.runningBundleIDs = runningBundleIDs
    }
}

public enum Eligibility: Equatable, Sendable { case eligible; case wait(String) }
public enum Policy {
    public static func isPrerelease(_ value: String) -> Bool {
        let pattern = #"(?i)(^|[^a-z])(alpha|beta|nightly|canary|preview|experimental|insiders?|dev|rc\d*)([^a-z]|$)|\d(?:a|b|rc)\d"#
        return value.range(of: pattern, options: .regularExpression) != nil
    }
    public static func evaluate(_ app: InstalledApp, settings: Settings, conditions: Conditions,
                                attempt: Attempt? = nil, now: Date = Date()) -> Eligibility {
        guard settings.enabled else { return .wait("Background updates are paused.") }
        guard !settings.excluded.contains(app.id) else { return .wait("Excluded by you.") }
        guard settings.heldVersions[app.id] == nil else { return .wait("Version held by you.") }
        guard app.provider != .unsupported, app.automatic else { return .wait(app.reason ?? "Requires a manual update.") }
        guard let version = app.availableVersion, app.needsUpdate else { return .wait("No update available.") }
        guard !isPrerelease(version), !isPrerelease(app.token) else { return .wait("Preview releases are excluded.") }
        guard conditions.onPower == true else { return .wait("Waiting for external power.") }
        guard let idle = conditions.idleSeconds, idle.isFinite, idle >= max(600, settings.idleSeconds) else { return .wait("Waiting until your Mac is idle.") }
        guard let running = conditions.runningBundleIDs else { return .wait("Could not verify which apps are open.") }
        guard !running.contains(app.bundleID) else { return .wait("Waiting until you close the app.") }
        guard attempt.map({ $0.retryAfter <= now }) ?? true else { return .wait("Waiting before retrying this update.") }
        return .eligible
    }
}
