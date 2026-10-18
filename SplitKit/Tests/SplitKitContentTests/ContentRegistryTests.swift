import Foundation
import Observation
import SwiftUI
import Testing
import UniformTypeIdentifiers
import SplitKitModel
@testable import SplitKitContent

// Test doubles: shared by nothing else, so they live here (not in a TestSupport.swift).

@MainActor @Observable
class DoubleContent: PaneContent {
    class var type: ContentType { ContentType(raw: "test.base") }
    class var displayName: String { "Base" }
    class var systemImage: String { "square" }
    class var minimumSize: CGSize { CGSize(width: 100, height: 80) }
    class var stateVersion: Int { 1 }

    let id: ContentID
    let restoredState: Data?
    let restoredVersion: Int?
    /// What `init` was given as `url`.
    let receivedURL: URL?

    required init(id: ContentID, url: URL?, restoring state: Data?, stateVersion: Int?) throws(ContentError) {
        self.id = id
        receivedURL = url
        restoredState = state
        restoredVersion = stateVersion
    }

    var title: String { Self.displayName }
    var toolbarItems: [PaneToolbarItem] { [] }
    func makeView() -> AnyView { AnyView(EmptyView()) }
    func encodeState() throws -> Data { Data() }
    func shouldClose() async -> Bool { true }
    func willRelease() {}
}

@MainActor @Observable
final class ImageDouble: DoubleContent {
    override class var type: ContentType { ContentType(raw: "test.image") }
    override class var displayName: String { "Image" }
    override class var systemImage: String { "photo" }
    override class var minimumSize: CGSize { CGSize(width: 200, height: 150) }
    override class var stateVersion: Int { 3 }
}

@MainActor @Observable
final class ModelDouble: DoubleContent {
    override class var type: ContentType { ContentType(raw: "test.model") }
    override class var displayName: String { "Model" }
}

/// Same `type` as `ImageDouble`, different metadata: proves the first registration stays.
@MainActor @Observable
final class ImpostorDouble: DoubleContent {
    override class var type: ContentType { ImageDouble.type }
    override class var displayName: String { "Impostor" }
}

@MainActor @Observable
final class FailingDouble: DoubleContent {
    override class var type: ContentType { ContentType(raw: "test.failing") }

    required init(id: ContentID, url: URL?, restoring state: Data?, stateVersion: Int?) throws(ContentError) {
        throw .stateIncompatible(version: stateVersion ?? -1)
    }
}

/// Rejects every URL in `init`, like a content that validates the file up front.
@MainActor @Observable
final class URLRejectingDouble: DoubleContent {
    override class var type: ContentType { ContentType(raw: "test.rejecting") }

    required init(id: ContentID, url: URL?, restoring state: Data?, stateVersion: Int?) throws(ContentError) {
        if let url { throw .unsupportedFile(url, reason: "not a supported file") }
        try super.init(id: id, url: url, restoring: state, stateVersion: stateVersion)
    }
}

@MainActor
@Suite struct ContentRegistryTests {
    let registry = ContentRegistry()
    let id = ContentID(raw: UUID())

    @Test func registrationOrderIsPreserved() throws {
        try registry.register(ModelDouble.self)
        try registry.register(ImageDouble.self)
        try registry.register(FailingDouble.self)
        #expect(registry.registeredTypes == [ModelDouble.type, ImageDouble.type, FailingDouble.type])
    }

    @Test func emptyRegistryHasNoTypes() {
        #expect(registry.registeredTypes.isEmpty)
        #expect(registry.type(for: URL(fileURLWithPath: "/tmp/a.png")) == nil)
    }

    @Test func duplicateTypeThrowsAndFirstStays() throws {
        try registry.register(ImageDouble.self, accepts: [.png])
        do {
            try registry.register(ImpostorDouble.self, accepts: [.jpeg])
            Issue.record("expected duplicateType")
        } catch {
            guard case .duplicateType(let type) = error else { Issue.record("wrong error \(error)"); return }
            #expect(type == ImageDouble.type)
        }
        #expect(registry.registeredTypes == [ImageDouble.type])
        #expect(registry.metadata(for: ImageDouble.type)?.displayName == "Image")
        #expect(registry.type(for: URL(fileURLWithPath: "/tmp/a.png")) == ImageDouble.type)
        #expect(registry.type(for: URL(fileURLWithPath: "/tmp/a.jpg")) == nil)
    }

    @Test func urlMatchingUsesConformance() throws {
        try registry.register(ImageDouble.self, accepts: [.image])
        #expect(registry.type(for: URL(fileURLWithPath: "/tmp/a.png")) == ImageDouble.type)
        #expect(registry.type(for: URL(fileURLWithPath: "/tmp/A.JPG")) == ImageDouble.type)
        #expect(registry.type(for: URL(fileURLWithPath: "/tmp/a.txt")) == nil)
        #expect(registry.type(for: URL(fileURLWithPath: "/tmp/noextension")) == nil)
    }

