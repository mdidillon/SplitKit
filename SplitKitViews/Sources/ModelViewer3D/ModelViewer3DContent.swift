import Observation
import RealityKit
import SwiftUI
import UniformTypeIdentifiers
import SplitKitContent
import SplitKitModel

/// glTF and GLB viewer pane (spec §10): GLTFKit2 converts the file, RealityKit renders it in a `RealityView`, and a
/// custom camera controller meets the camera contract (drag orbit; ⇧-drag, middle-drag and trackpad scroll pan; wheel
/// and pinch dolly, clamped; Reset Camera and ⌘0).
///
/// Opens a file through `init(url:)` (picker file panel or a dropped file) and restores from its saved state, the
/// file's absolute path plus the camera pose as JSON (`stateVersion` 1). `init` refuses what can't be shown, with a
/// typed `ContentError`, before any object exists:
/// - an extension that is not `.gltf`/`.glb` (including `.fbx`), Draco, meshopt or `KHR_mesh_quantization` data, a
///   malformed JSON or GLB container, a broken accessor or node index, a missing external `.bin` → `.unsupportedFile`
/// - a missing file → `.unreadable` (on restore too, which makes SplitKit show its "couldn't be restored" placeholder)
/// - neither a url nor a saved state → `.other`: there is nothing to show.
///
/// The parse of the model runs off the main actor after `init`; a failure there (GLTFKit2 refusing the binary data)
/// shows in the pane. The conversion runs on the main actor.
@MainActor @Observable
public final class ModelViewer3DContent: PaneContent {
    public static let type = ContentType(raw: "com.mdidillon.splitkit.model3d")
    public static let displayName = "3D Model"
    public static let systemImage = "cube"
    public static let minimumSize = CGSize.zero             // SplitKitConfiguration.minimumPaneSize applies
    public static let stateVersion = 1

    /// The file types the viewer opens; what `register(in:)` passes as `accepts`. glTF has no system constant, so
    /// both are declared from their extensions.
    public static let acceptedTypes: [UTType] = ["gltf", "glb"].compactMap { UTType(filenameExtension: $0) }

    /// Registers the viewer with the file types it opens (picker file panel, Finder drops).
    public static func register(in registry: ContentRegistry) throws(RegistryError) {
        try registry.register(self, accepts: acceptedTypes)
    }

    private struct State: Codable {
        var path: String
        var camera: OrbitCameraController.State?
    }

    public let fileURL: URL
    let stage: ModelStage
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    public init(id: ContentID, url: URL?, restoring state: Data?, stateVersion: Int?) throws(ContentError) {
        let file: URL
        var pose: OrbitCameraController.State?
        if let url {
            file = url
        } else if let state {
            guard stateVersion == Self.stateVersion, let decoded = try? JSONDecoder().decode(State.self, from: state) else {
                throw .stateIncompatible(version: stateVersion ?? 0)
            }
            file = URL(fileURLWithPath: decoded.path)
            pose = decoded.camera
        } else {
            throw .other("ModelViewer3D needs a glTF or GLB file")
        }
        let summary: GLTFPreflight.Summary
        do {
            summary = try GLTFPreflight.check(url: file)
        } catch {
            throw error.contentError(for: file)
        }
        fileURL = file
        stage = ModelStage(savedPose: pose)
        let stage = stage
        loadTask = Task { await stage.load(url: file, summary: summary) }
    }

    public var title: String { fileURL.lastPathComponent }

    public var toolbarItems: [PaneToolbarItem] {
        [PaneToolbarItem(
            id: "resetCamera",
            title: "Reset Camera",
            systemImage: "camera.metering.center.weighted",
            kind: .button { [stage] in stage.resetCamera() },
            priority: .high,
            isEnabled: stage.isReady,
            keyboardShortcut: KeyboardShortcut("0", modifiers: .command)
        )]
    }

    public func makeView() -> AnyView { AnyView(ModelViewer3DView(stage: stage, label: title)) }

    public func encodeState() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys                // the same pane always saves the same bytes
        return try encoder.encode(State(path: fileURL.standardizedFileURL.path, camera: stage.cameraPose))
    }

    public func shouldClose() async -> Bool { true }

    public func willRelease() {
        loadTask?.cancel()
        stage.tearDown()
    }

    /// Completes when the model is shown or has failed to load (tests).
    func waitUntilLoaded() async { await loadTask?.value }
}

private struct ModelViewer3DView: View {
    let stage: ModelStage
    let label: String

    var body: some View {
        ZStack {
            RealityView { content in
                // A re-hosted pane shows the same scene: take it from the previous view's content first.
                stage.sceneRoot.removeFromParent()
                content.add(stage.sceneRoot)
            }
            .realityViewCameraControls(.none)
            CameraInputView(stage: stage)
            switch stage.phase {
            case .loading:
                ProgressView()
            case .ready:
                EmptyView()
            case .failed(let error):
                ContentUnavailableView("Can't display model", systemImage: "exclamationmark.triangle",
                                       description: Text(error.description))
                    .background(.regularMaterial)
            }
        }
        .accessibilityLabel(label)
    }
}
