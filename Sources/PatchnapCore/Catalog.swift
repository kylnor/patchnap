import Foundation

public struct CatalogDownload: Codable, Equatable, Sendable {
    public var url: URL
    public var sha256: String
    public var archive: String
}
public enum Catalog {
    public static let endpoint = "https://formulae.brew.sh/api/cask.json"
    public static func load(runner: CommandRunner, refresh: Bool) async throws -> Data {
        let storage = Storage(); try storage.prepare()
        let cache = storage.directory.appendingPathComponent("public-catalog.json")
        if !refresh, let data = try? Data(contentsOf: cache) { return data }
        let temporary = storage.directory.appendingPathComponent("catalog-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let result = try await runner.run("/usr/bin/curl", ["--fail", "--silent", "--show-error", "--proto", "=https", "--max-time", "90", "--max-filesize", "30000000", "--output", temporary.path, endpoint], timeout: 100)
        guard result.status == 0 else { throw PatchnapError.message("The app catalog could not be downloaded.") }
        let data = try Data(contentsOf: temporary)
        guard let entries = try JSONSerialization.jsonObject(with: data) as? [[String: Any]], !entries.isEmpty else { throw PatchnapError.message("The app catalog was unreadable.") }
        try data.write(to: cache, options: .atomic)
        return data
    }
    public static func match(_ data: Data, inventory: [InstalledApp], osMajor: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
                             architecture: String = currentArchitecture) throws -> [InstalledApp] {
        guard let entries = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw PatchnapError.message("The app catalog was unreadable.") }
        var matches: [String: [InstalledApp]] = [:]
        for raw in entries {
            let entry = specialized(raw, osMajor: osMajor, architecture: architecture)
            guard let token = entry["token"] as? String, Providers.validToken(token), !Policy.isPrerelease(token),
                  entry["disabled"] as? Bool != true, let version = entry["version"] as? String, version != "latest", !Policy.isPrerelease(version),
                  let artifacts = entry["artifacts"] as? [[String: Any]],
                  artifacts.allSatisfy({ Set($0.keys).isSubset(of: ["app", "target", "zap", "uninstall", "command_wrapper"]) }),
                  let urlString = entry["url"] as? String, let url = URL(string: urlString), url.scheme == "https",
                  let sha = entry["sha256"] as? String, sha.range(of: #"^[a-fA-F0-9]{64}$"#, options: .regularExpression) != nil,
                  compatible(entry["depends_on"] as? [String: Any] ?? [:], osMajor: osMajor) else { continue }
            // No recipe code, uninstall actions, wrappers or dependencies are ever executed.
            let appNames = artifacts.compactMap { ($0["app"] as? [Any])?.first as? String }
            guard appNames.count == 1, let name = appNames.first, !name.contains("/"), name.hasSuffix(".app") else { continue }
            let archive: String
            let path = url.path.lowercased()
            if path.hasSuffix(".dmg") { archive = "dmg" }
            else if path.hasSuffix(".zip") || (entry["url_specs"] as? [String: Any])?["using"] as? String == "zip" { archive = "zip" }
            else { continue }
            for original in inventory where URL(fileURLWithPath: original.path).lastPathComponent == name {
                guard !FileManager.default.fileExists(atPath: original.path + "/Contents/_MASReceipt/receipt"),
                      !Policy.isPrerelease(original.installedVersion) else { continue }
                var app = original
                app.id = "catalog:\(token)"; app.provider = .catalog; app.token = token; app.automatic = true; app.reason = nil
                let target = version.split(separator: ",").first.map(String.init) ?? version
                app.availableVersion = target.compare(app.installedVersion, options: .numeric) == .orderedDescending ? target : nil
                app.download = CatalogDownload(url: url, sha256: sha.lowercased(), archive: archive)
                matches[original.path, default: []].append(app)
            }
        }
        // A name match is discovery only. Installation additionally requires the existing developer
        // identity, the downloaded bundle's identity, version and Gatekeeper assessment to agree.
        return matches.values.compactMap { $0.count == 1 ? $0[0] : nil }
    }
    public static var currentArchitecture: String {
        #if arch(arm64)
        "arm64"
        #else
        "x86_64"
        #endif
    }
    public static func specialized(_ raw: [String: Any], osMajor: Int, architecture: String) -> [String: Any] {
        let tags = [14: "sonoma", 15: "sequoia", 26: "tahoe", 27: "golden_gate"]
        guard let tag = tags[osMajor], let variations = raw["variations"] as? [String: [String: Any]] else { return raw }
        let key = architecture == "arm64" ? "arm64_\(tag)" : tag
        var entry = raw
        for (name, value) in variations[key] ?? [:] { entry[name] = value }
        return entry
    }
    public static func compatible(_ dependencies: [String: Any], osMajor: Int) -> Bool {
        for key in ["cask", "formula", "arch"] {
            if let value = dependencies[key], (value as? [Any])?.isEmpty != true { return false }
        }
        guard let rules = dependencies["macos"] as? [String: [String]] else { return dependencies["macos"] == nil || (dependencies["macos"] as? [String: Any])?.isEmpty == true }
        let current = ProcessInfo.processInfo.operatingSystemVersion
        let currentText = current.majorVersion == osMajor ? "\(current.majorVersion).\(current.minorVersion).\(current.patchVersion)" : "\(osMajor).0"
        return rules.allSatisfy { operation, versions in
            versions.allSatisfy { version in
                let comparison = currentText.compare(version, options: .numeric)
                switch operation { case ">=": return comparison != .orderedAscending; case ">": return comparison == .orderedDescending; case "<=": return comparison != .orderedDescending; case "<": return comparison == .orderedAscending; case "==", "=": return comparison == .orderedSame; default: return false }
            }
        }
    }
}
