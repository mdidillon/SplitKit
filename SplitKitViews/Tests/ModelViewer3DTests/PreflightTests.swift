import Foundation
import Testing
@testable import ModelViewer3D

/// The up-front checks (spec §11.1 P4 risks) on small hand-built files: each refusal is a typed error, none needs GLTFKit2.
@Suite struct PreflightTests {
    /// A valid one-triangle asset (36 bytes of positions in a data URI) that `change` edits.
    private func asset(_ change: (inout [String: Any]) -> Void = { _ in }) throws -> Data {
        var json: [String: Any] = [
            "asset": ["version": "2.0"],
            "scene": 0,
            "scenes": [["nodes": [0]]],
            "nodes": [["mesh": 0]],
            "meshes": [["primitives": [["attributes": ["POSITION": 0]]]]],
            "buffers": [["uri": "data:application/octet-stream;base64," + Data(count: 36).base64EncodedString(), "byteLength": 36]],
            "bufferViews": [["buffer": 0, "byteOffset": 0, "byteLength": 36]],
            "accessors": [["bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3", "min": [0, 0, 0], "max": [0, 0, 0]]],
        ]
        change(&json)
        return try JSONSerialization.data(withJSONObject: json)
    }

    /// A GLB container around `json` (space padded) and an optional BIN chunk.
    private func glb(_ json: Data, bin: Data? = nil) -> Data {
        func u32(_ value: Int) -> Data { withUnsafeBytes(of: UInt32(value).littleEndian) { Data($0) } }
        var jsonChunk = json
        while jsonChunk.count % 4 != 0 { jsonChunk.append(0x20) }
        var body = u32(jsonChunk.count) + u32(0x4E4F_534A) + jsonChunk
        if let bin { body += u32(bin.count) + u32(0x004E_4942) + bin }
        return u32(0x4654_6C67) + u32(2) + u32(12 + body.count) + body
    }

    private func check(_ data: Data, as fileName: String = "model.gltf") async throws -> ModelLoadError? {
        try await withTemporaryDirectory { dir in
            let url = dir.appending(path: fileName)
            try data.write(to: url)
            return preflightError(url)
        }
    }

    @Test func aValidAssetPasses() async throws {
        #expect(try await check(asset()) == nil)
        let binary = try asset { json in
            json["buffers"] = [["byteLength": 36]]
        }
        #expect(try await check(glb(binary, bin: Data(count: 36)), as: "model.glb") == nil)
    }

    @Test func theExtensionDecidesTheFormat() async throws {
        #expect(try await check(asset(), as: "model.fbx") == .unsupportedFormat(fileExtension: "fbx"))
        #expect(try await check(asset(), as: "model.obj") == .unsupportedFormat(fileExtension: "obj"))
        #expect(try await check(asset(), as: "MODEL.GLTF") == nil)
    }

    @Test(arguments: ["KHR_draco_mesh_compression", "KHR_mesh_quantization", "EXT_meshopt_compression"])
    func requiredExtensionsThatCannotBeDecodedAreRefused(name: String) async throws {
        let data = try asset { $0["extensionsRequired"] = [name]; $0["extensionsUsed"] = [name] }
        #expect(try await check(data) == .unsupportedRequiredExtensions([name]))
    }

    @Test func otherRequiredExtensionsPass() async throws {
        let data = try asset { $0["extensionsRequired"] = ["KHR_texture_basisu"]; $0["extensionsUsed"] = ["KHR_texture_basisu"] }
        #expect(try await check(data) == nil)
    }

    @Test func quantizedPositionsAreRefusedEvenWithoutTheExtensionHeader() async throws {
        let data = try asset { json in
            json["accessors"] = [["bufferView": 0, "componentType": 5122, "count": 3, "type": "VEC3"]]
        }
        #expect(try await check(data) == .unsupportedFeature("quantized vertex positions"))
    }

