import Foundation
import Darwin

public struct Storage: Sendable {
    public let directory: URL
    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Patchnap", isDirectory: true)
    }
    public func prepare() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
    }
    public func loadSettings() throws -> Settings { try load("settings.json", fallback: Settings()) }
    public func loadSnapshot() throws -> Snapshot { try load("state.json", fallback: Snapshot()) }
    public func saveSettings(_ value: Settings) throws { try save(value, name: "settings.json") }
    public func saveSnapshot(_ value: Snapshot) throws { try save(value, name: "state.json") }
    private func load<T: Decodable>(_ name: String, fallback: T) throws -> T {
        let path = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: path.path) else { return fallback }
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: path))
    }
    private func save<T: Encodable>(_ value: T, name: String) throws {
        try prepare()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let url = directory.appendingPathComponent(name)
        try encoder.encode(value).write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    public func lock() throws -> RunLock {
        try prepare()
        return try RunLock(path: directory.appendingPathComponent("run.lock").path)
    }
}

public final class RunLock {
    private let descriptor: Int32
    public init(path: String) throws {
        descriptor = Darwin.open(path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw PatchnapError.message("Cannot create the updater lock.") }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            throw PatchnapError.message("Another Patchnap check is already running.")
        }
    }
    deinit { flock(descriptor, LOCK_UN); close(descriptor) }
}

public enum PatchnapError: Error, LocalizedError, Sendable {
    case message(String)
    public var errorDescription: String? { if case let .message(text) = self { text } else { nil } }
}
