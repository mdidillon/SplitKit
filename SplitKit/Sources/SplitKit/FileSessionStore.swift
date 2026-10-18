import Foundation

/// The `SessionStore` behind `.file(URL)` (§8): atomic writes through a temp file in the same directory.
///
/// First save (no file yet): create the directory, write and fsync the temp file, `moveItem` it into place.
/// Later saves: `replaceItemAt(_:withItemAt:)`. Any failure leaves the previous file untouched and deletes
/// the temp file. The file system calls go through `Operations` so tests can fail each step.
struct FileSessionStore: SessionStore {
    /// The file system steps of a save. `live` is the real thing; tests replace single steps.
    struct Operations: Sendable {
        var createDirectory: @Sendable (URL) throws -> Void
        /// Creates `url` with `data` and fsyncs it.
        var write: @Sendable (Data, URL) throws -> Void
        /// Renames a temp file to a destination that doesn't exist yet.
        var move: @Sendable (_ temp: URL, _ destination: URL) throws -> Void
        /// Atomically replaces an existing destination with the temp file.
        var replace: @Sendable (_ destination: URL, _ temp: URL) throws -> Void
        var remove: @Sendable (URL) throws -> Void
        var exists: @Sendable (URL) -> Bool

        static let live = Operations(
            createDirectory: { try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true) },
            write: { data, url in
                try data.write(to: url)
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.synchronize()
            },
            move: { try FileManager.default.moveItem(at: $0, to: $1) },
            replace: { _ = try FileManager.default.replaceItemAt($0, withItemAt: $1) },
            remove: { try FileManager.default.removeItem(at: $0) },
            exists: { FileManager.default.fileExists(atPath: $0.path) })
    }

    let url: URL
    var operations: Operations = .live

    init(url: URL, operations: Operations = .live) {
        self.url = url
        self.operations = operations
    }

    /// The file's bytes, or nil when there is no file. Synchronous so `restoreOrOpenDefault()` can use it.
    func loadSynchronously() throws -> Data? {
        do {
            return try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return nil
        }
    }

    func load() async throws -> Data? {
        try loadSynchronously()
    }

    func save(_ data: Data) async throws {
        try write(data, to: url)
    }

    /// Keeps `data`, the unreadable original, as `session.invalid-<timestamp>.json` next to the session file
    /// (§8); a taken name gets a counter. Written atomically like a save.
    func keepInvalid(_ data: Data, at date: Date = Date()) throws -> URL {
        let folder = url.deletingLastPathComponent()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime, .withTimeZone]   // 20261018T123456Z
        let stamp = formatter.string(from: date)
        var target = folder.appending(path: "session.invalid-\(stamp).json", directoryHint: .notDirectory)
        var counter = 1
        while operations.exists(target) {
            target = folder.appending(path: "session.invalid-\(stamp)-\(counter).json", directoryHint: .notDirectory)
            counter += 1
        }
        try write(data, to: target)
        return target
    }

    private func write(_ data: Data, to destination: URL) throws {
        let folder = destination.deletingLastPathComponent()
        try operations.createDirectory(folder)
        let temp = folder.appending(path: ".\(destination.lastPathComponent).\(UUID().uuidString).tmp", directoryHint: .notDirectory)
        do {
            try operations.write(data, temp)
            if operations.exists(destination) {
                try operations.replace(destination, temp)
            } else {
                try operations.move(temp, destination)
            }
        } catch {
            try? operations.remove(temp)
            throw error
        }
    }
}
