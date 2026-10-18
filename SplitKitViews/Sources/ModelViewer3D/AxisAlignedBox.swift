import Foundation
import simd

/// An axis-aligned bounding box in metres (glTF units). A pure value type with no RealityKit dependency, so the
/// camera maths and the bounds checks can be unit-tested in isolation.
struct AxisAlignedBox: Equatable, Sendable, CustomStringConvertible {
    var min: SIMD3<Float>
    var max: SIMD3<Float>

    /// An inverted box that any `formUnion` replaces.
    static let empty = AxisAlignedBox(min: SIMD3(repeating: .infinity), max: SIMD3(repeating: -.infinity))

    var isEmpty: Bool { any(min .> max) }
    var center: SIMD3<Float> { (min + max) / 2 }
    var extents: SIMD3<Float> { max - min }
    var diagonal: Float { simd_length(extents) }

    /// Bounding sphere of the box: centre and half the diagonal.
    var boundingSphere: (center: SIMD3<Float>, radius: Float) { (center, diagonal / 2) }

    mutating func formUnion(_ point: SIMD3<Float>) {
        min = simd_min(min, point)
        max = simd_max(max, point)
    }

    mutating func formUnion(_ other: AxisAlignedBox) {
        guard !other.isEmpty else { return }
        formUnion(other.min)
        formUnion(other.max)
    }

    var corners: [SIMD3<Float>] {
        (0..<8).map { i in
            SIMD3(i & 1 == 0 ? min.x : max.x, i & 2 == 0 ? min.y : max.y, i & 4 == 0 ? min.z : max.z)
        }
    }

    /// Box enclosing this box's corners after `matrix` is applied.
    func transformed(by matrix: simd_float4x4) -> AxisAlignedBox {
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
    func relativeDeviation(from reference: AxisAlignedBox) -> Float {
        let scale = Swift.max(reference.diagonal, .leastNormalMagnitude)
        let d = simd_max(simd_abs(min - reference.min), simd_abs(max - reference.max))
        return d.max() / scale
    }

    var description: String {
        func f(_ v: SIMD3<Float>) -> String {
            "(" + [v.x, v.y, v.z].map { String(format: "%.4f", $0) }.joined(separator: ", ") + ")"
        }
        return "min \(f(min)) max \(f(max))"
    }
}
