import Foundation
import simd

/// An axis-aligned bounding box in metres (glTF units). Pure value type, no RealityKit dependency,
/// so the camera math and the reference-bounds computation can be unit-tested in isolation.
public struct AxisAlignedBox: Equatable, Sendable, CustomStringConvertible {
    public var min: SIMD3<Float>
    public var max: SIMD3<Float>

    public init(min: SIMD3<Float>, max: SIMD3<Float>) {
        self.min = min
        self.max = max
    }

    /// An inverted box that any `formUnion` replaces.
    public static let empty = AxisAlignedBox(min: SIMD3(repeating: .infinity), max: SIMD3(repeating: -.infinity))

    public var isEmpty: Bool { any(min .> max) }
    public var center: SIMD3<Float> { (min + max) / 2 }
    public var extents: SIMD3<Float> { max - min }
    public var diagonal: Float { simd_length(extents) }

    /// Bounding sphere of the box: centre and half the diagonal.
    public var boundingSphere: (center: SIMD3<Float>, radius: Float) { (center, diagonal / 2) }

    public mutating func formUnion(_ point: SIMD3<Float>) {
        min = simd_min(min, point)
        max = simd_max(max, point)
    }

    public mutating func formUnion(_ other: AxisAlignedBox) {
        guard !other.isEmpty else { return }
        formUnion(other.min)
        formUnion(other.max)
    }

    public var corners: [SIMD3<Float>] {
        (0..<8).map { i in
            SIMD3(i & 1 == 0 ? min.x : max.x, i & 2 == 0 ? min.y : max.y, i & 4 == 0 ? min.z : max.z)
        }
    }

    /// Box enclosing this box's corners after `matrix` is applied.
    public func transformed(by matrix: simd_float4x4) -> AxisAlignedBox {
        guard !isEmpty else { return self }
        var result = AxisAlignedBox.empty
        for corner in corners {
            let p = matrix * SIMD4(corner, 1)
            result.formUnion(SIMD3(p.x, p.y, p.z) / p.w)
        }
        return result
    }

    /// Largest per-axis deviation of `min`/`max` from `reference`, relative to the reference diagonal.
    /// Sign-sensitive per axis, so a box that is rotated (e.g. Z-up instead of Y-up) or mirrored fails
    /// even when its extents happen to have the same lengths.
    public func relativeDeviation(from reference: AxisAlignedBox) -> Float {
        let scale = Swift.max(reference.diagonal, .leastNormalMagnitude)
        let d = simd_max(simd_abs(min - reference.min), simd_abs(max - reference.max))
        return d.max() / scale
    }

    public var description: String {
        func f(_ v: SIMD3<Float>) -> String {
            "(" + [v.x, v.y, v.z].map { String(format: "%.4f", $0) }.joined(separator: ", ") + ")"
        }
        return "min \(f(min)) max \(f(max))"
    }
}
