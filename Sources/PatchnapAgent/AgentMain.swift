import Foundation
import PatchnapCore

@main struct PatchnapAgent {
    static func main() async {
        let arguments = Set(CommandLine.arguments.dropFirst())
        let accepted: Set<String> = ["--check", "--dry-run", "--json"]
        guard arguments.isSubset(of: accepted) else {
            FileHandle.standardError.write(Data("Usage: patchnap-agent [--check] [--dry-run] [--json]\n".utf8)); exit(64)
        }
        do {
            let snapshot = try await Engine().run(forceCheck: arguments.contains("--check"), install: !arguments.contains("--check") && !arguments.contains("--dry-run"))
            if arguments.contains("--json") {
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                FileHandle.standardOutput.write(try encoder.encode(snapshot)); print()
            } else { print(snapshot.message) }
        } catch {
            FileHandle.standardError.write(Data("Patchnap: \(error.localizedDescription)\n".utf8)); exit(1)
        }
    }
}
