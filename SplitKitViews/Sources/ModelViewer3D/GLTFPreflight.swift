import Foundation
import SplitKitContent

/// Why a model file can't be shown. Typed so the content can map it to `ContentError` and tests can assert the case.
enum ModelLoadError: Error, Equatable, CustomStringConvertible {
    /// The extension is not glTF/GLB (e.g. `.fbx`, which spec §10 rules out). Checked before anything is read.
    case unsupportedFormat(fileExtension: String)
    case fileNotFound
    /// Not valid glTF 2.0: bad JSON or GLB container, a broken index or range, or a refusal from GLTFKit2.
    case malformed(reason: String)
    /// An external buffer (`.bin`) the file refers to is missing.
    case missingResource(String)
    /// The file lists an extension in `extensionsRequired` that can't be honoured (Draco, meshopt, quantization).
    case unsupportedRequiredExtensions([String])
    /// The data itself needs a feature the converter lacks (e.g. quantized positions without the extension header).
    case unsupportedFeature(String)
    case noDefaultScene

    /// A lower-case clause without a full stop: what `ContentError.unsupportedFile(_, reason:)` carries, and what the
    /// SplitKit banner puts after “can't be opened:”.
    var reason: String {
        switch self {
        case .unsupportedFormat(let ext): "only glTF (.gltf) and GLB (.glb) files can be opened, not .\(ext)"
        case .fileNotFound: "the file could not be found"
        case .malformed(let reason): "it is not a valid glTF asset (\(reason))"
        case .missingResource(let name): "it refers to “\(name)”, which is missing"
        case .unsupportedRequiredExtensions(let names): "it requires unsupported glTF extensions: \(names.joined(separator: ", "))"
        case .unsupportedFeature(let what): "it uses an unsupported feature: \(what)"
        case .noDefaultScene: "it contains no scene to display"
        }
    }

    /// The same as a sentence, for the pane.
    var description: String { reason.prefix(1).uppercased() + reason.dropFirst() + "." }

    /// The error `init` throws for a file that is refused up front.
    func contentError(for url: URL) -> ContentError {
        if case .fileNotFound = self { return .unreadable(url) }
        return .unsupportedFile(url, reason: reason)
    }
}

/// The checks that run before GLTFKit2 sees a file, on the JSON alone (and the GLB container): they make `init` of the
/// content refuse a file up front (spec §11.1 risks: GLTFKit2 can `fatalError` on unusual valid files, Draco and
/// `KHR_mesh_quantization` can't be decoded) and they are the one JSON reader of the product.
enum GLTFPreflight {
    struct Summary: Sendable {
        var fileSize: Int
        var extensionsUsed: [String]
        var extensionsRequired: [String]
    }

    static let supportedExtensions: Set<String> = ["gltf", "glb"]

    /// Required extensions GLTFKit2 0.5.15 can't honour: it ships no Draco or meshopt decoder and no dequantizing
    /// path for `KHR_mesh_quantization`.
    static let refusedRequiredExtensions: Set<String> = [
        "KHR_draco_mesh_compression", "KHR_mesh_quantization", "EXT_meshopt_compression",
    ]

    /// Throws `ModelLoadError` for anything that makes the file unshowable; otherwise the facts later steps need.
    static func check(url: URL) throws(ModelLoadError) -> Summary {
        let fileExtension = url.pathExtension.lowercased()
        guard supportedExtensions.contains(fileExtension) else { throw .unsupportedFormat(fileExtension: fileExtension) }
        let (json, binLength, fileSize) = try read(url: url)

        guard let asset = json["asset"] as? [String: Any], let version = asset["version"] as? String, version.hasPrefix("2") else {
            throw .malformed(reason: "no glTF 2.0 asset version")
        }
        let used = json["extensionsUsed"] as? [String] ?? []
        let required = json["extensionsRequired"] as? [String] ?? []
        let refused = required.filter(refusedRequiredExtensions.contains)
        guard refused.isEmpty else { throw .unsupportedRequiredExtensions(refused) }
        try validate(json, directory: url.deletingLastPathComponent(), binChunkLength: binLength)
        return Summary(fileSize: fileSize, extensionsUsed: used, extensionsRequired: required)
    }

