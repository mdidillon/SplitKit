import Foundation
import Testing
import SplitKitContent
import SplitKitModel
@testable import ImageViewer

@Test func smoke() {
    #expect(ImageViewerInfo.version == "0.0.0")
}

@MainActor @Suite struct ImageViewerContentTests {
    @Test func loadsAPNGAndAJPEG() throws {
        for url in [Fixtures.png, Fixtures.jpeg] {
            let viewer = try makeViewer(url: url)
            #expect(viewer.title == url.lastPathComponent)
            #expect(viewer.toolbarItems.isEmpty)
            _ = viewer.makeView()
            _ = viewer.makeView()   // may be called again after re-hosting (§5)
        }
    }

    @Test func aCorruptImageIsUnreadable() {
        guard case let .unreadable(url) = contentError({ () throws(ContentError) in _ = try makeViewer(url: Fixtures.corrupt) }) else {
            Issue.record("expected .unreadable")
            return
        }
        #expect(url == Fixtures.corrupt)
    }

    @Test func aMissingFileIsUnreadable() {
        guard case .unreadable = contentError({ () throws(ContentError) in _ = try makeViewer(url: Fixtures.missing) }) else {
            Issue.record("expected .unreadable")
            return
        }
    }

    @Test func aNonImageFileIsUnsupported() {
        guard case let .unsupportedFile(url, _) = contentError({ () throws(ContentError) in _ = try makeViewer(url: Fixtures.text) }) else {
            Issue.record("expected .unsupportedFile")
            return
        }
        #expect(url == Fixtures.text)
    }

    @Test func noURLAndNoStateIsRejected() {
        guard case .other = contentError({ () throws(ContentError) in _ = try makeViewer(url: nil) }) else {
            Issue.record("expected .other")
            return
        }
    }

    @Test func stateRoundTripsThePath() throws {
        let viewer = try makeViewer(url: Fixtures.png)
        let state = try viewer.encodeState()
        let restored = try makeViewer(url: nil, state: state, stateVersion: ImageViewerContent.stateVersion)
        #expect(restored.fileURL.path == Fixtures.png.standardizedFileURL.path)
        #expect(restored.title == viewer.title)
        #expect(try restored.encodeState() == state)
    }

    @Test func restoringAMissingFileIsUnreadable() throws {
        let state = try JSONEncoder().encode(["path": Fixtures.missing.path])
        guard case .unreadable = contentError({ () throws(ContentError) in _ = try makeViewer(url: nil, state: state, stateVersion: 1) }) else {
            Issue.record("expected .unreadable")
            return
        }
    }

    @Test func aForeignStateVersionIsIncompatible() throws {
        let state = try makeViewer(url: Fixtures.png).encodeState()
        guard case .stateIncompatible(version: 2) = contentError({ () throws(ContentError) in _ = try makeViewer(url: nil, state: state, stateVersion: 2) }) else {
            Issue.record("expected .stateIncompatible(version: 2)")
            return
        }
    }

    @Test func registersWithImageTypesAndResolvesFiles() throws {
        let registry = ContentRegistry()
        try ImageViewerContent.register(in: registry)
        #expect(registry.type(for: Fixtures.png) == ImageViewerContent.type)
        #expect(registry.type(for: Fixtures.jpeg) == ImageViewerContent.type)
        #expect(registry.type(for: Fixtures.text) == nil)
        let made = try registry.make(ImageViewerContent.type, id: ContentID(raw: UUID()), url: Fixtures.png, state: nil, stateVersion: nil)
        #expect(made.title == "pixel.png")
    }
}
