import Foundation

/// A launchd domain target, e.g. `gui/501`, `system`, `user/501`, `pid/123`.
struct LaunchdDomain: Hashable, CustomStringConvertible {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    var description: String { rawValue }

    /// A domain-qualified service reference, e.g. `gui/501/com.example.agent`.
    func service(_ label: String) -> String {
        "\(rawValue)/\(label)"
    }

    // MARK: - Common domains

    static let system = LaunchdDomain(rawValue: "system")

    static var guiCurrentUser: LaunchdDomain {
        .gui(uid: getuid())
    }

    static var userCurrentUser: LaunchdDomain {
        .user(uid: getuid())
    }

    static func gui(uid: uid_t, path: String? = nil) -> LaunchdDomain {
        if let path {
            return LaunchdDomain(rawValue: "gui/\(uid)/\(path)")
        }
        return LaunchdDomain(rawValue: "gui/\(uid)")
    }

    static func user(uid: uid_t, path: String? = nil) -> LaunchdDomain {
        if let path {
            return LaunchdDomain(rawValue: "user/\(uid)/\(path)")
        }
        return LaunchdDomain(rawValue: "user/\(uid)")
    }

    static func pid(_ pid: pid_t) -> LaunchdDomain {
        LaunchdDomain(rawValue: "pid/\(pid)")
    }

    static func login(asid: UInt32) -> LaunchdDomain {
        LaunchdDomain(rawValue: "login/\(asid)")
    }

    static func session(asid: UInt32) -> LaunchdDomain {
        LaunchdDomain(rawValue: "session/\(asid)")
    }
}
