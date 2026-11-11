import Foundation

public struct SigningIdentity: Equatable, Sendable {
    public var team: String
    public var bundleID: String
}
public enum Signature {
    public static func inspect(_ app: InstalledApp, runner: CommandRunner) async throws -> SigningIdentity {
        let verification = try await runner.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path], timeout: 60)
        let detail = try await runner.run("/usr/bin/codesign", ["--display", "--verbose=4", app.path], timeout: 30)
        guard verification.status == 0, detail.status == 0 else { throw PatchnapError.message("The app's developer signature could not be verified.") }
        let fields = detail.error.split(whereSeparator: \.isNewline)
        guard let team = fields.first(where: { $0.hasPrefix("TeamIdentifier=") }).map({ String($0.dropFirst("TeamIdentifier=".count)) }),
              !team.isEmpty, team != "not set",
              let identifier = fields.first(where: { $0.hasPrefix("Identifier=") }).map({ String($0.dropFirst("Identifier=".count)) }),
              identifier == app.bundleID else { throw PatchnapError.message("The app's signed developer identity is missing or does not match.") }
        return SigningIdentity(team: team, bundleID: identifier)
    }
}
