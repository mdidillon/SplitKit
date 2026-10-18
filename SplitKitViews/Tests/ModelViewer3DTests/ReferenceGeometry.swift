import Foundation
import simd
@testable import ModelViewer3D

/// Reference geometry computed straight from the glTF JSON, independent of GLTFKit2 and RealityKit: POSITION accessor
/// `min`/`max` (mandatory in glTF 2.0) transformed by each node's world matrix. The ground truth for the spec §10
/// "bounding box within 1%" and "+Y up" criteria. The JSON comes from `GLTFPreflight.read`, the product's one reader.
struct ReferenceGeometry {
    struct Node {
        var name: String?
        var worldMatrix: simd_float4x4
    }

    enum ParseError: Error, Equatable {
        case missingField(String)
    }

    var bounds: AxisAlignedBox
    var nodes: [Node]

    init(url: URL) throws {
        let json = try GLTFPreflight.read(url: url).json
        let nodes = json["nodes"] as? [[String: Any]] ?? []
        let meshes = json["meshes"] as? [[String: Any]] ?? []
        let accessors = json["accessors"] as? [[String: Any]] ?? []
        let scenes = json["scenes"] as? [[String: Any]] ?? []
        let sceneIndex = json["scene"] as? Int ?? 0
        guard scenes.indices.contains(sceneIndex) else { throw ParseError.missingField("scenes[\(sceneIndex)]") }
        let roots = scenes[sceneIndex]["nodes"] as? [Int] ?? []

        var box = AxisAlignedBox.empty
        var visited: [Node] = []

        func visit(_ index: Int, parent: simd_float4x4) throws {
            guard nodes.indices.contains(index) else { throw ParseError.missingField("nodes[\(index)]") }
            let node = nodes[index]
            let world = parent * Self.localMatrix(node)
            let skinned = node["skin"] != nil
            if let meshIndex = node["mesh"] as? Int, meshes.indices.contains(meshIndex) {
                for primitive in meshes[meshIndex]["primitives"] as? [[String: Any]] ?? [] {
                    let mode = primitive["mode"] as? Int ?? 4
                    guard mode == 4, // triangles; GLTFKit2's RealityKit path converts only triangles
                          let attributes = primitive["attributes"] as? [String: Any],
                          let position = attributes["POSITION"] as? Int,
                          accessors.indices.contains(position),
                          let lo = Self.vec3(accessors[position]["min"]),
                          let hi = Self.vec3(accessors[position]["max"])
                    else { continue }
                    // glTF: skinned mesh node transforms are ignored; joints drive the vertices.
                    let local = AxisAlignedBox(min: lo, max: hi)
                    box.formUnion(skinned ? local : local.transformed(by: world))
                }
            }
            visited.append(Node(name: node["name"] as? String, worldMatrix: world))
            for child in node["children"] as? [Int] ?? [] {
                try visit(child, parent: world)
            }
        }
        for root in roots { try visit(root, parent: matrix_identity_float4x4) }

        bounds = box
        self.nodes = visited
    }

    static func localMatrix(_ node: [String: Any]) -> simd_float4x4 {
        if let m = node["matrix"] as? [Double], m.count == 16 {
            let f = m.map(Float.init) // column-major
            return simd_float4x4(SIMD4(f[0], f[1], f[2], f[3]), SIMD4(f[4], f[5], f[6], f[7]),
                                 SIMD4(f[8], f[9], f[10], f[11]), SIMD4(f[12], f[13], f[14], f[15]))
        }
        let t = vec3(node["translation"]) ?? .zero
        let s = vec3(node["scale"]) ?? .one
        var r = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        if let q = node["rotation"] as? [Double], q.count == 4 {
            r = simd_quatf(ix: Float(q[0]), iy: Float(q[1]), iz: Float(q[2]), r: Float(q[3]))
        }
        var m = simd_float4x4(r) * simd_float4x4(diagonal: SIMD4(s, 1))
        m.columns.3 = SIMD4(t, 1)
        return m
    }

    static func vec3(_ value: Any?) -> SIMD3<Float>? {
        guard let a = value as? [Double], a.count >= 3 else { return nil }
        return SIMD3(Float(a[0]), Float(a[1]), Float(a[2]))
    }
}
