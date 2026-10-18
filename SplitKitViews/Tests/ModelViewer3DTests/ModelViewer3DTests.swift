import Foundation
import simd
import SwiftUI
import Testing
import SplitKitContent
import SplitKitModel
@testable import ModelViewer3D

@Test func smoke() {
    #expect(ModelViewer3DInfo.version == "0.0.0")
}

/// The camera entity sits where the controller says (the transform is stored as scale/rotation/translation, so
/// the comparison has a tolerance).
@MainActor private func cameraEntityFollows(_ stage: ModelStage) throws -> Bool {
    let expected = try #require(stage.controller).transform
    let actual = stage.cameraEntity.transform.matrix
    return (0..<4).allSatisfy { simd_length(actual[$0] - expected[$0]) < 1e-4 }
}

@MainActor @Suite struct ModelViewer3DContentTests {
    // MARK: Opening

    @Test func opensAGLTFAndExposesTheResetCameraItem() async throws {
        let viewer = try makeViewer(url: Fixtures.url(Fixtures.box))
        #expect(viewer.title == "Box.gltf")
        let item = try #require(viewer.toolbarItems.first)
        #expect(viewer.toolbarItems.count == 1)
        #expect(item.title == "Reset Camera")
        #expect(item.priority == .high)
        #expect(item.keyboardShortcut == KeyboardShortcut("0", modifiers: .command))
        #expect(!item.isEnabled, "nothing to reset before the model is shown")

        await viewer.waitUntilLoaded()
        #expect(viewer.stage.phase == .ready)
        #expect(viewer.toolbarItems.first?.isEnabled == true)
        _ = viewer.makeView()
        _ = viewer.makeView()   // may be called again after re-hosting (§5)
        viewer.willRelease()
    }

    @Test func opensAGLB() async throws {
        let viewer = try makeViewer(url: Fixtures.url(Fixtures.helmet))
        await viewer.waitUntilLoaded()
        #expect(viewer.stage.phase == .ready)
        #expect(viewer.stage.report?.textureWarnings.isEmpty == true)
        viewer.willRelease()
    }

    @Test func registersWithItsFileTypes() throws {
        let registry = ContentRegistry()
        try ModelViewer3DContent.register(in: registry)
        #expect(registry.registeredTypes == [ModelViewer3DContent.type])
        #expect(ModelViewer3DContent.acceptedTypes.count == 2)
        #expect(registry.type(for: Fixtures.url(Fixtures.box)) == ModelViewer3DContent.type)
        #expect(registry.type(for: Fixtures.url(Fixtures.helmet)) == ModelViewer3DContent.type)
        #expect(registry.type(for: Fixtures.url(Fixtures.fbx)) == nil)
        #expect(registry.type(for: URL(fileURLWithPath: "/tmp/picture.png")) == nil)
    }

    // MARK: Refusals up front

    @Test func unsupportedAndBrokenFilesAreRefusedWithATypedError() {
        for path in [Fixtures.fbx, Fixtures.malformed, Fixtures.missingBuffer, Fixtures.dracoBox] {
            let url = Fixtures.url(path)
            guard case let .unsupportedFile(file, reason) = contentError({ () throws(ContentError) in _ = try makeViewer(url: url) }) else {
                Issue.record("\(path): expected .unsupportedFile")
                continue
            }
            #expect(file == url)
            #expect(!reason.isEmpty)
        }
    }

    @Test func aMissingFileIsUnreadable() {
        guard case .unreadable = contentError({ () throws(ContentError) in _ = try makeViewer(url: Fixtures.url("Errors/nope.glb")) }) else {
            Issue.record("expected .unreadable")
            return
        }
    }

    @Test func noURLAndNoStateIsRejected() {
        guard case .other = contentError({ () throws(ContentError) in _ = try makeViewer(url: nil) }) else {
            Issue.record("expected .other")
            return
        }
    }

    @Test func aForeignStateVersionAndGarbageStateAreIncompatible() {
        for (state, version) in [(Data("{}".utf8), 1), (Data("{\"path\":\"/x.glb\"}".utf8), 2), (Data("nonsense".utf8), 1)] as [(Data, Int)] {
            guard case let .stateIncompatible(reported) = contentError({ () throws(ContentError) in
                _ = try makeViewer(url: nil, state: state, stateVersion: version)
            }) else {
                Issue.record("expected .stateIncompatible for version \(version)")
                continue
            }
            #expect(reported == version)
        }
    }

    // MARK: State

