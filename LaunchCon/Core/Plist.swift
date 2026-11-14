import Foundation

/// Helpers for locating and reading launchd plist files.
enum Plist {

    /// Standard directories that contain launchd job plists, in display order.
    struct SearchLocation {
        let url: URL
        let domainHint: LaunchdDomain
        let isSystem: Bool
    }

    static let standardLocations: [SearchLocation] = [
        SearchLocation(
            url: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/LaunchAgents"),
            domainHint: .guiCurrentUser,
            isSystem: false
        ),
        SearchLocation(
            url: URL(fileURLWithPath: "/Library/LaunchAgents"),
            domainHint: .system,
            isSystem: true
        ),
        SearchLocation(
            url: URL(fileURLWithPath: "/Library/LaunchDaemons"),
            domainHint: .system,
            isSystem: true
        ),
        SearchLocation(
            url: URL(fileURLWithPath: "/System/Library/LaunchAgents"),
            domainHint: .system,
            isSystem: true
        ),
        SearchLocation(
            url: URL(fileURLWithPath: "/System/Library/LaunchDaemons"),
            domainHint: .system,
            isSystem: true
        ),
    ]

    /// Returns all `.plist` files in the standard locations that exist.
    static func findAllPlists() -> [(url: URL, location: SearchLocation)] {
        var results: [(URL, SearchLocation)] = []
        for location in standardLocations {
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: location.url,
                includingPropertiesForKeys: nil
            ) else { continue }
            for url in contents where url.pathExtension == "plist" {
                results.append((url, location))
            }
        }
        return results
    }

    /// Loads a plist file into a dictionary. Returns nil if unreadable/invalid.
    static func load(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    }

    /// Writes a plist dictionary atomically.
    static func save(_ dict: [String: Any], to url: URL) throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: dict,
            format: .xml,
            options: 0
        )
        try data.write(to: url, options: .atomic)
    }

    /// Extracts the `Label` key from a plist dictionary.
    static func label(in plist: [String: Any]) -> String? {
        plist["Label"] as? String
    }
}
