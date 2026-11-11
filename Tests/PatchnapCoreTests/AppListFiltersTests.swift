import Foundation
import Testing
@testable import PatchnapCore

struct AppListFiltersTests {
    var app: InstalledApp { InstalledApp(id: "store:1", name: "Things", bundleID: "test.things", path: "/fixture/Things.app", installedVersion: "1", availableVersion: "2", provider: .appStore, token: "1") }
    @Test func filtersCombineSearchSourceAndStatus() {
        var filter = AppListFilters(); filter.search = "THIN"; filter.source = .appStore; filter.status = .updateAvailable
        #expect(filter.matches(app, status: .updateAvailable))
        #expect(!filter.matches(app, status: .appOpen))
        filter.source = .homebrew
        #expect(!filter.matches(app, status: .updateAvailable))
        filter.source = .appStore; filter.search = "other"
        #expect(!filter.matches(app, status: .updateAvailable))
    }
    @Test func allFiltersAndClearRestoreEveryApp() {
        var filter = AppListFilters()
        #expect(!filter.isActive); #expect(filter.matches(app, status: .manualUpdate))
        filter.source = .catalog; filter.status = .versionHeld; filter.search = "missing"
        #expect(filter.isActive); #expect(!filter.matches(app, status: .updateAvailable))
        filter = AppListFilters()
        #expect(!filter.isActive); #expect(filter.matches(app, status: .updateAvailable))
    }
    @Test func displayedStatusAndFilterClassificationSharePrecedence() {
        let now = Date(); var settings = Settings()
        let attempt = Attempt(failures: 1, retryAfter: now.addingTimeInterval(100))
        func classify() -> AppStatus { AppStatus.classify(app, settings: settings, attempt: attempt, runningBundleIDs: [app.bundleID], now: now) }
        #expect(classify() == .needsAttention)
        settings.heldVersions[app.id] = "1"; #expect(classify() == .versionHeld)
        settings.excluded.insert(app.id); #expect(classify() == .excluded)
    }
    @Test func openAppsRemainDistinctFromAvailableUpdates() {
        #expect(AppStatus.classify(app, settings: Settings(), attempt: nil, runningBundleIDs: [app.bundleID]) == .appOpen)
        #expect(AppStatus.classify(app, settings: Settings(), attempt: nil, runningBundleIDs: []) == .updateAvailable)
        var current = app; current.availableVersion = nil
        #expect(AppStatus.classify(current, settings: Settings(), attempt: nil, runningBundleIDs: []) == .upToDate)
    }
    @Test func manualSourcesAreFilterableWithoutAnAvailableVersion() {
        var manual = app; manual.provider = .unsupported; manual.automatic = false; manual.availableVersion = nil
        let status = AppStatus.classify(manual, settings: Settings(), attempt: nil, runningBundleIDs: [])
        var filter = AppListFilters(); filter.source = .unsupported; filter.status = .manualUpdate
        #expect(status == .manualUpdate); #expect(filter.matches(manual, status: status))
    }
}
