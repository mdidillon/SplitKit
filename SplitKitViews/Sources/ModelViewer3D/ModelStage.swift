import Observation
import RealityKit
import SwiftUI

/// The RealityKit scene of one pane and the camera that looks at it. It outlives the SwiftUI view, so re-hosting the
/// pane (`makeView()` again) shows the same model from the same pose.
///
/// **Camera (resolves Spike B's open question, spec §11.1):** the camera is an entity with a
/// `PerspectiveCameraComponent` whose transform comes from `OrbitCameraController`; the scene root is never
/// transformed. The alternative, the inverse camera transform applied to the scene root, depends on the pose, field
/// of view and clipping planes of RealityView's built-in camera, none of which can be set, and it would move the
/// light and the model's physical size with the camera. The entity gives the framed distance, the dolly clamp and
/// the near/far planes exactly. Rendering through that entity in a macOS `RealityView` is a manual check
/// (`Docs/SplitUI-checklist.md`, ModelViewer3D); `RealityRenderer` renders through it in the automated tests.
@MainActor @Observable
final class ModelStage {
    enum Phase: Equatable {
        case loading, ready
        case failed(ModelLoadError)
    }

    private(set) var phase = Phase.loading

    @ObservationIgnored let sceneRoot = Entity()
    @ObservationIgnored let modelContainer = Entity()
    @ObservationIgnored let cameraEntity = Entity()
    @ObservationIgnored private(set) var controller: OrbitCameraController?
    @ObservationIgnored private(set) var report: LoadReport?

    /// Set by the input view when it lays out; a model that hasn't been touched is re-framed to the new shape.
    @ObservationIgnored var viewportSize = CGSize.zero {
        didSet {
            guard viewportSize != oldValue, !cameraMoved, controller != nil else { return }
            resetCamera()
        }
    }

    @ObservationIgnored private var savedPose: OrbitCameraController.State?
    @ObservationIgnored private var cameraMoved: Bool
    @ObservationIgnored private var tornDown = false

    init(savedPose: OrbitCameraController.State?) {
        self.savedPose = savedPose
        cameraMoved = savedPose != nil
        modelContainer.name = "ModelContainer"
        sceneRoot.addChild(modelContainer)
        sceneRoot.addChild(cameraEntity)
        let light = Entity()
        light.components.set(DirectionalLightComponent(color: .white, intensity: 2000))
        light.look(at: .zero, from: SIMD3(1, 2, 2), relativeTo: nil)
        sceneRoot.addChild(light)
    }

    var isReady: Bool { phase == .ready }

    /// The pose to save: the live one, or the restored one while the model is still loading.
    var cameraPose: OrbitCameraController.State? { controller?.state ?? savedPose }

    /// Parses off the main actor, converts here. A failure becomes the pane's `phase`.
    func load(url: URL, summary: GLTFPreflight.Summary) async {
        do {
            let loaded = try await ModelLoader.load(url: url, summary: summary)
            guard !tornDown else { return }
            show(loaded)
        } catch {
            guard !tornDown else { return }
            phase = .failed(error)
        }
    }

    private func show(_ loaded: LoadedModel) {
        modelContainer.children.removeAll()
        modelContainer.addChild(loaded.entity)
        report = loaded.report
        var controller = OrbitCameraController(bounds: loaded.bounds, aspectRatio: aspectRatio)
        if let savedPose { controller.restore(savedPose) }
        self.controller = controller
        savedPose = nil
        applyCamera()
        // Skeletal animation loops; morph targets are reported as unsupported (spec §10 optional row).
        if let animation = loaded.entity.availableAnimations.first {
            loaded.entity.playAnimation(animation.repeat())
        }
        phase = .ready
    }

    func tearDown() {
        tornDown = true
        modelContainer.children.removeAll()
        controller = nil
    }

    // MARK: Camera

    private var aspectRatio: Float {
        viewportSize.height > 0 ? Float(viewportSize.width / viewportSize.height) : 1
    }

    /// Reset Camera / ⌘0: the framed default (bounding-sphere fit for the current viewport), pose and target.
    func resetCamera() {
        guard var controller else { return }
        controller.reset(aspectRatio: aspectRatio)
        self.controller = controller
        cameraMoved = false
        applyCamera()
    }

    func orbit(dx: CGFloat, dy: CGFloat) { adjust { $0.orbit(deltaX: Float(dx), deltaY: Float(dy)) } }
    func pan(dx: CGFloat, dy: CGFloat) {
        let height = Float(viewportSize.height)
        adjust { $0.pan(deltaX: Float(dx), deltaY: Float(dy), viewportHeight: height) }
    }
    func scrollZoom(dy: CGFloat) { adjust { $0.scrollZoom(deltaY: Float(dy)) } }
    func pinch(_ magnification: CGFloat) { adjust { $0.pinch(magnification: Float(magnification)) } }

    private func adjust(_ change: (inout OrbitCameraController) -> Void) {
        guard var controller else { return }
        change(&controller)
        self.controller = controller
        cameraMoved = true
        applyCamera()
    }

    private func applyCamera() {
        guard let controller else { return }
        cameraEntity.components.set(PerspectiveCameraComponent(
            near: max(controller.minDistance * 0.1, 0.0001),
            far: controller.maxDistance * 2,
            fieldOfViewInDegrees: controller.configuration.verticalFieldOfView * 180 / .pi))
        cameraEntity.transform = Transform(matrix: controller.transform)
    }
}
