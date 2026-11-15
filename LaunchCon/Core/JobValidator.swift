import Foundation

/// A single problem or noteworthy condition found in a job's configuration.
struct Diagnostic: Equatable {
    enum Severity: String {
        case error
        case warning
        case info
    }

    let severity: Severity
    let message: String
    /// The plist key responsible, when applicable (for editor highlighting).
    let key: String?
}

/// Static analysis of a job's plist, LaunchControl-style.
enum JobValidator {

    private static let calendarKeys: Set<String> = [
        "Second", "Minute", "Hour", "Day", "Month", "Weekday",
    ]

    /// Keys launchd has deprecated; still accepted in plists but ignored or
    /// superseded on modern macOS.
    private static let deprecatedKeys: Set<String> = [
        "Umask",
        "SoftResourceLimits",
        "HardResourceLimits",
        "ResourceLimits",
        "TimeOut",
        "ExitTimeOut",
    ]

    static func validate(_ job: Job) -> [Diagnostic] {
        var results: [Diagnostic] = []

        guard let path = job.plistPath else {
            results.append(Diagnostic(
                severity: .info,
                message: "No plist file — this job exists only in the launchd domain",
                key: nil
            ))
            return results
        }

        guard FileManager.default.fileExists(atPath: path) else {
            results.append(Diagnostic(
                severity: .error,
                message: "Plist file does not exist: \(path)",
                key: nil
            ))
            return results
        }

        guard let plist = job.plist ?? Plist.load(URL(fileURLWithPath: path)) else {
            results.append(Diagnostic(
                severity: .error,
                message: "Plist is unreadable or not a dictionary",
                key: nil
            ))
            return results
        }

        // MARK: Label

        if plist["Label"] == nil {
            results.append(Diagnostic(
                severity: .error, message: "Missing required key: Label", key: "Label"))
        } else if let label = plist["Label"] as? String {
            let filename = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            if label != filename {
                results.append(Diagnostic(
                    severity: .warning,
                    message: "Label \"\(label)\" doesn't match filename \"\(filename).plist\"",
                    key: "Label"))
            }
        } else {
            results.append(Diagnostic(
                severity: .error, message: "Label is not a string", key: "Label"))
        }

        // MARK: Program / ProgramArguments

        let program = plist["Program"] as? String
        let arguments = plist["ProgramArguments"] as? [String]
        let hasArguments = !(arguments?.isEmpty ?? true)

        if program == nil && !hasArguments {
            results.append(Diagnostic(
                severity: .error,
                message: "Neither Program nor ProgramArguments is set — the job has nothing to run",
                key: "ProgramArguments"))
        }
        if program != nil && hasArguments {
            results.append(Diagnostic(
                severity: .warning,
                message: "Both Program and ProgramArguments are set; ProgramArguments takes precedence",
                key: "ProgramArguments"))
        }

        if let executable = program ?? arguments?.first, executable.hasPrefix("/") {
            if FileManager.default.fileExists(atPath: executable) {
                if !FileManager.default.isExecutableFile(atPath: executable) {
                    results.append(Diagnostic(
                        severity: .error,
                        message: "Program is not executable: \(executable)",
                        key: program != nil ? "Program" : "ProgramArguments"))
                }
            } else {
                results.append(Diagnostic(
                    severity: .error,
                    message: "Program not found: \(executable)",
                    key: program != nil ? "Program" : "ProgramArguments"))
            }
        }

        // MARK: Paths

        if let workingDir = plist["WorkingDirectory"] as? String, !workingDir.isEmpty {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: workingDir, isDirectory: &isDirectory) {
                if !isDirectory.boolValue {
                    results.append(Diagnostic(
                        severity: .warning,
                        message: "Working directory is not a directory: \(workingDir)",
                        key: "WorkingDirectory"))
                }
            } else {
                results.append(Diagnostic(
                    severity: .warning,
                    message: "Working directory does not exist: \(workingDir)",
                    key: "WorkingDirectory"))
            }
        }

