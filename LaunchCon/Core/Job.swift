import Foundation

/// A launchd job as reported by `launchctl list`, optionally enriched with
/// plist metadata discovered on disk.
struct Job: Identifiable, Hashable {
    /// The job's launchd label, e.g. `com.example.agent`.
    var label: String

    /// PID of the running process, if currently running.
    var pid: Int?

    /// Last exit status reported by launchd (`-` in list output becomes nil).
    var lastExitStatus: Int?

    /// The domain this job was listed from, e.g. `gui/501`.
    var domain: LaunchdDomain

    /// Path to the plist file on disk, if known.
    var plistPath: String?

    /// Whether the job is currently loaded in its domain.
    var isLoaded: Bool

    /// Whether the job is disabled (from `launchctl print-disabled`).
    var isDisabled: Bool

    /// Parsed plist contents, if the plist file was readable.
    var plist: [String: Any]?

    var id: String { "\(domain.rawValue)/\(label)" }

    var displayName: String { label }

    /// Human-readable status shown in the job list's Status column.
    var statusText: String {
        if pid != nil { return "Running" }
        if isDisabled { return "Disabled" }
        if isLoaded { return lastExitStatus.map { "Exit \($0)" } ?? "Loaded" }
        return "Not loaded"
    }

    static func == (lhs: Job, rhs: Job) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
