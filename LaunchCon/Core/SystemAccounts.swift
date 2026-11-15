import Foundation

/// Names of user and group accounts on this machine, listed via `dscl`.
/// Results are cached — directory contents rarely change during a session.
enum SystemAccounts {
    static let userNames: [String] = list(path: "/Users")
    static let groupNames: [String] = list(path: "/Groups")

    private static func list(path: String) -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/dscl")
        process.arguments = [".", "-list", path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return []
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return [] }
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .sorted()
    }
}
