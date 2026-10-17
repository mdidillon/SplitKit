import Foundation
import simd

/// Custom camera for the §10 camera contract: the camera orbits a `target` point at `distance`,
/// described by `yaw`/`pitch` (radians). Pan moves target and camera together; dolly changes only
/// the distance and is clamped to `[minDistance, maxDistance]`, so the camera never reaches or
/// crosses the target. `reset()` restores the framed default (bounding-sphere fit), pose and target.
///
/// Input deltas are in view points with AppKit drag semantics: +x to the right, +y downwards
/// (`NSEvent.deltaX/deltaY`). Interaction is "grab the model": dragging right turns the model right.
public struct OrbitCameraController: Equatable, Sendable {
    public struct Configuration: Equatable, Sendable {
        /// Vertical field of view, radians.
        public var verticalFieldOfView: Float = 45 * .pi / 180
        /// Default viewing direction for the framed pose.
        public var defaultYaw: Float = 20 * .pi / 180
        public var defaultPitch: Float = 15 * .pi / 180
        /// Orbit radians per point dragged.
        public var orbitSensitivity: Float = 0.008
        /// Pitch stays inside ±limit so the up vector never degenerates.
        public var pitchLimit: Float = 89 * .pi / 180
        /// Near clamp as a fraction of the bounding-sphere radius (> 0, so the target is never reached).
        public var minDistanceFactor: Float = 0.1
        /// Far clamp as a multiple of the framed distance.
        public var maxDistanceFactor: Float = 10
        /// Extra margin on the bounding-sphere fit (1 = sphere touches the narrowest view edge).
        public var framingMargin: Float = 1.05

        public init() {}
    }

    public struct State: Equatable, Sendable {
        public var target: SIMD3<Float>
        public var distance: Float
        public var yaw: Float
        public var pitch: Float
    }

    public let configuration: Configuration
    public let bounds: AxisAlignedBox
    public let framed: State
    public let minDistance: Float
    public let maxDistance: Float
    public private(set) var state: State

    public var target: SIMD3<Float> { state.target }
    public var distance: Float { state.distance }

    /// - Parameters:
    ///   - bounds: model bounds in world space.
    ///   - aspectRatio: viewport width / height, used so the sphere fits the narrower field of view.
    public init(bounds: AxisAlignedBox, aspectRatio: Float = 1, configuration: Configuration = .init()) {
        self.configuration = configuration
        let usable = !bounds.isEmpty && bounds.diagonal.isFinite && bounds.diagonal > 1e-6
        self.bounds = usable ? bounds : AxisAlignedBox(min: SIMD3(repeating: -0.5), max: SIMD3(repeating: 0.5))
        let sphere = self.bounds.boundingSphere
        let distance = Self.framingDistance(radius: sphere.radius, aspectRatio: aspectRatio,
                                            configuration: configuration)
        let framed = State(target: sphere.center, distance: distance,
                           yaw: configuration.defaultYaw, pitch: configuration.defaultPitch)
        self.framed = framed
        self.state = framed
        self.minDistance = sphere.radius * configuration.minDistanceFactor
        self.maxDistance = distance * configuration.maxDistanceFactor
    }

    /// Distance at which a sphere of `radius` fits inside the narrower of the vertical and horizontal FOV.
    public static func framingDistance(radius: Float, aspectRatio: Float, configuration: Configuration) -> Float {
        let halfV = configuration.verticalFieldOfView / 2
        let aspect = aspectRatio.isFinite && aspectRatio > 0 ? aspectRatio : 1
        let halfH = atan(tan(halfV) * aspect)
        return radius * configuration.framingMargin / sin(min(halfV, halfH))
    }

    // MARK: Pose

    /// Unit vector from target to camera.
    public var viewDirection: SIMD3<Float> {
        SIMD3(cos(state.pitch) * sin(state.yaw), sin(state.pitch), cos(state.pitch) * cos(state.yaw))
    }

    public var position: SIMD3<Float> { state.target + state.distance * viewDirection }

    /// Camera basis (RealityKit cameras look down -Z): right, up, back.
    public var basis: (right: SIMD3<Float>, up: SIMD3<Float>, back: SIMD3<Float>) {
        let back = viewDirection
        let right = simd_normalize(simd_cross(SIMD3<Float>(0, 1, 0), back))
        let up = simd_cross(back, right)
        return (right, up, back)
    }

    public var orientation: simd_quatf {
        let b = basis
        return simd_quatf(simd_float3x3(b.right, b.up, b.back))
    }

    /// Camera-to-world transform for a camera entity.
    public var transform: simd_float4x4 {
        var m = simd_float4x4(orientation)
        m.columns.3 = SIMD4(position, 1)
        return m
    }

    // MARK: Contract actions

    /// Orbit around the target. Distance and target are unchanged.
    public mutating func orbit(deltaX: Float, deltaY: Float) {
        guard deltaX.isFinite, deltaY.isFinite else { return }
        state.yaw -= deltaX * configuration.orbitSensitivity
        state.pitch += deltaY * configuration.orbitSensitivity
        state.pitch = min(max(state.pitch, -configuration.pitchLimit), configuration.pitchLimit)
        state.yaw = remainder(state.yaw, 2 * .pi)
    }

    /// Pan in the view plane. Target and camera move by the same vector, so orbit direction and
    /// distance are unchanged. Scaled so the point at target depth follows the pointer.
    public mutating func pan(deltaX: Float, deltaY: Float, viewportHeight: Float) {
        guard deltaX.isFinite, deltaY.isFinite, viewportHeight > 0 else { return }
        let worldPerPoint = 2 * state.distance * tan(configuration.verticalFieldOfView / 2) / viewportHeight
        let b = basis
        state.target += (-deltaX * b.right + deltaY * b.up) * worldPerPoint
    }

    /// Dolly toward (`factor` < 1) or away from (`factor` > 1) the target, clamped near/far.
    public mutating func dolly(factor: Float) {
        guard factor.isFinite, factor > 0 else { return }
        state.distance = min(max(state.distance * factor, minDistance), maxDistance)
    }

    /// Mouse scroll wheel: positive `deltaY` (wheel away from the user) zooms in.
    public mutating func scrollZoom(deltaY: Float) {
        dolly(factor: exp(-deltaY * 0.1))
    }

    /// Trackpad pinch: positive magnification (fingers apart) zooms in.
    public mutating func pinch(magnification: Float) {
        dolly(factor: exp(-magnification))
    }

    /// Restore the framed default: pose and target.
    public mutating func reset() {
        state = framed
    }
}
