import Foundation

/// Parses `launchctl print <domain>/<label>` output into top-level
/// `key = value` properties.
///
/// Output looks like:
///
///     gui/503/com.example.foo = {
///         active count = 0
///         path = /Users/x/Library/LaunchAgents/foo.plist
///         state = not running
///         program = /bin/echo
///         arguments = {
///             /bin/echo
///             hi
///         }
///         ...
///     }
///
/// Only properties at depth 1 (direct children of the outer braces) are
/// returned. Nested blocks (`arguments`, `environment`, `event triggers`, …)
/// are collapsed to the placeholder "(…)" so callers know the key exists.
enum ServicePrintParser {

    static func properties(_ output: String) -> [String: String] {
        var result: [String: String] = [:]
        var depth = 0

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            // A `key = value` line is top-level only inside the outer braces.
            if depth == 1, let eq = line.firstIndex(of: "=") {
                let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
                var value = String(line[line.index(after: eq)...])
                    .trimmingCharacters(in: .whitespaces)
                if value == "{" {
                    value = "(…)"
                }
                if !key.isEmpty, !value.isEmpty {
                    result[key] = value
                }
            }

            depth += line.filter { $0 == "{" }.count
            depth -= line.filter { $0 == "}" }.count
            if depth < 0 { depth = 0 }
        }
        return result
    }
}
