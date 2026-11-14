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
    /// Value exists but has no simple editor (dicts, calendar intervals, etc.).
    case unsupported
}

struct JobKeySchema {
    let key: String
    let title: String
    let kind: PlistEditorKind
    /// Whether the string editor gets a "Choose…" file-picker button.
    let isPath: Bool

    static let all: [JobKeySchema] = [
        JobKeySchema(key: "Label", title: "Label", kind: .string, isPath: false),
        JobKeySchema(key: "ProgramArguments", title: "Program Arguments", kind: .stringList, isPath: false),
        JobKeySchema(key: "Program", title: "Program", kind: .string, isPath: true),
        JobKeySchema(key: "RunAtLoad", title: "Run at Load", kind: .bool, isPath: false),
        JobKeySchema(key: "KeepAlive", title: "Keep Alive", kind: .bool, isPath: false),
        JobKeySchema(key: "StartInterval", title: "Start Interval", kind: .integer, isPath: false),
        JobKeySchema(key: "StartCalendarInterval", title: "Start Calendar Interval", kind: .unsupported, isPath: false),
        JobKeySchema(key: "WorkingDirectory", title: "Working Directory", kind: .string, isPath: true),
        JobKeySchema(key: "StandardOutPath", title: "Standard Output", kind: .string, isPath: true),
        JobKeySchema(key: "StandardErrorPath", title: "Standard Error", kind: .string, isPath: true),
        JobKeySchema(key: "EnvironmentVariables", title: "Environment Variables", kind: .stringMap, isPath: false),
        JobKeySchema(key: "UserName", title: "User Name", kind: .string, isPath: false),
        JobKeySchema(key: "GroupName", title: "Group Name", kind: .string, isPath: false),
        JobKeySchema(key: "ProcessType", title: "Process Type",
                     kind: .popup(["Background", "Interactive", "Adaptive", "Standard"]), isPath: false),
        JobKeySchema(key: "LowPriorityIO", title: "Low Priority IO", kind: .bool, isPath: false),
        JobKeySchema(key: "Nice", title: "Nice", kind: .integer, isPath: false),
        JobKeySchema(key: "AbandonProcessGroup", title: "Abandon Process Group", kind: .bool, isPath: false),
    ]
}