    @Test func stateRoundTripsThePathAndTheCameraPose() async throws {
        let viewer = try makeViewer(url: Fixtures.url(Fixtures.box))
        await viewer.waitUntilLoaded()
        viewer.stage.viewportSize = CGSize(width: 800, height: 600)
        viewer.stage.orbit(dx: 120, dy: -40)
        viewer.stage.pan(dx: 30, dy: 15)
        viewer.stage.scrollZoom(dy: 4)
        let pose = try #require(viewer.stage.controller?.state)
        #expect(pose != viewer.stage.controller?.framed)

        let state = try viewer.encodeState()
        let restored = try makeViewer(url: nil, state: state, stateVersion: ModelViewer3DContent.stateVersion)
        #expect(restored.fileURL.path == viewer.fileURL.standardizedFileURL.path)
        #expect(restored.title == viewer.title)
        // Before the model is shown the saved pose is what a snapshot writes.
        #expect(restored.stage.cameraPose == pose)
        #expect(try restored.encodeState() == state)

        restored.stage.viewportSize = CGSize(width: 800, height: 600)
        await restored.waitUntilLoaded()
        #expect(restored.stage.controller?.state == pose)
        // Equal poses can differ in the sign of a zero, so the saved bytes of a restored pane are compared by pose.
        let again = try makeViewer(url: nil, state: try restored.encodeState(), stateVersion: 1)
        #expect(again.stage.cameraPose == pose)
        again.willRelease()
        viewer.willRelease()
        restored.willRelease()
    }

    @Test func aStateWithoutACameraFramesTheModel() async throws {
        let state = Data("{\"path\":\"\(Fixtures.url(Fixtures.box).path)\"}".utf8)
        let viewer = try makeViewer(url: nil, state: state, stateVersion: 1)
        await viewer.waitUntilLoaded()
        #expect(viewer.stage.controller?.state == viewer.stage.controller?.framed)
        viewer.willRelease()
    }

    @Test func restoringAMissingFileIsUnreadable() throws {
        let state = Data("{\"path\":\"/does/not/exist.glb\"}".utf8)
        guard case .unreadable = contentError({ () throws(ContentError) in
            _ = try makeViewer(url: nil, state: state, stateVersion: 1)
        }) else {
            Issue.record("expected .unreadable")
            return
        }
    }

    // MARK: Camera

    @Test func resetCameraReturnsToTheFramedPoseAndTarget() async throws {
        let viewer = try makeViewer(url: Fixtures.url(Fixtures.helmet))
        await viewer.waitUntilLoaded()
        viewer.stage.viewportSize = CGSize(width: 900, height: 600)
        let framed = try #require(viewer.stage.controller?.framed)
        viewer.stage.orbit(dx: 200, dy: 90)
        viewer.stage.pan(dx: -60, dy: 40)
        viewer.stage.pinch(0.5)
        #expect(viewer.stage.controller?.state != framed)

        let item = try #require(viewer.toolbarItems.first)
        guard case let .button(action) = item.kind else { Issue.record("Reset Camera must be a button"); return }
        action()
        #expect(viewer.stage.controller?.state == viewer.stage.controller?.framed)
        #expect(viewer.stage.controller?.target == framed.target)
        #expect(try cameraEntityFollows(viewer.stage))
        viewer.willRelease()
    }

    @Test func theCameraEntityFollowsTheController() async throws {
        let viewer = try makeViewer(url: Fixtures.url(Fixtures.box))
        await viewer.waitUntilLoaded()
        viewer.stage.orbit(dx: 50, dy: 10)
        #expect(try cameraEntityFollows(viewer.stage))
        #expect(viewer.stage.sceneRoot.transform.matrix == matrix_identity_float4x4, "the scene root is never moved")
        viewer.willRelease()
    }

    @Test func aModelThatHasNotBeenTouchedIsReframedWhenTheViewportChanges() async throws {
        let viewer = try makeViewer(url: Fixtures.url(Fixtures.box))
        await viewer.waitUntilLoaded()
        viewer.stage.viewportSize = CGSize(width: 400, height: 800)
        let tall = try #require(viewer.stage.controller?.state)
        viewer.stage.viewportSize = CGSize(width: 1200, height: 400)
        let wide = try #require(viewer.stage.controller?.state)
        #expect(tall.distance > wide.distance, "a tall viewport needs more distance to fit the model's sphere")
        viewer.stage.orbit(dx: 10, dy: 0)
        let touched = viewer.stage.controller?.state
        viewer.stage.viewportSize = CGSize(width: 400, height: 800)
        #expect(viewer.stage.controller?.state == touched, "a moved camera keeps its pose")
        viewer.willRelease()
    }

    @Test func releasingTheContentDropsTheModel() async throws {
        let viewer = try makeViewer(url: Fixtures.url(Fixtures.box))
        await viewer.waitUntilLoaded()
        #expect(!viewer.stage.modelContainer.children.isEmpty)
        viewer.willRelease()
        #expect(viewer.stage.modelContainer.children.isEmpty)
    }
}
