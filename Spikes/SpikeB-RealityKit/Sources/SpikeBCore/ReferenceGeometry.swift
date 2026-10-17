import Foundation
import simd

/// Reference geometry computed straight from the glTF JSON, independent of GLTFKit2 and RealityKit:
/// POSITION accessor `min`/`max` (mandatory in glTF 2.0) transformed by each node's world matrix.
/// Used as the ground truth for the §10 "bounding box within 1%" and "+Y up" criteria.
public struct ReferenceGeometry: Sendable {
    public struct Node: Sendable {
        public var name: String?
        public var worldMatrix: simd_float4x4
        public var hasMesh: Bool
        public var isSkinned: Bool
    }

    public var bounds: AxisAlignedBox
    public var nodes: [Node]
    public var extensionsUsed: [String]
    public var extensionsRequired: [String]
    public var hasSkins: Bool
    public var hasMorphTargets: Bool
    public var animationCount: Int

    public enum ParseError: Error, Equatable {
        case unreadable
        case notGLB
        case invalidJSON
        case missingField(String)
    }

    public init(url: URL) throws {
        let data: Data
        do { data = try Data(contentsOf: url) } catch { throw ParseError.unreadable }
        let jsonData = url.pathExtension.lowercased() == "glb" ? try Self.glbJSONChunk(data) : data
        guard let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw ParseError.invalidJSON
        }
        try self.init(json: json)
    }

    init(json: [String: Any]) throws {
        let nodes = json["nodes"] as? [[String: Any]] ?? []
        let meshes = json["meshes"] as? [[String: Any]] ?? []
        let accessors = json["accessors"] as? [[String: Any]] ?? []
        let scenes = json["scenes"] as? [[String: Any]] ?? []
        let sceneIndex = json["scene"] as? Int ?? 0
        guard scenes.indices.contains(sceneIndex) else { throw ParseError.missingField("scenes[\(sceneIndex)]") }
        let roots = scenes[sceneIndex]["nodes"] as? [Int] ?? []

        extensionsUsed = json["extensionsUsed"] as? [String] ?? []
        extensionsRequired = json["extensionsRequired"] as? [String] ?? []
        hasSkins = !(json["skins"] as? [Any] ?? []).isEmpty
        animationCount = (json["animations"] as? [Any] ?? []).count
        hasMorphTargets = meshes.contains { mesh in
            (mesh["primitives"] as? [[String: Any]] ?? []).contains { !($0["targets"] as? [Any] ?? []).isEmpty }
        }

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
            visited.append(Node(name: node["name"] as? String, worldMatrix: world,
                                hasMesh: node["mesh"] != nil, isSkinned: skinned))
            for child in node["children"] as? [Int] ?? [] {
                try visit(child, parent: world)
            }
        }
        for root in roots { try visit(root, parent: matrix_identity_float4x4) }

        bounds = box
        self.nodes = visited
    }

    /// `extensionsRequired` read from the JSON alone (works even when GLTFKit2 refuses the file).
    public static func requiredExtensions(url: URL) -> [String] {
        guard let data = try? Data(contentsOf: url),
              let jsonData = url.pathExtension.lowercased() == "glb" ? try? glbJSONChunk(data) : data,
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        else { return [] }
        return json["extensionsRequired"] as? [String] ?? []
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

    /// Extracts the JSON chunk of a GLB container (glTF 2.0 §4.4).
    static func glbJSONChunk(_ data: Data) throws -> Data {
        func u32(_ offset: Int) -> UInt32? {
            guard data.count >= offset + 4 else { return nil }
            return data.subdata(in: offset..<offset + 4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        }
        guard u32(0) == 0x4654_6C67, // "glTF"
              let chunkLength = u32(12), u32(16) == 0x4E4F_534A, // "JSON"
              data.count >= 20 + Int(chunkLength)
        else { throw ParseError.notGLB }
        return data.subdata(in: 20..<20 + Int(chunkLength))
    }
}
