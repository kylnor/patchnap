import Foundation
import Testing
@testable import PatchnapCore

private actor FakeBackend: UpdateBackend {
    let app = InstalledApp(id: "brew:fixture", name: "Fixture", bundleID: "test.fixture", path: "/not/a/real/app", installedVersion: "1.0", availableVersion: "2.0", provider: .homebrew, token: "fixture")
    var installed: [String] = []
    var installedResult = "2.0"
    var changedDeveloper = false
    var failedProviders: Set<Provider> = []
    func discover(refresh: Bool) -> Discovery { Discovery(apps: [app], errors: [], failedProviders: failedProviders) }
    func install(_ app: InstalledApp) { installed.append(app.id) }
    func signingIdentity(_ app: InstalledApp) -> SigningIdentity {
        SigningIdentity(team: changedDeveloper && !installed.isEmpty ? "OTHERTEAM" : "FIXTURETEAM", bundleID: app.bundleID)
    }
    func installedVersion(_ app: InstalledApp) -> String { installedResult }
    func configure(version: String = "2.0", changedDeveloper: Bool = false, failed: Set<Provider> = []) {
        installedResult = version; self.changedDeveloper = changedDeveloper; failedProviders = failed
    }
}
private actor ConditionsSequence {
    var readings: [Conditions]
    init(_ readings: [Conditions]) { self.readings = readings }
    func next() -> Conditions { readings.count > 1 ? readings.removeFirst() : readings[0] }
}
struct EngineTests {
    var ready: Conditions { Conditions(onPower: true, idleSeconds: 900, runningBundleIDs: []) }
    func storage() throws -> Storage {
        let storage = Storage(directory: FileManager.default.temporaryDirectory.appendingPathComponent("patchnap-test-\(UUID().uuidString)"))
        var settings = Settings(); settings.enabled = true; try storage.saveSettings(settings)
        return storage
    }
    @Test func verifiedUpdateIsRecorded() async throws {
        let storage = try storage(); defer { try? FileManager.default.removeItem(at: storage.directory) }
        let backend = FakeBackend(); let ready = ready
        let result = try await Engine(storage: storage, providers: backend, conditions: { ready }).run(forceCheck: true)
        #expect(await backend.installed.count == 1)
        #expect(result.history.first?.outcome == .updated)
        #expect(result.apps.first?.installedVersion == "2.0")
    }
    @Test func userReturningBeforeInstallDefersIt() async throws {
        let storage = try storage(); defer { try? FileManager.default.removeItem(at: storage.directory) }
        let backend = FakeBackend()
        let readings = ConditionsSequence([ready, Conditions(onPower: true, idleSeconds: 1, runningBundleIDs: [])])
        let result = try await Engine(storage: storage, providers: backend, conditions: { await readings.next() }).run(forceCheck: true)
        #expect(await backend.installed.isEmpty); #expect(result.history.isEmpty)
    }
    @Test func successfulExitWithoutVersionChangeIsNotSuccess() async throws {
        let storage = try storage(); defer { try? FileManager.default.removeItem(at: storage.directory) }
        let backend = FakeBackend(); await backend.configure(version: "1.0"); let ready = ready
        let result = try await Engine(storage: storage, providers: backend, conditions: { ready }).run(forceCheck: true)
        #expect(result.history.first?.outcome == .needsAttention)
        #expect(result.attempts["brew:fixture"]?.failures == 1)
        #expect(result.apps.first?.installedVersion == "1.0")
    }
    @Test func changedDeveloperRequiresAttention() async throws {
        let storage = try storage(); defer { try? FileManager.default.removeItem(at: storage.directory) }
        let backend = FakeBackend(); await backend.configure(changedDeveloper: true); let ready = ready
        let result = try await Engine(storage: storage, providers: backend, conditions: { ready }).run(forceCheck: true)
        #expect(result.history.first?.outcome == .needsAttention)
        #expect(result.history.first?.message.contains("different developer") == true)
    }
    @Test func unrelatedProviderFailureDoesNotBlockAnUpdate() async throws {
        let storage = try storage(); defer { try? FileManager.default.removeItem(at: storage.directory) }
        let backend = FakeBackend(); await backend.configure(failed: [.appStore]); let ready = ready
        let result = try await Engine(storage: storage, providers: backend, conditions: { ready }).run(forceCheck: true)
        #expect(result.history.first?.outcome == .updated)
    }
    @Test func sameProviderFailurePreventsInstallation() async throws {
        let storage = try storage(); defer { try? FileManager.default.removeItem(at: storage.directory) }
        let backend = FakeBackend(); await backend.configure(failed: [.homebrew]); let ready = ready
        _ = try await Engine(storage: storage, providers: backend, conditions: { ready }).run(forceCheck: true)
        #expect(await backend.installed.isEmpty)
    }
    @Test func readOnlyCheckNeverInstallsEvenWhenEnabledAndIdle() async throws {
        let storage = try storage(); defer { try? FileManager.default.removeItem(at: storage.directory) }
        let backend = FakeBackend(); let ready = ready
        _ = try await Engine(storage: storage, providers: backend, conditions: { ready }).run(forceCheck: true, install: false)
        #expect(await backend.installed.isEmpty)
    }
}
