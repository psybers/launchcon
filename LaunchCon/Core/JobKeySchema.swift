import Foundation

/// How a plist key is edited in the property list editor.
enum PlistEditorKind {
    /// Single-line text.
    case string
    /// On/off checkbox.
    case bool
    /// Integer text field.
    case integer
    /// One string per line (for `ProgramArguments`).
    case stringList
    /// `KEY=VALUE` per line (for `EnvironmentVariables`).
    case stringMap
    /// Popup with fixed options.
    case popup([String])
    /// User account name — dropdown of local users.
    case userName
    /// Group account name — dropdown of local groups.
    case groupName
    /// `StartCalendarInterval`-style schedule (dict or array of dicts).
    case calendarInterval
    /// Value exists but has no simple editor (dicts, calendar intervals, etc.).
    case unsupported
}

struct JobKeySchema {
    let key: String
    let title: String
    let kind: PlistEditorKind
    /// Whether the string editor gets a "Choose…" file-picker button.
    let isPath: Bool
    /// Short description shown in the key palette.
    let summary: String
    /// Value inserted when the key is added from the palette. `nil` means the
    /// palette only focuses the key's row without inserting a value.
    let defaultValue: Any?

    static let all: [JobKeySchema] = [
        JobKeySchema(key: "Label", title: "Label",
                     kind: .string, isPath: false,
                     summary: "Unique name of the job; must match the plist filename",
                     defaultValue: nil),
        JobKeySchema(key: "ProgramArguments", title: "Program Arguments",
                     kind: .stringList, isPath: false,
                     summary: "Executable path followed by arguments, one per line",
                     defaultValue: nil),
        JobKeySchema(key: "Program", title: "Program",
                     kind: .string, isPath: true,
                     summary: "Executable to run (alternative to ProgramArguments)",
                     defaultValue: nil),
        JobKeySchema(key: "RunAtLoad", title: "Run at Load",
                     kind: .bool, isPath: false,
                     summary: "Start the job immediately when it is loaded",
                     defaultValue: true),
        JobKeySchema(key: "KeepAlive", title: "Keep Alive",
                     kind: .bool, isPath: false,
                     summary: "Keep the job running; may also be a dictionary of conditions",
                     defaultValue: true),
        JobKeySchema(key: "StartInterval", title: "Start Interval",
                     kind: .integer, isPath: false,
                     summary: "Seconds between scheduled launches",
                     defaultValue: nil),
        JobKeySchema(key: "StartCalendarInterval", title: "Start Calendar Interval",
                     kind: .calendarInterval, isPath: false,
                     summary: "Wall-clock schedule (e.g. every day at 9:00)",
                     defaultValue: nil),
        JobKeySchema(key: "WorkingDirectory", title: "Working Directory",
                     kind: .string, isPath: true,
                     summary: "Directory the job runs in",
                     defaultValue: nil),
        JobKeySchema(key: "StandardOutPath", title: "Standard Output",
                     kind: .string, isPath: true,
                     summary: "File receiving the job's stdout",
                     defaultValue: nil),
        JobKeySchema(key: "StandardErrorPath", title: "Standard Error",
                     kind: .string, isPath: true,
                     summary: "File receiving the job's stderr",
                     defaultValue: nil),
        JobKeySchema(key: "StandardInPath", title: "Standard Input",
                     kind: .string, isPath: true,
                     summary: "File the job reads stdin from",
                     defaultValue: nil),
        JobKeySchema(key: "EnvironmentVariables", title: "Environment Variables",
                     kind: .stringMap, isPath: false,
                     summary: "KEY=VALUE pairs added to the job's environment",
                     defaultValue: nil),
        JobKeySchema(key: "UserName", title: "User Name",
                     kind: .userName, isPath: false,
                     summary: "User the job runs as",
                     defaultValue: nil),
        JobKeySchema(key: "GroupName", title: "Group Name",
                     kind: .groupName, isPath: false,
                     summary: "Group the job runs as",
                     defaultValue: nil),
        JobKeySchema(key: "ProcessType", title: "Process Type",
                     kind: .popup(["Background", "Interactive", "Adaptive", "Standard"]),
                     isPath: false,
                     summary: "Scheduling priority class for the job",
                     defaultValue: nil),
        JobKeySchema(key: "LowPriorityIO", title: "Low Priority IO",
                     kind: .bool, isPath: false,
                     summary: "Throttle disk I/O to lowest priority",
                     defaultValue: true),
        JobKeySchema(key: "Nice", title: "Nice",
                     kind: .integer, isPath: false,
                     summary: "Nice value adjusting CPU scheduling priority",
                     defaultValue: nil),
        JobKeySchema(key: "AbandonProcessGroup", title: "Abandon Process Group",
                     kind: .bool, isPath: false,
                     summary: "Don't kill the process group when the job exits",
                     defaultValue: true),
        JobKeySchema(key: "ThrottleInterval", title: "Throttle Interval",
                     kind: .integer, isPath: false,
                     summary: "Minimum seconds between launch attempts (default 10)",
                     defaultValue: 10),
        JobKeySchema(key: "LaunchOnlyOnce", title: "Launch Only Once",
                     kind: .bool, isPath: false,
                     summary: "Run at most once per boot",
                     defaultValue: true),
        JobKeySchema(key: "EnableGlobbing", title: "Enable Globbing",
                     kind: .bool, isPath: false,
                     summary: "Expand shell-style wildcards in arguments",
                     defaultValue: true),
        JobKeySchema(key: "EnableTransactions", title: "Enable Transactions",
                     kind: .bool, isPath: false,
                     summary: "Run the job as a transaction",
                     defaultValue: true),
        JobKeySchema(key: "StartOnMount", title: "Start on Mount",
                     kind: .bool, isPath: false,
                     summary: "Start the job when a filesystem mounts",
                     defaultValue: true),
        JobKeySchema(key: "WatchPaths", title: "Watch Paths",
                     kind: .stringList, isPath: false,
                     summary: "Paths whose modification triggers a launch",
                     defaultValue: nil),
        JobKeySchema(key: "QueueDirectories", title: "Queue Directories",
                     kind: .stringList, isPath: false,
                     summary: "Directories scanned for files to process",
                     defaultValue: nil),
        JobKeySchema(key: "LimitLoadToHosts", title: "Limit Load To Hosts",
                     kind: .stringList, isPath: false,
                     summary: "Only load the job on these hosts",
                     defaultValue: nil),
        JobKeySchema(key: "LimitLoadFromHosts", title: "Limit Load From Hosts",
                     kind: .stringList, isPath: false,
                     summary: "Never load the job on these hosts",
                     defaultValue: nil),
        JobKeySchema(key: "LimitLoadToSessionType", title: "Limit Load To Session Type",
                     kind: .popup(["Aqua", "Background", "LoginWindow", "StandardIO", "System"]),
                     isPath: false,
                     summary: "Restrict loading to a session type",
                     defaultValue: nil),
    ]
}
