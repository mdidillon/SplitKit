import Foundation
import SplitKitContent
import SplitKitModel
@testable import ImageViewer

/// The shared fixtures of the ImageViewer tests (Tests/Fixtures/, licences in LICENSES.md).
enum Fixtures {
    static let images = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Fixtures/Images", directoryHint: .isDirectory)

    static var png: URL { images.appending(path: "pixel.png") }
    static var jpeg: URL { images.appending(path: "pixel.jpg") }
    static var corrupt: URL { images.appending(path: "corrupt.png") }
    static var text: URL { images.appending(path: "notes.txt") }
    static var missing: URL { images.appending(path: "does-not-exist.png") }
}

@MainActor func makeViewer(url: URL?, state: Data? = nil, stateVersion: Int? = nil) throws(ContentError) -> ImageViewerContent {
    try ImageViewerContent(id: ContentID(raw: UUID()), url: url, restoring: state, stateVersion: stateVersion)
}

/// The `ContentError` `body` throws, or nil when it doesn't throw.
@MainActor func contentError(_ body: () throws(ContentError) -> Void) -> ContentError? {
    do { try body() } catch { return error }
    return nil
}
