import Foundation

/// An editable launchd plist file.
final class PlistDocument {
    let url: URL
    private(set) var contents: [String: Any]
    /// Contents as last loaded from or saved to disk — the dirty baseline.
    private(set) var savedContents: [String: Any]

    init(url: URL, contents: [String: Any]) {
        self.url = url
        self.contents = contents
        self.savedContents = contents
    }

    func value(forKey key: String) -> Any? {
        contents[key]
    }

    /// Sets a value in the working contents without saving. Passing nil
    /// removes the key. The change is unsaved until `save` is called.
    func set(_ value: Any?, forKey key: String) {
        if let value {
            contents[key] = value
        } else {
            contents.removeValue(forKey: key)
        }
    }

    /// Replaces the entire contents and writes atomically to disk.
    func save(_ newContents: [String: Any]) throws {
        try Plist.save(newContents, to: url)
        contents = newContents
        savedContents = newContents
    }

    /// True if `candidate` differs from the last saved contents.
    func hasChanges(comparedTo candidate: [String: Any]) -> Bool {
        !Plist.valuesEqual(candidate, savedContents)
    }
}
