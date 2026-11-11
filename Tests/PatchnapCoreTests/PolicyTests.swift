import Foundation
import Testing
@testable import PatchnapCore

struct PolicyTests {
    var app: InstalledApp { InstalledApp(id: "brew:firefox", name: "Firefox", bundleID: "org.mozilla.firefox", path: "/Applications/Firefox.app", installedVersion: "130.0", availableVersion: "131.0", provider: .homebrew, token: "firefox") }
    var ready: Conditions { Conditions(onPower: true, idleSeconds: 900, runningBundleIDs: []) }
    var enabled: Settings { var settings = Settings(); settings.enabled = true; return settings }
    @Test func idleClosedStableAppIsEligible() { #expect(Policy.evaluate(app, settings: enabled, conditions: ready) == .eligible) }
    @Test func unknownConditionsFailClosed() {
        let cases = [Conditions(onPower: nil, idleSeconds: 900, runningBundleIDs: []), Conditions(onPower: true, idleSeconds: nil, runningBundleIDs: []), Conditions(onPower: true, idleSeconds: 900, runningBundleIDs: nil), Conditions(onPower: false, idleSeconds: 900, runningBundleIDs: []), Conditions(onPower: true, idleSeconds: 2, runningBundleIDs: [])]
        for condition in cases { #expect(Policy.evaluate(app, settings: enabled, conditions: condition) != .eligible) }
    }
    @Test func doesNotUpdateRunningApp() {
        var condition = ready; condition.runningBundleIDs = [app.bundleID]
        #expect(Policy.evaluate(app, settings: enabled, conditions: condition) != .eligible)
    }
    @Test func exclusionsHoldsAndPauseWin() {
        var settings = enabled; settings.excluded.insert(app.id)
        #expect(Policy.evaluate(app, settings: settings, conditions: ready) != .eligible)
        settings.excluded = []; settings.heldVersions[app.id] = app.installedVersion
        #expect(Policy.evaluate(app, settings: settings, conditions: ready) != .eligible)
        #expect(Policy.evaluate(app, settings: Settings(), conditions: ready) != .eligible)
    }
    @Test(arguments: ["2.0-beta.1", "3.0rc2", "firefox@nightly", "chrome-canary", "1.0-preview", "2.4b3"])
    func rejectsPreviewChannels(_ value: String) { #expect(Policy.isPrerelease(value)) }
    @Test(arguments: ["1.0", "131.0.3", "firefox", "rectangle", "discord"])
    func recognizesStableLabels(_ value: String) { #expect(!Policy.isPrerelease(value)) }
    @Test func boundedBackoff() {
        let now = Date(); var attempt: Attempt?
        for _ in 0..<50 { attempt = Attempt.failed(previous: attempt, now: now) }
        #expect(attempt?.failures == 12); #expect(attempt?.retryAfter == now.addingTimeInterval(86_400))
        #expect(Policy.evaluate(app, settings: enabled, conditions: ready, attempt: attempt, now: now) != .eligible)
    }
    @Test func corruptSettingsAreNotSilentlyReset() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = Storage(directory: dir); try storage.prepare()
        try Data("broken".utf8).write(to: dir.appendingPathComponent("settings.json"))
        #expect(throws: (any Error).self) { try storage.loadSettings() }
    }
    @Test func roundTripPreservesChoices() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = Storage(directory: dir); var settings = enabled
        settings.excluded = [app.id]; settings.heldVersions["store:123"] = "2.0"
        try storage.saveSettings(settings)
        #expect(try storage.loadSettings() == settings)
    }
    @Test func overlappingRunsAreRefused() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = Storage(directory: dir); let first = try storage.lock()
        defer { withExtendedLifetime(first) {} }
        #expect(throws: (any Error).self) { try storage.lock() }
    }
    @Test func onlyStableOfficialAppCasksAreAutomatic() throws {
        let inventory = [app]
        let json = #"{"casks":[{"token":"firefox","version":"131.0","installed":"130.0","tap":"homebrew/cask","artifacts":[{"app":["Firefox.app"]},{"zap":[{}]}]}]}"#
        let mapped = try Providers.parseCasks(Data(json.utf8), inventory: inventory)
        #expect(mapped.count == 1); #expect(mapped.first?.automatic == true)
        #expect(mapped.first?.availableVersion == "131.0")
        let installer = json.replacingOccurrences(of: #"{"app":["Firefox.app"]}"#, with: #"{"app":["Firefox.app"]},{"pkg":["Installer.pkg"]}"#)
        #expect(try Providers.parseCasks(Data(installer.utf8), inventory: inventory).first?.automatic == false)
        let beta = json.replacingOccurrences(of: "131.0", with: "131.0-beta")
        #expect(try Providers.parseCasks(Data(beta.utf8), inventory: inventory).first?.automatic == false)
    }
    @Test func serviceUninstallArtifactsRequireManualHandling() throws {
        let json = #"{"casks":[{"token":"firefox","version":"131.0","installed":"130.0","tap":"homebrew/cask","artifacts":[{"app":["Firefox.app"],"target":"/Applications/Firefox.app"},{"uninstall":[{"launchctl":"vendor.service"}]}]}]}"#
        #expect(try Providers.parseCasks(Data(json.utf8), inventory: [app]).first?.automatic == false)
        let quitOnly = json.replacingOccurrences(of: "launchctl", with: "quit")
        #expect(try Providers.parseCasks(Data(quitOnly.utf8), inventory: [app]).first?.automatic == true)
    }
    @Test func recognizesAppStoreDataVolumeAliases() {
        #expect(Providers.canonicalAppPath("/System/Volumes/Data/Applications/Fixture.app") == "/Applications/Fixture.app")
        #expect(Providers.canonicalAppPath("/Applications/Fixture.app") == "/Applications/Fixture.app")
        #expect(Providers.canonicalAppPath("/System/Library/Fixture.app") == "/System/Library/Fixture.app")
    }
    @Test func acceptsJSONStreamAndRejectsToolNoise() throws {
        let rows = try Providers.jsonRecords(Data("{\"adamID\":123}\n{\"adamID\":456}\n".utf8))
        #expect(rows.count == 2)
        #expect(throws: (any Error).self) { try Providers.jsonRecords(Data("Warning: hello\n".utf8)) }
    }
    @Test(arguments: ["--force", "firefox;id", "../app", "chrome@beta", "", "a b"])
    func rejectsUntrustedTokens(_ token: String) { #expect(!Providers.validToken(token)) }
}