    /// The parsed JSON of a `.gltf` or of the JSON chunk of a `.glb`, the BIN chunk length (GLB) and the file size.
    static func read(url: URL) throws(ModelLoadError) -> (json: [String: Any], binLength: Int?, fileSize: Int) {
        guard FileManager.default.fileExists(atPath: url.path) else { throw .fileNotFound }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { throw .malformed(reason: "the file can't be read") }
        var jsonData = data
        var binLength: Int?
        if url.pathExtension.lowercased() == "glb" {
            (jsonData, binLength) = try glbChunks(data)
        }
        guard let object = try? JSONSerialization.jsonObject(with: jsonData), let json = object as? [String: Any] else {
            throw .malformed(reason: "invalid JSON")
        }
        return (json, binLength, data.count)
    }

    /// JSON chunk and BIN chunk length of a GLB container (glTF 2.0 §4.4).
    static func glbChunks(_ data: Data) throws(ModelLoadError) -> (json: Data, binLength: Int?) {
        func u32(_ offset: Int) -> Int? {
            guard offset >= 0, data.count >= offset + 4 else { return nil }
            return Int(data.subdata(in: data.startIndex + offset..<data.startIndex + offset + 4)
                .withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
        }
        guard u32(0) == 0x4654_6C67, u32(4) == 2, let total = u32(8), total <= data.count else {
            throw .malformed(reason: "not a GLB 2 container")
        }
        guard let jsonLength = u32(12), u32(16) == 0x4E4F_534A, data.count >= 20 + jsonLength else {
            throw .malformed(reason: "the GLB has no JSON chunk")
        }
        let json = data.subdata(in: data.startIndex + 20..<data.startIndex + 20 + jsonLength)
        let next = 20 + jsonLength
        var binLength: Int?
        if let length = u32(next), u32(next + 4) == 0x004E_4942 {
            guard data.count >= next + 8 + length else { throw .malformed(reason: "the GLB BIN chunk is truncated") }
            binLength = length
        }
        return (json, binLength)
    }

    // MARK: Structure

    private static let componentSizes = [5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4]
    private static let componentCounts = ["SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT2": 4, "MAT3": 9, "MAT4": 16]
    private static let floatComponent = 5126

    private static func validate(_ json: [String: Any], directory: URL, binChunkLength: Int?) throws(ModelLoadError) {
        func objects(_ key: String) -> [[String: Any]] { json[key] as? [[String: Any]] ?? [] }
        func fail(_ reason: String) -> ModelLoadError { .malformed(reason: reason) }

        let buffers = objects("buffers"), views = objects("bufferViews"), accessors = objects("accessors")
        let meshes = objects("meshes"), nodes = objects("nodes"), scenes = objects("scenes")
        let materialCount = objects("materials").count

        var bufferLengths: [Int] = []
        for (index, buffer) in buffers.enumerated() {
            guard let length = buffer["byteLength"] as? Int, length > 0 else { throw fail("buffer \(index) has no byteLength") }
            bufferLengths.append(length)
            if let uri = buffer["uri"] as? String {
                guard !uri.hasPrefix("data:") else { continue }
                guard let resolved = URL(string: uri, relativeTo: directory) else { throw fail("buffer \(index) has an invalid uri") }
                guard FileManager.default.fileExists(atPath: resolved.path) else { throw .missingResource(uri) }
                let size = (try? FileManager.default.attributesOfItem(atPath: resolved.path)[.size] as? Int) ?? 0
                guard size >= length else { throw fail("buffer “\(uri)” is shorter than its byteLength") }
            } else {
                // Without a uri only the GLB's BIN chunk can provide the first buffer.
                guard index == 0, let binChunkLength, binChunkLength >= length else {
                    throw fail("buffer \(index) has no data")
                }
            }
        }

        var viewLengths: [Int] = []
        for (index, view) in views.enumerated() {
            guard let buffer = view["buffer"] as? Int, bufferLengths.indices.contains(buffer),
                  let length = view["byteLength"] as? Int, length > 0 else { throw fail("bufferView \(index) is invalid") }
            let offset = view["byteOffset"] as? Int ?? 0
            guard offset >= 0, offset + length <= bufferLengths[buffer] else {
                throw fail("bufferView \(index) exceeds its buffer")
            }
            viewLengths.append(length)
        }

        var accessorComponents: [Int] = []
        for (index, accessor) in accessors.enumerated() {
            guard let component = accessor["componentType"] as? Int, let size = componentSizes[component],
                  let type = accessor["type"] as? String, let count = componentCounts[type],
                  let elements = accessor["count"] as? Int, elements > 0 else { throw fail("accessor \(index) is invalid") }
            accessorComponents.append(component)
            guard let view = accessor["bufferView"] as? Int else { continue }
            guard viewLengths.indices.contains(view) else { throw fail("accessor \(index) refers to a missing bufferView") }
            let stride = views[view]["byteStride"] as? Int ?? size * count
            let offset = accessor["byteOffset"] as? Int ?? 0
            guard offset >= 0, stride > 0, offset + (elements - 1) * stride + size * count <= viewLengths[view] else {
                throw fail("accessor \(index) exceeds its bufferView")
            }
        }

        for (meshIndex, mesh) in meshes.enumerated() {
            for primitive in mesh["primitives"] as? [[String: Any]] ?? [] {
                for (name, value) in primitive["attributes"] as? [String: Any] ?? [:] {
                    guard let accessor = value as? Int, accessorComponents.indices.contains(accessor) else {
                        throw fail("mesh \(meshIndex) attribute \(name) refers to a missing accessor")
                    }
                    if name == "POSITION", accessorComponents[accessor] != floatComponent {
                        throw .unsupportedFeature("quantized vertex positions")
                    }
                }
                if let indices = primitive["indices"] as? Int, !accessorComponents.indices.contains(indices) {
                    throw fail("mesh \(meshIndex) refers to a missing index accessor")
                }
                if let material = primitive["material"] as? Int, !(0..<materialCount).contains(material) {
                    throw fail("mesh \(meshIndex) refers to a missing material")
                }
            }
        }

        for (index, node) in nodes.enumerated() {
            if let mesh = node["mesh"] as? Int, !meshes.indices.contains(mesh) { throw fail("node \(index) refers to a missing mesh") }
            for child in node["children"] as? [Int] ?? [] where !nodes.indices.contains(child) {
                throw fail("node \(index) refers to a missing child")
            }
        }
        for (index, scene) in scenes.enumerated() {
            for root in scene["nodes"] as? [Int] ?? [] where !nodes.indices.contains(root) {
                throw fail("scene \(index) refers to a missing node")
            }
        }
        if let scene = json["scene"] as? Int, !scenes.indices.contains(scene) { throw fail("the default scene is missing") }
        try requireAcyclic(nodes)
    }

    /// GLTFKit2 would recurse forever on a node that is its own ancestor.
    private static func requireAcyclic(_ nodes: [[String: Any]]) throws(ModelLoadError) {
        var state = [Int](repeating: 0, count: nodes.count)          // 0 new, 1 on the path, 2 done
        func cyclic(_ index: Int) -> Bool {
            if state[index] == 1 { return true }
            if state[index] == 2 { return false }
            state[index] = 1
            for child in nodes[index]["children"] as? [Int] ?? [] where cyclic(child) { return true }
            state[index] = 2
            return false
        }
        for index in nodes.indices where cyclic(index) { throw .malformed(reason: "the node tree has a cycle") }
    }
}
