import Foundation
import CryptoKit

public enum DirectInstaller {
    public static func install(_ app: InstalledApp, runner: CommandRunner) async throws {
        guard let download = app.download, app.provider == .catalog, app.automatic,
              download.url.scheme == "https", ["dmg", "zip"].contains(download.archive),
              download.sha256.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil else {
            throw PatchnapError.message("This app has no verified download recipe.")
        }
        let original = URL(fileURLWithPath: app.path)
        let parent = original.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path), original.pathExtension == "app",
              try original.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
            throw PatchnapError.message("This app's location needs administrator permission. Update it manually.")
        }
        let identity = try await Signature.inspect(app, runner: runner)
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("patchnap-download-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: work) }
        let archive = work.appendingPathComponent("download." + download.archive)
        let fetched = try await runner.run("/usr/bin/curl", ["--fail", "--silent", "--show-error", "--location", "--proto", "=https", "--proto-redir", "=https", "--max-time", "600", "--max-filesize", "2147483648", "--output", archive.path, download.url.absoluteString], timeout: 620)
        guard fetched.status == 0, try digest(archive) == download.sha256 else { throw PatchnapError.message("The download failed or its checksum did not match. The installed app was left alone.") }
        let extracted = work.appendingPathComponent("extracted")
        try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: false)
        var mounted = false
        do {
            let unpacked: CommandResult
            if download.archive == "zip" {
                unpacked = try await unpackZip(archive, into: extracted, runner: runner)
            } else {
                unpacked = try await runner.run("/usr/bin/hdiutil", ["attach", "-readonly", "-nobrowse", "-noautoopen", "-mountpoint", extracted.path, archive.path], timeout: 120)
                mounted = unpacked.status == 0
            }
            guard unpacked.status == 0 else { throw PatchnapError.message("The verified download could not be opened. The installed app was left alone.") }
            let source = try findApp(in: extracted, name: original.lastPathComponent)
            let stage = parent.appendingPathComponent(".patchnap-stage-\(UUID().uuidString).app")
            defer { try? FileManager.default.removeItem(at: stage) }
            let copied = try await runner.run("/usr/bin/ditto", [source.path, stage.path], timeout: 240)
            guard copied.status == 0 else { throw PatchnapError.message("The downloaded app could not be staged. The installed app was left alone.") }
            if mounted {
                let detached = try await runner.run("/usr/bin/hdiutil", ["detach", extracted.path], timeout: 60)
                guard detached.status == 0 else { throw PatchnapError.message("The update disk image could not be detached. The installed app was left alone.") }
                mounted = false
            }
            var stagedApp = app; stagedApp.path = stage.path
            guard try await Signature.inspect(stagedApp, runner: runner) == identity else { throw PatchnapError.message("The download was signed by a different developer. The installed app was left alone.") }
            let assess = try await runner.run("/usr/sbin/spctl", ["--assess", "--type", "execute", stage.path], timeout: 120)
            guard assess.status == 0 else { throw PatchnapError.message("Gatekeeper did not accept the downloaded app. The installed app was left alone.") }
            try await validateCompatibility(stage, runner: runner)
            let version = try readVersion(stage, expectedID: app.bundleID)
            guard let target = app.availableVersion, version.compare(target, options: .numeric) != .orderedAscending,
                  version.compare(app.installedVersion, options: .numeric) == .orderedDescending else { throw PatchnapError.message("The downloaded app's version did not match the expected update.") }
            // No user-writable code executes before identity and Gatekeeper verification.
            let quarantine = "0083;\(String(Int(Date().timeIntervalSince1970), radix: 16));Patchnap;"
            let marked = try await runner.run("/usr/bin/xattr", ["-w", "com.apple.quarantine", quarantine, stage.path], timeout: 15)
            guard marked.status == 0 else { throw PatchnapError.message("The downloaded app could not retain its download security marker.") }
            let settings = try Storage().loadSettings()
            let conditions = await SystemConditions.read()
            guard Policy.evaluate(app, settings: settings, conditions: conditions) == .eligible else { throw PatchnapError.message("Conditions changed during download. The installed app was left alone; the update will retry later.") }
            guard try readVersion(original, expectedID: app.bundleID) == app.installedVersion,
                  try await Signature.inspect(app, runner: runner) == identity else { throw PatchnapError.message("The installed app changed during download. Waiting for a new check.") }
            try await replace(staged: stage, original: original) {
                guard try readVersion(original, expectedID: app.bundleID) == version,
                      try await Signature.inspect(app, runner: runner) == identity else { throw PatchnapError.message("The installed update failed verification.") }
            }
        } catch {
            if mounted { _ = try? await runner.run("/usr/bin/hdiutil", ["detach", extracted.path], timeout: 60) }
            throw error
        }
    }
    public static func validateCompatibility(_ bundleURL: URL, runner: CommandRunner) async throws {
        guard let bundle = Bundle(url: bundleURL), let executable = bundle.executableURL else { throw PatchnapError.message("The downloaded app has no executable.") }
        let current = ProcessInfo.processInfo.operatingSystemVersion
        let version = "\(current.majorVersion).\(current.minorVersion).\(current.patchVersion)"
        if let minimum = bundle.object(forInfoDictionaryKey: "LSMinimumSystemVersion") as? String,
           version.compare(minimum, options: .numeric) == .orderedAscending {
            throw PatchnapError.message("The downloaded app requires a newer macOS release.")
        }
        let architectures = try await runner.run("/usr/bin/lipo", ["-archs", executable.path], timeout: 30)
        guard architectures.status == 0, architectures.output.split(whereSeparator: \.isWhitespace).contains(Substring(Catalog.currentArchitecture)) else {
            throw PatchnapError.message("The downloaded app does not support this Mac's architecture.")
        }
    }

    public static func unpackZip(_ archive: URL, into directory: URL, runner: CommandRunner) async throws -> CommandResult {
        // macOS bsdtar's default secure extraction refuses .. and traversal through symlinks.
        // Never add -P (which disables those protections). No recipe code is run.
        try await runner.run("/usr/bin/tar", ["--safe-writes", "--no-same-owner", "-xf", archive.path, "-C", directory.path], timeout: 240)
    }
    public static func replace(staged: URL, original: URL, verify: @Sendable () async throws -> Void) async throws {
        let backupName = ".patchnap-backup-\(UUID().uuidString).app"
        let backup = original.deletingLastPathComponent().appendingPathComponent(backupName)
        _ = try FileManager.default.replaceItemAt(original, withItemAt: staged, backupItemName: backupName, options: .withoutDeletingBackupItem)
        do { try await verify() }
        catch {
            do { _ = try FileManager.default.replaceItemAt(original, withItemAt: backup) }
            catch { throw PatchnapError.message("The update failed and rollback could not complete. The original backup is retained at \(backup.path).") }
            throw error
        }
        try? FileManager.default.removeItem(at: backup)
    }

    public static func digest(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
    public static func readVersion(_ url: URL, expectedID: String) throws -> String {
        let data = try Data(contentsOf: url.appendingPathComponent("Contents/Info.plist"))
        let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        guard info?["CFBundleIdentifier"] as? String == expectedID, let version = info?["CFBundleShortVersionString"] as? String else { throw PatchnapError.message("The app's identity or version is missing.") }
        return version
    }
    public static func findApp(in root: URL, name: String) throws -> URL {
        var matches: [URL] = []
        if let iterator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [.skipsHiddenFiles]) {
            for case let url as URL in iterator where url.pathExtension == "app" {
                iterator.skipDescendants()
                if url.lastPathComponent == name {
                    guard try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { continue }
                    matches.append(url)
                }
            }
        }
        guard matches.count == 1, let app = matches.first else { throw PatchnapError.message("The download did not contain exactly one expected app.") }
        return app
    }
}