    @Test func brokenIndicesAndRangesAreMalformed() async throws {
        let cases: [(String, (inout [String: Any]) -> Void)] = [
            ("accessor beyond its bufferView", { $0["accessors"] = [["bufferView": 0, "componentType": 5126, "count": 100, "type": "VEC3"]] }),
            ("accessor with a missing bufferView", { $0["accessors"] = [["bufferView": 5, "componentType": 5126, "count": 3, "type": "VEC3"]] }),
            ("accessor with an unknown type", { $0["accessors"] = [["bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC9"]] }),
            ("bufferView beyond its buffer", { $0["bufferViews"] = [["buffer": 0, "byteOffset": 20, "byteLength": 36]] }),
            ("bufferView with a missing buffer", { $0["bufferViews"] = [["buffer": 3, "byteLength": 36]] }),
            ("attribute with a missing accessor", { $0["meshes"] = [["primitives": [["attributes": ["POSITION": 9]]]]] }),
            ("primitive with a missing material", { $0["meshes"] = [["primitives": [["attributes": ["POSITION": 0], "material": 4]]]] }),
            ("node with a missing mesh", { $0["nodes"] = [["mesh": 3]] }),
            ("node with a missing child", { $0["nodes"] = [["children": [7]]] }),
            ("node that is its own ancestor", { $0["nodes"] = [["children": [1]], ["children": [0]]] }),
            ("scene with a missing node", { $0["scenes"] = [["nodes": [4]]] }),
            ("missing default scene", { $0["scene"] = 2 }),
            ("no asset version", { $0["asset"] = [String: String]() }),
            ("glTF 1.0", { $0["asset"] = ["version": "1.0"] }),
            ("buffer without data", { $0["buffers"] = [["byteLength": 36]] }),
        ]
        for (name, change) in cases {
            let error = try await check(asset(change))
            guard case .malformed? = error else {
                Issue.record("\(name): expected .malformed, got \(String(describing: error))")
                continue
            }
        }
    }

    @Test func aBufferShorterThanItsByteLengthIsMalformed() async throws {
        let error = try await withTemporaryDirectory { dir in
            try Data(count: 10).write(to: dir.appending(path: "short.bin"))
            let json = try asset { $0["buffers"] = [["uri": "short.bin", "byteLength": 36]] }
            let url = dir.appending(path: "model.gltf")
            try json.write(to: url)
            return preflightError(url)
        }
        guard case .malformed? = error else { Issue.record("got \(String(describing: error))"); return }
    }

    @Test func aMissingExternalBufferIsNamed() async throws {
        let data = try asset { $0["buffers"] = [["uri": "gone.bin", "byteLength": 36]] }
        #expect(try await check(data) == .missingResource("gone.bin"))
    }

    @Test func brokenContainersAreMalformed() async throws {
        let json = try asset { $0["buffers"] = [["byteLength": 36]] }
        let cases: [(String, Data)] = [
            ("not JSON", Data("not json".utf8)),
            ("JSON that is not an object", Data("[1, 2]".utf8)),
            ("empty file", Data()),
            ("GLB without a BIN chunk for a buffer without a uri", glb(json)),
            ("GLB with a short BIN chunk", glb(json, bin: Data(count: 8))),
            ("GLB header only", glb(Data()).prefix(12)),
        ]
        for (name, data) in cases {
            let error = try await check(data, as: name.hasPrefix("GLB") ? "model.glb" : "model.gltf")
            guard case .malformed? = error else {
                Issue.record("\(name): expected .malformed, got \(String(describing: error))")
                continue
            }
        }
    }

    @Test func errorsMapToContentErrors() {
        let url = URL(fileURLWithPath: "/tmp/x.glb")
        guard case .unreadable = ModelLoadError.fileNotFound.contentError(for: url) else {
            Issue.record("a missing file must be .unreadable")
            return
        }
        for error in [ModelLoadError.unsupportedFormat(fileExtension: "fbx"), .malformed(reason: "x"), .missingResource("a.bin"),
                      .unsupportedRequiredExtensions(["KHR_draco_mesh_compression"]), .unsupportedFeature("x"), .noDefaultScene] {
            guard case let .unsupportedFile(file, reason) = error.contentError(for: url) else {
                Issue.record("\(error) must be .unsupportedFile")
                continue
            }
            #expect(file == url)
            #expect(reason == error.reason)
            #expect(!reason.hasSuffix("."), "the banner adds the full stop: \(reason)")
        }
    }
}
