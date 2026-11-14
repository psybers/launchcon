import Foundation

/// Reads the tail of a (potentially huge) log file without loading it all.
enum LogTail {

    /// Returns the last `maxLines` lines of the file at `path`, reading at
    /// most `maxBytes` from the end. Returns nil if the file can't be read.
    static func tail(path: String, maxLines: Int = 500, maxBytes: Int = 256 * 1024) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }

        guard let size = try? handle.seekToEnd(), size > 0 else { return "" }
        let offset = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        try? handle.seek(toOffset: offset)

        guard var text = String(data: handle.readDataToEndOfFile(), encoding: .utf8) else {
            return nil
        }
        // If we started mid-file, drop the partial first line.
        if offset > 0, let newline = text.firstIndex(of: "\n") {
            text = String(text[text.index(after: newline)...])
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.suffix(maxLines).joined(separator: "\n")
    }
}
