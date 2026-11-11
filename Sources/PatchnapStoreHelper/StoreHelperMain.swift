import Foundation
import Darwin
import CryptoKit
import AppKit
import PatchnapCore

// This root entry point deliberately accepts one operation and one decimal ID.
// No caller-controlled executable, environment, path, script, or extra argument is accepted.
@main struct StoreHelper {
    static let masPath = "/Library/Application Support/Patchnap/mas"
    static let manifestPath = "/Library/Application Support/Patchnap/mas.sha256"
    static func main() async {
        do {
            guard geteuid() == 0, CommandLine.arguments.count == 3,
                  CommandLine.arguments[1] == "update" else { throw PatchnapError.message("Expected update and one installed App Store ID, with administrator authority.") }
            let id = CommandLine.arguments[2]
            guard id.range(of: #"^[0-9]{1,18}$"#, options: .regularExpression) != nil else { throw PatchnapError.message("Invalid App Store ID.") }
            // A root-owned copy is essential: Homebrew executables are user-writable.
            try checkTrustedPath(masPath); try checkTrustedPath(manifestPath)
            let expected = try String(contentsOfFile: manifestPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
            let actual = SHA256.hash(data: try Data(contentsOf: URL(fileURLWithPath: masPath))).map { String(format: "%02x", $0) }.joined()
            guard expected.count == 64, expected == actual else { throw PatchnapError.message("The App Store tool's integrity check failed. Reinstall the helper.") }
            guard let console = SCDynamicStoreCopyConsoleUser(nil, nil, nil) as String?,
                  console != "loginwindow", console != "root", console == ProcessInfo.processInfo.environment["SUDO_USER"] else {
                throw PatchnapError.message("The requesting user must be the active Mac user.")
            }
            let runner = CommandRunner()
            let located = try await runner.run("/usr/bin/mdfind", ["kMDItemAppStoreAdamID == \(id)"], timeout: 30)
            guard located.status == 0 else { throw PatchnapError.message("Cannot verify this app is installed.") }
            let paths = Array(Set(located.output.split(whereSeparator: \.isNewline).map { Providers.canonicalAppPath(String($0)) }.filter { $0.hasSuffix(".app") }))
            guard paths.count == 1, let path = paths.first,
                  FileManager.default.fileExists(atPath: path + "/Contents/_MASReceipt/receipt"),
                  let bundle = Bundle(path: path), let bundleID = bundle.bundleIdentifier else {
                throw PatchnapError.message("Only one already-installed App Store app may be updated.")
            }
            let conditions = SystemConditions.read()
            guard conditions.onPower == true, let idle = conditions.idleSeconds, idle >= 600,
                  let running = conditions.runningBundleIDs, !running.contains(bundleID) else {
                throw PatchnapError.message("Waiting for external power, idle time, and a closed app.")
            }
            // Inspect all users' process executable paths too: root NSWorkspace alone can lack the GUI session.
            let processes = try await runner.run("/bin/ps", ["-axo", "comm="], timeout: 15)
            guard processes.status == 0,
                  !processes.output.split(whereSeparator: \.isNewline).contains(where: { Providers.canonicalAppPath(String($0)).hasPrefix(path + "/") }) else {
                throw PatchnapError.message("The app is still running.")
            }
            let result = try await runner.run(masPath, ["update", id], timeout: 1200, environment: ["SUDO_USER": console])
            guard result.status == 0 else { throw PatchnapError.message("App Store could not finish this update. Check Apple Account sign-in.") }
            print("App Store update finished; caller must verify the installed version.")
        } catch {
            FileHandle.standardError.write(Data("Patchnap: \(error.localizedDescription)\n".utf8)); exit(1)
        }
    }
    static func checkTrustedPath(_ path: String) throws {
        var current = URL(fileURLWithPath: path)
        while current.path != "/" {
            var info = stat()
            guard lstat(current.path, &info) == 0, info.st_uid == 0,
                  info.st_mode & 0o022 == 0, info.st_mode & S_IFMT != S_IFLNK else {
                throw PatchnapError.message("The installation helper requires root-owned, non-writable files and directories.")
            }
            current.deleteLastPathComponent()
        }
    }
}

import SystemConfiguration
