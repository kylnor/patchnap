import Foundation

public struct Discovery: Sendable {
    public var apps: [InstalledApp]
    public var errors: [String]
    public var failedProviders: Set<Provider>
}

public protocol UpdateBackend: Sendable {
    func discover(refresh: Bool) async -> Discovery
    func install(_ app: InstalledApp) async throws
    func signingIdentity(_ app: InstalledApp) async throws -> SigningIdentity
    func installedVersion(_ app: InstalledApp) async throws -> String
}

public struct Providers: UpdateBackend {
    public let runner: CommandRunner
    public let tools: ToolPaths
    public init(runner: CommandRunner = CommandRunner(), tools: ToolPaths = ToolPaths()) { self.runner = runner; self.tools = tools }

    public func discover(refresh: Bool = true) async -> Discovery {
        let inventory = Inventory.installedApps()
        var mapped: [String: InstalledApp] = [:]
        var errors: [String] = []
        var failed: Set<Provider> = []
        if let brew = tools.brew {
            do {
                if refresh {
                    let refreshResult = try await runner.run(brew, ["update", "--quiet"], timeout: 240)
                    guard refreshResult.status == 0 else { throw PatchnapError.message("Homebrew's update catalog could not refresh.") }
                }
                let result = try await runner.run(brew, ["info", "--json=v2", "--cask", "--installed"], timeout: 120)
                guard result.status == 0 else { throw PatchnapError.message("Homebrew's installed apps could not be read.") }
                for app in try Self.parseCasks(Data(result.output.utf8), inventory: inventory) { mapped[app.path] = app }
            } catch { errors.append(error.localizedDescription); failed.insert(.homebrew) }
        }
        if let mas = tools.mas {
            do {
                let installed = try await runner.run(mas, ["list", "--json"], timeout: 90)
                let outdated = try await runner.run(mas, ["outdated", "--json"], timeout: 90)
                guard installed.status == 0, outdated.status == 0 else {
                    throw PatchnapError.message("App Store checks need a working mas installation and an Apple Account signed in to the App Store.")
                }
                for app in try Self.parseStore(installed: Data(installed.output.utf8), outdated: Data(outdated.output.utf8), inventory: inventory) { mapped[app.path] = app }
            } catch { errors.append(error.localizedDescription); failed.insert(.appStore) }
        } else { errors.append("Install mas to check Mac App Store updates."); failed.insert(.appStore) }
        do {
            let catalog = try await Catalog.load(runner: runner, refresh: refresh)
            for app in try Catalog.match(catalog, inventory: inventory.filter { mapped[$0.path] == nil }) { mapped[app.path] = app }
        } catch { errors.append("The standalone-app catalog could not be checked."); failed.insert(.catalog) }
        let apps = inventory.map { mapped[$0.path] ?? $0 }
        return Discovery(apps: apps, errors: errors, failedProviders: failed)
    }

