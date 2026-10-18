import Foundation
import simd

/// The camera contract of spec §10: the camera orbits a `target` point at `distance`, described by `yaw`/`pitch`
/// (radians). Pan moves target and camera together; dolly changes only the distance and is clamped to
/// `[minDistance, maxDistance]`, so the camera never reaches or crosses the target. `reset` restores the framed
/// default (bounding-sphere fit), pose and target.
///
/// Input deltas are in view points with AppKit drag semantics: +x to the right, +y downwards
/// (`NSEvent.deltaX/deltaY`). Interaction is "grab the model": dragging right turns the model right.
struct OrbitCameraController: Equatable, Sendable {
    struct Configuration: Equatable, Sendable {
        /// Vertical field of view, radians.
        var verticalFieldOfView: Float = 45 * .pi / 180
        /// Default viewing direction for the framed pose.
        var defaultYaw: Float = 20 * .pi / 180
        var defaultPitch: Float = 15 * .pi / 180
        /// Orbit radians per point dragged.
        var orbitSensitivity: Float = 0.008
        /// Pitch stays inside ±limit so the up vector never degenerates.
        var pitchLimit: Float = 89 * .pi / 180
        /// Near clamp as a fraction of the bounding-sphere radius (> 0, so the target is never reached).
        var minDistanceFactor: Float = 0.1
        /// Far clamp as a multiple of the framed distance.
        var maxDistanceFactor: Float = 10
        /// Extra margin on the bounding-sphere fit (1 = sphere touches the narrowest view edge).
        var framingMargin: Float = 1.05
        /// Wheel zoom: `exp(-deltaY * wheelZoomSpeed)` per notch of `deltaY`.
        var wheelZoomSpeed: Float = 0.1
    }

    /// The pose that is saved with the pane (spec §8): where the camera looks at, from how far and from where.
    struct State: Equatable, Sendable, Codable {
        var target: SIMD3<Float>
        var distance: Float
        var yaw: Float
        var pitch: Float
    }

    let configuration: Configuration
    let bounds: AxisAlignedBox
    private(set) var aspectRatio: Float
    private(set) var framed: State
    private(set) var minDistance: Float
    private(set) var maxDistance: Float
    private(set) var state: State

    var target: SIMD3<Float> { state.target }
    var distance: Float { state.distance }

    /// - Parameters:
    ///   - bounds: model bounds in world space.
    ///   - aspectRatio: viewport width / height, used so the sphere fits the narrower field of view.
    init(bounds: AxisAlignedBox, aspectRatio: Float = 1, configuration: Configuration = .init()) {
        self.configuration = configuration
        let usable = !bounds.isEmpty && bounds.diagonal.isFinite && bounds.diagonal > 1e-6
        self.bounds = usable ? bounds : AxisAlignedBox(min: SIMD3(repeating: -0.5), max: SIMD3(repeating: 0.5))
        self.aspectRatio = 1
        let placeholder = State(target: .zero, distance: 1, yaw: 0, pitch: 0)
        framed = placeholder
        state = placeholder
        minDistance = 0
        maxDistance = 1
        frame(aspectRatio: aspectRatio)
        state = framed
    }

    /// Distance at which a sphere of `radius` fits inside the narrower of the vertical and horizontal FOV.
    static func framingDistance(radius: Float, aspectRatio: Float, configuration: Configuration) -> Float {
        let halfV = configuration.verticalFieldOfView / 2
        let aspect = aspectRatio.isFinite && aspectRatio > 0 ? aspectRatio : 1
        let halfH = atan(tan(halfV) * aspect)
        return radius * configuration.framingMargin / sin(min(halfV, halfH))
    }

    private mutating func frame(aspectRatio: Float) {
        self.aspectRatio = aspectRatio
        let sphere = bounds.boundingSphere
        let distance = Self.framingDistance(radius: sphere.radius, aspectRatio: aspectRatio, configuration: configuration)
        framed = State(target: sphere.center, distance: distance, yaw: configuration.defaultYaw, pitch: configuration.defaultPitch)
        minDistance = sphere.radius * configuration.minDistanceFactor
        maxDistance = distance * configuration.maxDistanceFactor
    }

