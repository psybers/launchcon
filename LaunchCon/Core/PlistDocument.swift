import Foundation

/// An editable launchd plist file.
final class PlistDocument {
    let url: URL
    private(set) var contents: [String: Any]
    private(set) var isDirty = false

    init(url: URL, contents: [String: Any]) {
        self.url = url
        self.contents = contents
    }

    func value(forKey key: String) -> Any? {
        contents[key]
    }

    /// Replaces the entire contents and writes atomically to disk.
    func save(_ newContents: [String: Any]) throws {
        try Plist.save(newContents, to: url)
        contents = newContents
        isDirty = false
    }

    func markDirty() {
        isDirty = true
    }
}