    @Test func firstRegisteredMatchWinsEvenIfLessSpecific() throws {
        try registry.register(ModelDouble.self, accepts: [.image])   // broad, registered first
        try registry.register(ImageDouble.self, accepts: [.png])     // specific, registered second
        for _ in 0..<5 {
            #expect(registry.type(for: URL(fileURLWithPath: "/tmp/a.png")) == ModelDouble.type)
        }
    }

    @Test func registrationOrderDecidesNotSpecificity() throws {
        try registry.register(ImageDouble.self, accepts: [.png])
        try registry.register(ModelDouble.self, accepts: [.image])
        #expect(registry.type(for: URL(fileURLWithPath: "/tmp/a.png")) == ImageDouble.type)
        #expect(registry.type(for: URL(fileURLWithPath: "/tmp/a.jpeg")) == ModelDouble.type)
    }

    @Test func typeWithoutAcceptsNeverMatchesAURL() throws {
        try registry.register(ImageDouble.self)
        #expect(registry.type(for: URL(fileURLWithPath: "/tmp/a.png")) == nil)
    }

    @Test func metadataIsReadableByContentType() throws {
        try registry.register(ImageDouble.self)
        let metadata = try #require(registry.metadata(for: ImageDouble.type))
        #expect(metadata.type == ImageDouble.type)
        #expect(metadata.displayName == "Image")
        #expect(metadata.systemImage == "photo")
        #expect(metadata.minimumSize == CGSize(width: 200, height: 150))
        #expect(metadata.stateVersion == 3)
        #expect(registry.metadata(for: ModelDouble.type) == nil)
    }

    @Test func makeWithoutStatePassesNil() throws {
        try registry.register(ImageDouble.self)
        let content = try registry.make(ImageDouble.type, id: id, url: nil, state: nil, stateVersion: nil)
        let image = try #require(content as? ImageDouble)
        #expect(image.id == id)
        #expect(image.restoredState == nil)
        #expect(image.restoredVersion == nil)
    }

    @Test func makeWithStatePassesStateAndVersion() throws {
        try registry.register(ImageDouble.self)
        let state = Data([1, 2, 3])
        let content = try registry.make(ImageDouble.type, id: id, url: nil, state: state, stateVersion: 2)
        let image = try #require(content as? ImageDouble)
        #expect(image.restoredState == state)
        #expect(image.restoredVersion == 2)
    }

    @Test func makeForwardsTheURLToInit() throws {
        try registry.register(ImageDouble.self)
        let url = URL(fileURLWithPath: "/tmp/a.png")
        let image = try #require(try registry.make(ImageDouble.type, id: id, url: url, state: nil, stateVersion: nil) as? ImageDouble)
        #expect(image.receivedURL == url)
        let restored = try #require(try registry.make(ImageDouble.type, id: id, url: nil, state: Data([1]), stateVersion: 3) as? ImageDouble)
        #expect(restored.receivedURL == nil)
    }

    @Test func aURLRejectedByInitSurfacesAsCreationFailed() throws {
        try registry.register(URLRejectingDouble.self)
        let url = URL(fileURLWithPath: "/tmp/a.xyz")
        do {
            _ = try registry.make(URLRejectingDouble.type, id: id, url: url, state: nil, stateVersion: nil)
            Issue.record("expected creationFailed")
        } catch {
            guard case .creationFailed(let type, .unsupportedFile(let rejected, _)) = error else { Issue.record("wrong error \(error)"); return }
            #expect(type == URLRejectingDouble.type)
            #expect(rejected == url)
        }
        _ = try registry.make(URLRejectingDouble.type, id: id, url: nil, state: nil, stateVersion: nil)
    }

    @Test func makeCreatesTheRegisteredConcreteType() throws {
        try registry.register(ImageDouble.self)
        try registry.register(ModelDouble.self)
        let content = try registry.make(ModelDouble.type, id: id, url: nil, state: nil, stateVersion: nil)
        #expect(content is ModelDouble)
    }

    @Test func makeUnknownTypeThrows() throws {
        try registry.register(ImageDouble.self)
        do {
            _ = try registry.make(ModelDouble.type, id: id, url: nil, state: nil, stateVersion: nil)
            Issue.record("expected unknownType")
        } catch {
            guard case .unknownType(let type) = error else { Issue.record("wrong error \(error)"); return }
            #expect(type == ModelDouble.type)
        }
    }

    @Test func makeWrapsTheContentErrorFromInit() throws {
        try registry.register(FailingDouble.self)
        do {
            _ = try registry.make(FailingDouble.type, id: id, url: nil, state: Data(), stateVersion: 7)
            Issue.record("expected creationFailed")
        } catch {
            guard case .creationFailed(let type, let inner) = error else { Issue.record("wrong error \(error)"); return }
            #expect(type == FailingDouble.type)
            guard case .stateIncompatible(let version) = inner else { Issue.record("wrong inner error \(inner)"); return }
            #expect(version == 7)
        }
    }
}
