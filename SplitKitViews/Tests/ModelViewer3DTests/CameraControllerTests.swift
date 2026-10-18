import simd
import Testing
@testable import ModelViewer3D

/// Camera contract maths (spec §10): orbit, pan, dolly clamp, reset, framing, restore.
@Suite struct CameraControllerTests {
    let bounds = AxisAlignedBox(min: SIMD3(-1, 0, -0.5), max: SIMD3(3, 2, 0.5))

    func near(_ a: Float, _ b: Float, _ tolerance: Float = 1e-4) -> Bool { abs(a - b) <= tolerance * max(1, abs(b)) }
    func near(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ tolerance: Float = 1e-4) -> Bool {
        simd_length(a - b) <= tolerance * max(1, simd_length(b))
    }

    @Test func framingFitsBoundingSphere() {
        let config = OrbitCameraController.Configuration()
        for aspect: Float in [0.5, 1, 16.0 / 9] {
            let c = OrbitCameraController(bounds: bounds, aspectRatio: aspect)
            let sphere = bounds.boundingSphere
            #expect(c.target == sphere.center)
            #expect(near(simd_length(c.position - c.target), c.distance))
            // The sphere's angular radius equals the narrower half-FOV (divided by the margin).
            let halfV = config.verticalFieldOfView / 2
            let halfH = atan(tan(halfV) * aspect)
            let angularRadius = asin(sphere.radius * config.framingMargin / c.distance)
            #expect(near(angularRadius, min(halfV, halfH)))
        }
    }

    @Test func framedCameraLooksAtTarget() {
        let c = OrbitCameraController(bounds: bounds)
        let forward = -SIMD3(c.transform.columns.2.x, c.transform.columns.2.y, c.transform.columns.2.z)
        #expect(near(forward, simd_normalize(c.target - c.position)))
        #expect(c.basis.up.y > 0)
    }