    // MARK: Pose

    /// Unit vector from target to camera.
    var viewDirection: SIMD3<Float> {
        SIMD3(cos(state.pitch) * sin(state.yaw), sin(state.pitch), cos(state.pitch) * cos(state.yaw))
    }

    var position: SIMD3<Float> { state.target + state.distance * viewDirection }

    /// Camera basis (RealityKit cameras look down -Z): right, up, back.
    var basis: (right: SIMD3<Float>, up: SIMD3<Float>, back: SIMD3<Float>) {
        let back = viewDirection
        let right = simd_normalize(simd_cross(SIMD3<Float>(0, 1, 0), back))
        let up = simd_cross(back, right)
        return (right, up, back)
    }

    var orientation: simd_quatf {
        let b = basis
        return simd_quatf(simd_float3x3(b.right, b.up, b.back))
    }

    /// Camera-to-world transform for the camera entity.
    var transform: simd_float4x4 {
        var m = simd_float4x4(orientation)
        m.columns.3 = SIMD4(position, 1)
        return m
    }

    // MARK: Contract actions

    /// Orbit around the target. Distance and target are unchanged.
    mutating func orbit(deltaX: Float, deltaY: Float) {
        guard deltaX.isFinite, deltaY.isFinite else { return }
        state.yaw -= deltaX * configuration.orbitSensitivity
        state.pitch += deltaY * configuration.orbitSensitivity
        state.pitch = min(max(state.pitch, -configuration.pitchLimit), configuration.pitchLimit)
        state.yaw = remainder(state.yaw, 2 * .pi)
    }

    /// Pan in the view plane. Target and camera move by the same vector, so orbit direction and
    /// distance are unchanged. Scaled so the point at target depth follows the pointer.
    mutating func pan(deltaX: Float, deltaY: Float, viewportHeight: Float) {
        guard deltaX.isFinite, deltaY.isFinite, viewportHeight > 0 else { return }
        let worldPerPoint = 2 * state.distance * tan(configuration.verticalFieldOfView / 2) / viewportHeight
        let b = basis
        state.target += (-deltaX * b.right + deltaY * b.up) * worldPerPoint
    }

    /// Dolly toward (`factor` < 1) or away from (`factor` > 1) the target, clamped near/far.
    mutating func dolly(factor: Float) {
        guard factor.isFinite, factor > 0 else { return }
        state.distance = min(max(state.distance * factor, minDistance), maxDistance)
    }

    /// Mouse scroll wheel: positive `deltaY` (wheel away from the user) zooms in.
    mutating func scrollZoom(deltaY: Float) {
        dolly(factor: exp(-deltaY * configuration.wheelZoomSpeed))
    }

    /// Trackpad pinch: positive magnification (fingers apart) zooms in.
    mutating func pinch(magnification: Float) {
        dolly(factor: exp(-magnification))
    }

    /// Restore the framed default, pose and target. With `aspectRatio` the framing is recomputed for a viewport that
    /// has changed shape since the last reset.
    mutating func reset(aspectRatio: Float? = nil) {
        if let aspectRatio { frame(aspectRatio: aspectRatio) }
        state = framed
    }

    /// Adopt a saved pose (restore): every value must be finite, otherwise the framed default stays; the distance
    /// and pitch are clamped like live input.
    mutating func restore(_ saved: State) {
        let values = [saved.target.x, saved.target.y, saved.target.z, saved.distance, saved.yaw, saved.pitch]
        guard values.allSatisfy(\.isFinite) else { return }
        state = State(target: saved.target,
                      distance: min(max(saved.distance, minDistance), maxDistance),
                      yaw: remainder(saved.yaw, 2 * .pi),
                      pitch: min(max(saved.pitch, -configuration.pitchLimit), configuration.pitchLimit))
    }
}