    public static func parseCasks(_ data: Data, inventory: [InstalledApp]) throws -> [InstalledApp] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let casks = root["casks"] as? [[String: Any]] else {
            throw PatchnapError.message("Homebrew returned an unreadable app catalog.")
        }
        return casks.compactMap { cask in
            guard let token = cask["token"] as? String, let version = cask["version"] as? String,
                  let artifacts = cask["artifacts"] as? [[String: Any]] else { return nil }
            let names = artifacts.compactMap { ($0["app"] as? [Any])?.first as? String }
            guard names.count == 1, let appName = names.first,
                  !appName.contains("/"), appName.hasSuffix(".app"),
                  let installed = inventory.first(where: { URL(fileURLWithPath: $0.path).lastPathComponent == appName }) else { return nil }
            // Preserve App Store ownership instead of replacing the app's distribution channel.
            guard !FileManager.default.fileExists(atPath: installed.path + "/Contents/_MASReceipt/receipt") else { return nil }
            let recognized = artifacts.allSatisfy { artifact in
                guard Set(artifact.keys).isSubset(of: ["app", "zap", "target", "uninstall", "command_wrapper"]) else { return false }
                if let actions = artifact["uninstall"] as? [[String: Any]] {
                    return actions.allSatisfy { Set($0.keys).isSubset(of: ["quit"]) }
                }
                return artifact["uninstall"] == nil
            }
            let stable = !token.contains("@") && !Policy.isPrerelease(token) && !Policy.isPrerelease(version) && !Policy.isPrerelease(installed.installedVersion) && version != "latest"
            let official = (cask["tap"] as? String) == "homebrew/cask"
            let enabled = cask["disabled"] as? Bool != true
            let dependencies = cask["depends_on"] as? [String: Any] ?? [:]
            let independent = ["cask", "formula"].allSatisfy { key in
                guard let value = dependencies[key] else { return true }
                return (value as? [String])?.isEmpty == true
            }
            let expected = version.split(separator: ",").first.map(String.init) ?? version
            let catalogInstalled = (cask["installed"] as? String) ?? (cask["installed"] as? [String])?.first
            var app = installed
            app.id = "brew:\(token)"; app.provider = .homebrew; app.token = token
            // Only schedule when the catalog and bundle agree on the current installed version.
            let comparable = catalogInstalled.map { $0.split(separator: ",").first.map(String.init) == app.installedVersion } ?? false
            app.automatic = recognized && stable && official && enabled && comparable && independent
            app.availableVersion = expected.compare(app.installedVersion, options: .numeric) == .orderedDescending ? expected : nil
            if !app.automatic {
                app.reason = !stable ? "This cask has no verified stable version." : !recognized ? "This app uses an installer or extra artifacts that need manual handling." : !official ? "Third-party casks need manual review." : !enabled ? "This cask is disabled." : !independent ? "This cask may install dependencies and needs manual handling." : "The app version could not be matched to Homebrew's installed version."
            } else { app.reason = nil }
            return app
        }
    }

    public static func canonicalAppPath(_ value: String) -> String {
        let path = URL(fileURLWithPath: value).standardizedFileURL.path
        let dataVolume = "/System/Volumes/Data"
        return path.hasPrefix(dataVolume + "/") ? String(path.dropFirst(dataVolume.count)) : path
    }

    public static func jsonRecords(_ data: Data) throws -> [[String: Any]] {
        if data.isEmpty { return [] }
        if let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] { return array }
        return try String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).map { line in
            guard let object = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { throw PatchnapError.message("App Store returned an unreadable record.") }
            return object
        }
    }
    public static func parseStore(installed: Data, outdated: Data, inventory: [InstalledApp]) throws -> [InstalledApp] {
        let pending = try jsonRecords(outdated)
        return try jsonRecords(installed).compactMap { record in
            let id = (record["adamID"] as? NSNumber)?.stringValue ?? (record["adamID"] as? String)
            guard let id, !id.isEmpty, id.allSatisfy(\.isNumber),
                  let app = inventory.first(where: { item in
                      if let path = record["path"] as? String { return canonicalAppPath(item.path) == canonicalAppPath(path) }
                      if let bundle = record["bundleID"] as? String ?? record["bundleId"] as? String { return item.bundleID == bundle }
                      return item.name == record["name"] as? String
                  }) else { return nil }
            guard FileManager.default.fileExists(atPath: app.path + "/Contents/_MASReceipt/receipt") else { return nil }
            var result = app
            result.id = "store:\(id)"; result.provider = .appStore; result.token = id; result.automatic = true; result.reason = nil
            if let newer = pending.first(where: {
                (($0["adamID"] as? NSNumber)?.stringValue ?? $0["adamID"] as? String) == id
            }), let version = newer["newVersion"] as? String ?? newer["version"] as? String,
               version.compare(app.installedVersion, options: .numeric) == .orderedDescending {
                result.availableVersion = version
            }
            return result
        }
    }

    public func install(_ app: InstalledApp) async throws {
        let result: CommandResult
        switch app.provider {
        case .homebrew:
            guard let brew = tools.brew, app.automatic, Self.validToken(app.token) else { throw PatchnapError.message("This Homebrew update needs manual attention.") }
            result = try await runner.run(brew, ["upgrade", "--cask", "--greedy", app.token], timeout: 1200)
        case .appStore:
            guard app.token.allSatisfy(\.isNumber), !app.token.isEmpty,
                  FileManager.default.isExecutableFile(atPath: tools.helper) else { throw PatchnapError.message("Enable App Store installs in Patchnap Settings. A one-time administrator approval is required.") }
            result = try await runner.run("/usr/bin/sudo", ["-n", tools.helper, "update", app.token], timeout: 1200)
        case .catalog:
            try await DirectInstaller.install(app, runner: runner)
            return
        case .unsupported: throw PatchnapError.message("No supported update source for this app yet.")
        }
        guard result.status == 0 else {
            throw PatchnapError.message(app.provider == .appStore ? "App Store installation could not finish. Check App Store sign-in and the installation helper." : "Homebrew could not finish this update. Open the app or check Homebrew before retrying.")
        }
    }

    public func signingIdentity(_ app: InstalledApp) async throws -> SigningIdentity {
        try await Signature.inspect(app, runner: runner)
    }
    public func installedVersion(_ app: InstalledApp) async throws -> String {
        let url = URL(fileURLWithPath: app.path).appendingPathComponent("Contents/Info.plist")
        let data = try Data(contentsOf: url)
        let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        guard let actual = info?["CFBundleShortVersionString"] as? String,
              info?["CFBundleIdentifier"] as? String == app.bundleID else {
            throw PatchnapError.message("The installed app's identity or version could not be read.")
        }
        return actual
    }

    public static func validToken(_ value: String) -> Bool {
        value.range(of: #"^[a-z0-9][a-z0-9-]*$"#, options: .regularExpression) != nil
    }
}
