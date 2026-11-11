import Foundation

public enum AppStatus: String, CaseIterable, Identifiable, Sendable {
    case upToDate, updateAvailable, appOpen, manualUpdate, needsAttention, excluded, versionHeld
    public var id: Self { self }
    public var label: String {
        switch self {
        case .upToDate: "Up to date"
        case .updateAvailable: "Update available"
        case .appOpen: "App open"
        case .manualUpdate: "Manual update"
        case .needsAttention: "Needs attention"
        case .excluded: "Excluded"
        case .versionHeld: "Version held"
        }
    }
    public static func classify(_ app: InstalledApp, settings: Settings, attempt: Attempt?,
                                runningBundleIDs: Set<String>?, now: Date = Date()) -> AppStatus {
        if settings.excluded.contains(app.id) { return .excluded }
        if settings.heldVersions[app.id] != nil { return .versionHeld }
        if let attempt, attempt.retryAfter > now { return .needsAttention }
        if !app.automatic || app.provider == .unsupported { return .manualUpdate }
        if app.needsUpdate { return runningBundleIDs?.contains(app.bundleID) == true ? .appOpen : .updateAvailable }
        return .upToDate
    }
}

public struct AppListFilters: Equatable, Sendable {
    public var search = ""
    public var source: Provider?
    public var status: AppStatus?
    public init() {}
    public var isActive: Bool { !search.isEmpty || source != nil || status != nil }
    public func matches(_ app: InstalledApp, status actualStatus: AppStatus) -> Bool {
        (search.isEmpty || app.name.localizedCaseInsensitiveContains(search))
            && (source == nil || source == app.provider)
            && (status == nil || status == actualStatus)
    }
}

extension Provider {
    public var label: String {
        switch self {
        case .appStore: "App Store"
        case .homebrew: "Homebrew"
        case .catalog: "Catalog"
        case .unsupported: "Unsupported"
        }
    }
}
