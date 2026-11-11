import Foundation
import Testing
@testable import PatchnapCore

struct CatalogTests {
    var app: InstalledApp { InstalledApp(id: "bundle:fixture", name: "Fixture", bundleID: "test.fixture", path: "/Applications/Fixture.app", installedVersion: "1.0", provider: .unsupported, token: "", automatic: false) }
    var fixture: String { #"[{"token":"fixture","version":"2.0","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","url":"https://example.com/Fixture.zip","artifacts":[{"app":["Fixture.app"]},{"uninstall":[{"quit":"test.fixture"}]}],"depends_on":{"macos":{">=":["14"]}}}]"# }
    @Test func matchesStandaloneAppWithoutRunningRecipeCode() throws {
        let result = try Catalog.match(Data(fixture.utf8), inventory: [app], osMajor: 14)
        #expect(result.count == 1); #expect(result.first?.provider == .catalog)
        #expect(result.first?.availableVersion == "2.0"); #expect(result.first?.download?.archive == "zip")
    }
    @Test func ambiguousCatalogMatchIsUnsupported() throws {
        let duplicate = fixture.dropLast() + "," + fixture.dropFirst()
        #expect(try Catalog.match(Data(duplicate.utf8), inventory: [app], osMajor: 14).isEmpty)
    }
    @Test func rejectsUnverifiedAndIncompatibleDownloads() throws {
        let invalid = [fixture.replacingOccurrences(of: "https://", with: "http://"),
                       fixture.replacingOccurrences(of: String(repeating: "a", count: 64), with: "no_check"),
                       fixture.replacingOccurrences(of: "2.0", with: "2.0-beta"),
                       fixture.replacingOccurrences(of: "[\"14\"]", with: "[\"99\"]"),
                       fixture.replacingOccurrences(of: "Fixture.zip", with: "Fixture.pkg")]
        for json in invalid { #expect(try Catalog.match(Data(json.utf8), inventory: [app], osMajor: 14).isEmpty) }
    }
    @Test func usesArchitectureAndOSSpecificMetadata() {
        let entry: [String: Any] = ["url": "arm64", "variations": ["sonoma": ["url": "intel"], "arm64_sonoma": ["url": "arm-sonoma"]]]
        #expect(Catalog.specialized(entry, osMajor: 14, architecture: "x86_64")["url"] as? String == "intel")
        #expect(Catalog.specialized(entry, osMajor: 14, architecture: "arm64")["url"] as? String == "arm-sonoma")
    }
    @Test func refusesDependenciesAndUnknownOSRules() {
        #expect(!Catalog.compatible(["formula": ["helper"]], osMajor: 14))
        #expect(!Catalog.compatible(["macos": ["mystery": ["14"]]], osMajor: 14))
        #expect(Catalog.compatible(["macos": [">=": ["14"]]], osMajor: 14))
    }
    @Test func checksumMatchesKnownContent() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("abc".utf8).write(to: file)
        #expect(try DirectInstaller.digest(file) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
    @Test func failedReplacementVerificationRestoresOriginal() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let old = root.appendingPathComponent("Fixture.app"), new = root.appendingPathComponent("staged.app")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: new, withIntermediateDirectories: false)
        try Data("old".utf8).write(to: old.appendingPathComponent("version"))
        try Data("new".utf8).write(to: new.appendingPathComponent("version"))
        do {
            try await DirectInstaller.replace(staged: new, original: old) { throw PatchnapError.message("fixture rejection") }
            Issue.record("Expected the verification failure")
        } catch { #expect(error.localizedDescription.contains("fixture rejection")) }
        #expect(try String(contentsOf: old.appendingPathComponent("version"), encoding: .utf8) == "old")
    }
    @Test func archiveTraversalCannotWriteOutsideExtractionDirectory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let archive = root.appendingPathComponent("unsafe.zip"), output = root.appendingPathComponent("extracted")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
        try Data(base64Encoded: "UEsDBBQAAAAAAIQqa12t4oSOCQAAAAkAAAAKAAAALi4vZXNjYXBlZHVudHJ1c3RlZFBLAQIUAxQAAAAAAIQqa12t4oSOCQAAAAkAAAAKAAAAAAAAAAAAAACAAQAAAAAuLi9lc2NhcGVkUEsFBgAAAAABAAEAOAAAADEAAAAAAA==")!.write(to: archive)
        let result = try await DirectInstaller.unpackZip(archive, into: output, runner: CommandRunner())
        #expect(result.status != 0)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("escaped").path))
    }
}
