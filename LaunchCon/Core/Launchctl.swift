import Foundation

enum LaunchctlError: Error, CustomStringConvertible {
    case executableNotFound
    case commandFailed(command: String, status: Int32, stderr: String)
    case invalidOutput(String)

    var description: String {
        switch self {
        case .executableNotFound:
            return "launchctl executable not found"
        case let .commandFailed(command, status, stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "`\(command)` exited with status \(status)\(detail.isEmpty ? "" : ": \(detail)")"
        case let .invalidOutput(output):
            return "Could not parse launchctl output: \(output.prefix(200))"
        }
    }
}

/// Async wrapper around the `launchctl` command-line tool.
enum Launchctl {

    // MARK: - Listing

    /// Lists jobs in a domain by parsing `launchctl print <domain>` output.
    /// (`launchctl list` only works for the caller's own domain on modern macOS.)
    static func list(domain: LaunchdDomain) async throws -> [Job] {
        let output = try await run(["print", domain.rawValue])
        let rows = DomainPrintParser.services(output)
        return rows.map { row in
            Job(
                label: row.label,
                pid: row.pid,
                lastExitStatus: row.status,
                domain: domain,
                plistPath: nil,
                isLoaded: true,
                isDisabled: false,
                plist: nil
            )
        }
    }

    /// Lists jobs in the caller's own domain via `launchctl list`.
    /// Only valid when the process runs inside the target user's session.
    static func listCurrentDomain(extended: Bool = false) async throws -> [Job] {
        var args = ["list"]
        if extended { args.append("-x") }
        let output = try await run(args)
        let rows = JobListParser.parse(output)
        return rows.map { row in
            Job(
                label: row.label,
                pid: row.pid,
                lastExitStatus: row.status,
                domain: .guiCurrentUser,
                plistPath: nil,
                isLoaded: true,
                isDisabled: false,
                plist: nil
            )
        }
    }

    /// Prints detailed state for a single service.
    /// Equivalent to `launchctl print <domain>/<label>`.
    @discardableResult
    static func printService(domain: LaunchdDomain, label: String) async throws -> String {
        try await run(["print", domain.service(label)])
    }

    /// Returns the set of disabled service identifiers for a domain.
    /// Parses `launchctl print-disabled <domain>` output.
    static func printDisabled(domain: LaunchdDomain) async throws -> Set<String> {
        let output = try await run(["print-disabled", domain.rawValue])
        return DisabledListParser.parse(output)
    }

    // MARK: - Loading / unloading

    /// Bootstraps a plist into a domain. Equivalent to
    /// `launchctl bootstrap <domain> <plistPath>`.
    static func load(plistPath: String, domain: LaunchdDomain) async throws {
        try await runThrowing(["bootstrap", domain.rawValue, plistPath])
    }

    /// Legacy load: `launchctl load [-w] <plistPath>`.
    static func loadLegacy(plistPath: String, disabledByDefault: Bool = false) async throws {
        var args = ["load"]
        if disabledByDefault { args.append("-D") }
        args.append(plistPath)
        try await runThrowing(args)
    }

    /// Boots out a service. Equivalent to `launchctl bootout <domain>/<label>`.
    static func unload(label: String, domain: LaunchdDomain) async throws {
        try await runThrowing(["bootout", domain.service(label)])
    }

    /// Legacy unload: `launchctl unload [-w] <plistPath>`.
    static func unloadLegacy(plistPath: String) async throws {
        try await runThrowing(["unload", plistPath])
    }

    // MARK: - Enable / disable

    static func enable(label: String, domain: LaunchdDomain) async throws {
        try await runThrowing(["enable", domain.service(label)])
    }

    static func disable(label: String, domain: LaunchdDomain) async throws {
        try await runThrowing(["disable", domain.service(label)])
    }

    /// Disables/enables by plist path via `launchctl load/unload -w`.
    static func setDisabled(plistPath: String, disabled: Bool) async throws {
        try await runThrowing([disabled ? "unload" : "load", "-w", plistPath])
    }

    // MARK: - Start / stop

    /// Starts (or restarts with `killFirst`) a service.
    /// Equivalent to `launchctl kickstart [-k] <domain>/<label>`.
    static func kickstart(label: String, domain: LaunchdDomain, killFirst: Bool = false) async throws {
        var args = ["kickstart"]
        if killFirst { args.append("-k") }
        args.append(domain.service(label))
        try await runThrowing(args)
    }

    /// Sends SIGTERM to a running service. Equivalent to `launchctl kill TERM <service>`.
    static func kill(label: String, domain: LaunchdDomain, signal: String = "TERM") async throws {
        try await runThrowing(["kill", signal, domain.service(label)])
    }