    @Test func orbitKeepsDistanceAndTarget() {
        var c = OrbitCameraController(bounds: bounds)
        let target = c.target, distance = c.distance
        for (dx, dy) in [(10, 0), (0, 25), (-300, 140), (5000, -5000), (0.5, 0.25)] as [(Float, Float)] {
            c.orbit(deltaX: dx, deltaY: dy)
            #expect(c.target == target)
            #expect(c.distance == distance)
            #expect(near(simd_length(c.position - c.target), distance))
            #expect(near(-SIMD3(c.transform.columns.2.x, c.transform.columns.2.y, c.transform.columns.2.z),
                         simd_normalize(c.target - c.position)))
        }
    }

    @Test func orbitDirections() {
        // Grab the model: dragging right moves the camera left around it (yaw decreases), dragging down raises the camera.
        var c = OrbitCameraController(bounds: bounds)
        c.orbit(deltaX: 50, deltaY: 0)
        #expect(c.state.yaw < c.framed.yaw)
        var d = OrbitCameraController(bounds: bounds)
        d.orbit(deltaX: 0, deltaY: 20)
        #expect(d.state.pitch > d.framed.pitch)
    }

    @Test func orbitPitchIsClampedAndBasisStaysFinite() {
        var c = OrbitCameraController(bounds: bounds)
        c.orbit(deltaX: 0, deltaY: 1e6)
        #expect(c.state.pitch <= c.configuration.pitchLimit)
        c.orbit(deltaX: 0, deltaY: -1e7)
        #expect(c.state.pitch >= -c.configuration.pitchLimit)
        #expect(isFinite(c.transform))
    }

    @Test func panMovesTargetAndCameraEqually() {
        var c = OrbitCameraController(bounds: bounds)
        c.orbit(deltaX: 40, deltaY: 30)
        let before = (target: c.target, position: c.position, direction: c.viewDirection, distance: c.distance)
        c.pan(deltaX: 120, deltaY: -45, viewportHeight: 600)
        let dTarget = c.target - before.target
        let dPosition = c.position - before.position
        #expect(simd_length(dTarget) > 0)
        #expect(near(dTarget, dPosition))
        #expect(c.distance == before.distance)
        #expect(c.viewDirection == before.direction)
    }

    @Test func panIsInViewPlaneAndScaledToTargetDepth() {
        var c = OrbitCameraController(bounds: bounds)
        let start = c.target
        // Dragging one full viewport height moves the target by the visible height at target depth.
        c.pan(deltaX: 0, deltaY: 600, viewportHeight: 600)
        let expected = 2 * c.distance * tan(c.configuration.verticalFieldOfView / 2)
        #expect(near(simd_length(c.target - start), expected))
        #expect(near(simd_dot(c.target - start, c.viewDirection), 0, 1e-3))
        // Drag right: model follows the pointer, so the camera moves left.
        var d = OrbitCameraController(bounds: bounds)
        d.pan(deltaX: 10, deltaY: 0, viewportHeight: 600)
        #expect(simd_dot(d.target - start, d.basis.right) < 0)
    }

    @Test func panWithoutAViewportDoesNothing() {
        var c = OrbitCameraController(bounds: bounds)
        let before = c.state
        c.pan(deltaX: 10, deltaY: 10, viewportHeight: 0)
        c.pan(deltaX: .nan, deltaY: 10, viewportHeight: 600)
        #expect(c.state == before)
    }

    @Test func dollyClampsNearAndNeverCrossesTarget() {
        var c = OrbitCameraController(bounds: bounds)
        let direction = c.viewDirection
        for _ in 0..<1000 { c.dolly(factor: 0.5) }
        #expect(c.distance == c.minDistance)
        #expect(c.minDistance > 0)
        // Still on the same side of the target, never through it.
        #expect(simd_dot(c.position - c.target, direction) > 0)
        #expect(c.viewDirection == direction)
    }

    @Test func dollyClampsFar() {
        var c = OrbitCameraController(bounds: bounds)
        for _ in 0..<1000 { c.dolly(factor: 2) }
        #expect(c.distance == c.maxDistance)
    }

    @Test func dollyClampIsTenthOfRadiusAndTenTimesFramed() {
        let c = OrbitCameraController(bounds: bounds)
        #expect(near(c.minDistance, 0.1 * bounds.boundingSphere.radius))
        #expect(near(c.maxDistance, 10 * c.framed.distance))
    }

    @Test func dollyIgnoresInvalidFactors() {
        var c = OrbitCameraController(bounds: bounds)
        let before = c.state
        for factor: Float in [0, -1, .nan, .infinity, -.infinity] { c.dolly(factor: factor) }
        #expect(c.state == before)
    }

    @Test func scrollAndPinchDirections() {
        var c = OrbitCameraController(bounds: bounds)
        let d0 = c.distance
        c.scrollZoom(deltaY: 3)
        #expect(c.distance < d0)
        c.scrollZoom(deltaY: -6)
        #expect(c.distance > d0)
        c.reset()
        c.pinch(magnification: 0.2)
        #expect(c.distance < d0)
        c.pinch(magnification: -0.5)
        #expect(c.distance > d0)
    }

    @Test func resetRestoresExactFramedPoseAndTarget() {
        var c = OrbitCameraController(bounds: bounds, aspectRatio: 1.6)
        let framedTransform = c.transform
        let framedTarget = c.target
        c.orbit(deltaX: 333, deltaY: -77)
        c.pan(deltaX: -50, deltaY: 80, viewportHeight: 500)
        c.dolly(factor: 0.3)
        #expect(c.state != c.framed)
        c.reset()
        #expect(c.state == c.framed)
        #expect(c.target == framedTarget)
        #expect(c.transform == framedTransform)
    }

    @Test func resetWithANewAspectRatioReframesForTheNewViewport() {
        var c = OrbitCameraController(bounds: bounds, aspectRatio: 1)
        c.pan(deltaX: 30, deltaY: 30, viewportHeight: 500)
        c.reset(aspectRatio: 0.4)
        let narrow = OrbitCameraController(bounds: bounds, aspectRatio: 0.4)
        #expect(c.state == narrow.state)
        #expect(c.maxDistance == narrow.maxDistance)
        #expect(c.minDistance == narrow.minDistance)
    }

    @Test func restoreAdoptsASavedPoseAndClampsIt() {
        var c = OrbitCameraController(bounds: bounds)
        let saved = OrbitCameraController.State(target: SIMD3(1, 2, 3), distance: 4, yaw: 0.5, pitch: 0.25)
        c.restore(saved)
        #expect(c.state == saved)
        c.restore(.init(target: .zero, distance: 1e9, yaw: 0, pitch: 3))
        #expect(c.distance == c.maxDistance)
        #expect(c.state.pitch == c.configuration.pitchLimit)
        c.restore(.init(target: .zero, distance: 0, yaw: 0, pitch: 0))
        #expect(c.distance == c.minDistance)
    }

    @Test func restoreIgnoresNonFiniteValues() {
        var c = OrbitCameraController(bounds: bounds)
        let before = c.state
        c.restore(.init(target: SIMD3(.nan, 0, 0), distance: 1, yaw: 0, pitch: 0))
        c.restore(.init(target: .zero, distance: .infinity, yaw: 0, pitch: 0))
        #expect(c.state == before)
    }

    @Test func degenerateBoundsStillProduceAFiniteCamera() {
        for b in [AxisAlignedBox.empty, AxisAlignedBox(min: .zero, max: .zero)] {
            let c = OrbitCameraController(bounds: b)
            #expect(isFinite(c.transform))
            #expect(c.minDistance > 0 && c.minDistance < c.distance && c.distance < c.maxDistance)
        }
    }
}

func isFinite(_ m: simd_float4x4) -> Bool {
    [m.columns.0, m.columns.1, m.columns.2, m.columns.3].allSatisfy { c in
        c.x.isFinite && c.y.isFinite && c.z.isFinite && c.w.isFinite
    }
}
