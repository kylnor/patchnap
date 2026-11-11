import Foundation
import Darwin

public struct CommandResult: Sendable {
    public var status: Int32
    public var output: String
    public var error: String
}

public actor CommandRunner {
    public init() {}
    public func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 120,
                    environment additions: [String: String] = [:]) async throws -> CommandResult {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("patchnap-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: dir) }
        let outURL = dir.appendingPathComponent("out"), errURL = dir.appendingPathComponent("err")
        fm.createFile(atPath: outURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        fm.createFile(atPath: errURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let out = try FileHandle(forWritingTo: outURL), err = try FileHandle(forWritingTo: errURL)
        defer { try? out.close(); try? err.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let inherited = ProcessInfo.processInfo.environment
        var env = ["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
                   "HOME": NSHomeDirectory(), "USER": NSUserName(), "LOGNAME": NSUserName(),
                   "LANG": "en_US.UTF-8", "HOMEBREW_NO_AUTO_UPDATE": "1", "HOMEBREW_NO_ANALYTICS": "1",
                   "HOMEBREW_NO_INSTALL_CLEANUP": "1", "HOMEBREW_NO_SUDO": "1",
                   "HOMEBREW_NO_UPGRADE_QUIT_CASKS": "1"]
        if let value = inherited["TMPDIR"] { env["TMPDIR"] = value }
        for (key, value) in additions { env[key] = value }
        process.environment = env
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = out; process.standardError = err
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        do {
            while process.isRunning {
                try Task.checkCancellation()
                if Date() >= deadline { throw PatchnapError.message("The update tool timed out. Check the app before retrying.") }
                try await Task.sleep(for: .milliseconds(150))
            }
        } catch {
            if process.isRunning {
                process.terminate()
                for _ in 0..<20 where process.isRunning { try? await Task.sleep(for: .milliseconds(100)) }
                if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
            }
            process.waitUntilExit()
            throw error
        }
        process.waitUntilExit()
        return CommandResult(status: process.terminationStatus,
                             output: String(decoding: (try? Data(contentsOf: outURL)) ?? Data(), as: UTF8.self),
                             error: String(decoding: (try? Data(contentsOf: errURL)) ?? Data(), as: UTF8.self))
    }
}

public struct ToolPaths: Sendable {
    public var brew: String?
    public var mas: String?
    public var helper = "/Library/PrivilegedHelperTools/com.patchnap.store-helper"
    public init() {
        brew = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first { FileManager.default.isExecutableFile(atPath: $0) }
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/mas").path
        mas = [bundled, "/opt/homebrew/bin/mas", "/usr/local/bin/mas"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