    /// Removes a service definition from a domain without bootstrapping.
    /// Equivalent to `launchctl remove <label>` (legacy) — use with care.
    static func remove(label: String, domain: LaunchdDomain) async throws {
        try await runThrowing(["remove", domain.service(label)])
    }

    // MARK: - Process runner

    private static let executableURL = URL(fileURLWithPath: "/bin/launchctl")

    /// Runs launchctl and returns stdout. Throws on non-zero exit.
    @discardableResult
    static func run(_ arguments: [String]) async throws -> String {
        let (stdout, stderr, status) = try await launchctl(arguments)
        guard status == 0 else {
            throw LaunchctlError.commandFailed(
                command: "launchctl \(arguments.joined(separator: " "))",
                status: status,
                stderr: stderr
            )
        }
        return stdout
    }

    private static func runThrowing(_ arguments: [String]) async throws {
        _ = try await run(arguments)
    }

    /// Low-level process execution. Returns (stdout, stderr, exitStatus).
    static func launchctl(_ arguments: [String]) async throws -> (stdout: String, stderr: String, status: Int32) {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            process.terminationHandler = { proc in
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""
                continuation.resume(returning: (stdout, stderr, proc.terminationStatus))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: LaunchctlError.executableNotFound)
            }
        }
    }
}

// MARK: - Output parsers

/// One row of `launchctl list` output.
struct JobListRow {
    var pid: Int?
    var status: Int?
    var label: String
}

enum JobListParser {
    /// Parses `launchctl list` output:
    ///
    ///     PID\tStatus\tLabel
    ///     -\t0\tcom.apple.foo
    ///     1234\t1\tcom.example.bar
    ///
    /// Tolerant of extra columns (e.g. `-x` output): the label is always the
    /// last whitespace-separated field and pid/status are parsed from the
    /// leading numeric fields when present.
    static func parse(_ output: String) -> [JobListRow] {
        var rows: [JobListRow] = []
        for rawLine in output.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("PID") || line.hasPrefix("-") && line.contains("Status") {
                continue
            }
            let fields = line.split(whereSeparator: { $0 == "\t" || $0 == " " }).map(String.init)
            guard let label = fields.last, !label.isEmpty else { continue }

            // Skip banner/section lines that aren't job rows.
            guard fields.count >= 3 || label.contains(".") else { continue }

            var pid: Int?
            var status: Int?
            if let first = fields.first, first != "-", let value = Int(first) {
                pid = value
            }
            // Status is the field before the label when there are >=3 fields.
            if fields.count >= 3, let statusField = fields.dropLast().last, statusField != "-",
               let value = Int(statusField) {
                status = value
            }
            rows.append(JobListRow(pid: pid, status: status, label: label))
        }
        return rows
    }
}

enum DomainPrintParser {
    /// Parses the `services = { ... }` block of `launchctl print <domain>`:
    ///
    ///     services = {
    ///            0      0 \tcom.example.foo
    ///        41614   (pe) \tcom.apple.bar
    ///     }
    ///
    /// Columns are PID, status-or-flags, label. PID `0` means not running;
    /// non-numeric status fields like `(pe)` are treated as nil.
    static func services(_ output: String) -> [JobListRow] {
        var rows: [JobListRow] = []
        var inServices = false

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if !inServices {
                if line.hasPrefix("services") && line.contains("{") {
                    inServices = true
                }
                continue
            }
            if line == "}" { break }
            if line.isEmpty { continue }

            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard fields.count >= 3, let label = fields.last else { continue }

            var pid: Int?
            if let first = fields.first.flatMap(Int.init), first > 0 {
                pid = first
            }
            var status: Int?
            if fields.count >= 3, let value = Int(fields[1]) {
                status = value
            }
            rows.append(JobListRow(pid: pid, status: status, label: label))
        }
        return rows
    }
}

enum DisabledListParser {
    /// Parses `launchctl print-disabled <domain>` output, which looks like:
    ///
    ///     disabled services = {
    ///             "com.example.foo" => disabled
    ///             "com.example.bar" => enabled
    ///     }
    ///
    /// Returns the set of labels marked `disabled`.
    static func parse(_ output: String) -> Set<String> {
        var disabled = Set<String>()
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasSuffix("=> disabled") else { continue }
            // Extract the quoted label.
            if let start = trimmed.firstIndex(of: "\""),
               let end = trimmed[start...].dropFirst().firstIndex(of: "\"") {
                let label = String(trimmed[trimmed.index(after: start)..<end])
                disabled.insert(label)
            }
        }
        return disabled
    }
}