        for key in ["StandardOutPath", "StandardErrorPath"] {
            guard let logPath = plist[key] as? String, !logPath.isEmpty,
                  logPath != "/dev/null" else { continue }
            guard logPath.hasPrefix("/") else {
                results.append(Diagnostic(
                    severity: .warning,
                    message: "\(key) is not an absolute path: \(logPath)", key: key))
                continue
            }
            let directory = (logPath as NSString).deletingLastPathComponent
            if !FileManager.default.fileExists(atPath: directory) {
                results.append(Diagnostic(
                    severity: .warning,
                    message: "\(key) parent directory does not exist: \(directory)", key: key))
            } else if !FileManager.default.isWritableFile(atPath: directory) {
                results.append(Diagnostic(
                    severity: .warning,
                    message: "\(key) parent directory is not writable: \(directory)", key: key))
            }
            if FileManager.default.fileExists(atPath: logPath),
               !FileManager.default.isWritableFile(atPath: logPath) {
                results.append(Diagnostic(
                    severity: .warning,
                    message: "\(key) file is not writable: \(logPath)", key: key))
            }
        }

        // MARK: EnvironmentVariables

        if let env = plist["EnvironmentVariables"] {
            if let dict = env as? [String: Any] {
                for (name, value) in dict {
                    if name.isEmpty {
                        results.append(Diagnostic(
                            severity: .warning,
                            message: "EnvironmentVariables has an empty variable name",
                            key: "EnvironmentVariables"))
                    } else if !(value is String) {
                        results.append(Diagnostic(
                            severity: .warning,
                            message: "EnvironmentVariables.\(name) is not a string",
                            key: "EnvironmentVariables"))
                    }
                }
            } else {
                results.append(Diagnostic(
                    severity: .warning,
                    message: "EnvironmentVariables is not a dictionary",
                    key: "EnvironmentVariables"))
            }
        }

        // MARK: KeepAlive + RunAtLoad

        if keepAliveIsEnabled(plist["KeepAlive"]),
           boolValue(plist["RunAtLoad"]) {
            results.append(Diagnostic(
                severity: .info,
                message: "KeepAlive is set together with RunAtLoad — KeepAlive already keeps the job running",
                key: "KeepAlive"))
        }

        // MARK: Deprecated keys

        for key in plist.keys where deprecatedKeys.contains(key) {
            results.append(Diagnostic(
                severity: .info,
                message: "\(key) is deprecated and may be ignored on modern macOS",
                key: key))
        }

        // MARK: StartCalendarInterval

        if let interval = plist["StartCalendarInterval"] {
            validateCalendarInterval(interval, into: &results)
        }

        return results
    }

    /// Bool interpretation that distinguishes CFBoolean from integers —
    /// `as? Bool` would treat `KeepAlive = 1` as true.
    private static func boolValue(_ value: Any?) -> Bool {
        guard let number = value as? NSNumber else { return false }
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue }
        return false
    }

    /// KeepAlive "enabled" means `true`, a non-empty dictionary of conditions,
    /// or a non-empty array of dictionaries.
    private static func keepAliveIsEnabled(_ value: Any?) -> Bool {
        guard let value else { return false }
        if let dict = value as? [String: Any] { return !dict.isEmpty }
        if let array = value as? [Any] { return !array.isEmpty }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue }
            return number.intValue != 0
        }
        return false
    }

    /// Accepts a dict or array of dicts keyed by Second/Minute/Hour/Day/Month/
    /// Weekday with integer values.
    private static func validateCalendarInterval(_ value: Any, into results: inout [Diagnostic]) {
        func check(_ dict: [String: Any]) {
            for (key, val) in dict {
                if !calendarKeys.contains(key) {
                    results.append(Diagnostic(
                        severity: .warning,
                        message: "Unknown StartCalendarInterval key: \(key)",
                        key: "StartCalendarInterval"))
                } else if !(val is NSNumber) {
                    results.append(Diagnostic(
                        severity: .error,
                        message: "StartCalendarInterval.\(key) is not an integer",
                        key: "StartCalendarInterval"))
                }
            }
        }

        if let dict = value as? [String: Any] {
            check(dict)
        } else if let array = value as? [Any] {
            for element in array {
                if let dict = element as? [String: Any] {
                    check(dict)
                } else {
                    results.append(Diagnostic(
                        severity: .error,
                        message: "StartCalendarInterval array contains a non-dictionary entry",
                        key: "StartCalendarInterval"))
                }
            }
        } else {
            results.append(Diagnostic(
                severity: .error,
                message: "StartCalendarInterval must be a dictionary or array of dictionaries",
                key: "StartCalendarInterval"))
        }
    }
}
