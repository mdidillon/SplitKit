import Observation
import RealityKit
import SpikeBCore
import SwiftUI

/// Camera implementations compared by the spike: the custom controller, or one native
/// `realityViewCameraControls` mode (RealityKit applies exactly one `CameraControls` value at a time).
enum CameraMode: String, CaseIterable, Identifiable {
    case custom = "Custom"
    case nativeOrbit = "Native .orbit"
    case nativePan = "Native .pan"
    case nativeTilt = "Native .tilt"
    case nativeDolly = "Native .dolly"

    var id: String { rawValue }

    var nativeControls: CameraControls {
        switch self {
        case .custom: .none
        case .nativeOrbit: .orbit
        case .nativePan: .pan
        case .nativeTilt: .tilt
        case .nativeDolly: .dolly
        }
    }
}

@MainActor
@Observable
final class ViewerModel {
    /// Everything RealityView displays hangs off this root; it never changes identity.
    let sceneRoot = Entity()
    /// Holds the loaded model; also the `cameraTarget` for native modes.
    let modelContainer = Entity()
    let cameraEntity = Entity()

    private(set) var controller = OrbitCameraController(bounds: .empty)
    private(set) var fileName: String?
    private(set) var errorMessage: String?
    private(set) var status: String = "Open a .gltf or .glb file (⌘O)."
    private(set) var animationCount = 0
    /// Bumped to rebuild RealityView, the only way to reset a native camera mode.
    private(set) var nativeResetToken = 0
    var viewportSize = CGSize(width: 800, height: 600)

    var mode: CameraMode = .custom {
        didSet { applyMode() }
    }

    init() {
        modelContainer.name = "ModelContainer"
        sceneRoot.addChild(modelContainer)
        let light = Entity()
        light.components.set(DirectionalLightComponent(color: .white, intensity: 2000))
        light.look(at: .zero, from: SIMD3(1, 2, 2), relativeTo: nil)
        sceneRoot.addChild(light)
        applyMode()
    }

    func open(url: URL) {
        modelContainer.children.removeAll()
        fileName = url.lastPathComponent
        do {
            let loaded = try ModelLoader.load(url: url)
            modelContainer.addChild(loaded.entity)
            animationCount = loaded.entity.availableAnimations.count
            errorMessage = nil
            let r = loaded.report
            status = String(format: "%@ — %.0f ms, %d/%d texture slots, %d warnings, %d animations, bounds %@",
                            url.lastPathComponent, r.totalDuration.milliseconds, r.convertedTextureSlots, r.expectedTextureSlots,
                            r.textureWarnings.count, r.availableAnimationCount, loaded.bounds.description)
            for warning in r.textureWarnings { print("[SpikeB] texture warning: \(warning)") }
        } catch {
            animationCount = 0
            errorMessage = error.description
            status = "Failed to open \(url.lastPathComponent)"
        }
        resetCamera()
    }

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        // Deliberately unfiltered so .fbx and malformed files can be picked to check the error path.
        if panel.runModal() == .OK, let url = panel.url { open(url: url) }
    }

    func playAnimations() {
        for animation in modelContainer.children.first?.availableAnimations ?? [] {
            modelContainer.children.first?.playAnimation(animation.repeat())
        }
    }

    // MARK: Camera

    var aspectRatio: Float {
        viewportSize.height > 0 ? Float(viewportSize.width / viewportSize.height) : 1
    }

    /// Reset Camera / ⌘0: framed default (bounding-sphere fit), pose and target.
    func resetCamera() {
        controller = OrbitCameraController(bounds: ModelLoader.measuredBounds(of: modelContainer),
                                           aspectRatio: aspectRatio)
        if mode != .custom { nativeResetToken += 1 }
        applyCamera()
    }

    func orbit(dx: CGFloat, dy: CGFloat) { controller.orbit(deltaX: Float(dx), deltaY: Float(dy)); applyCamera() }
    func pan(dx: CGFloat, dy: CGFloat) {
        controller.pan(deltaX: Float(dx), deltaY: Float(dy), viewportHeight: Float(viewportSize.height))
        applyCamera()
    }
    func scrollZoom(dy: CGFloat) { controller.scrollZoom(deltaY: Float(dy)); applyCamera() }
    func pinch(_ magnification: CGFloat) { controller.pinch(magnification: Float(magnification)); applyCamera() }

    private func applyCamera() {
        cameraEntity.components.set(PerspectiveCameraComponent(
            near: max(controller.minDistance * 0.1, 0.0001),
            far: controller.maxDistance * 2,
            fieldOfViewInDegrees: controller.configuration.verticalFieldOfView * 180 / .pi))
        cameraEntity.transform = Transform(matrix: controller.transform)
    }

    private func applyMode() {
        // The custom camera entity is only in the scene in custom mode, so native modes drive
        // RealityView's own virtual camera without competition.
        if mode == .custom {
            if cameraEntity.parent == nil { sceneRoot.addChild(cameraEntity) }
        } else {
            cameraEntity.removeFromParent()
        }
        nativeResetToken += 1
        applyCamera()
    }
}
