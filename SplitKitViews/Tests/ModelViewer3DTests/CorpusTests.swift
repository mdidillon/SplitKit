import Foundation
@preconcurrency import GLTFKit2
import RealityKit
import simd
import Testing
@testable import ModelViewer3D

struct CorpusModel: CustomTestStringConvertible, Sendable {
    let path: String
    let feature: String
    var testDescription: String { path }
}

/// The required spec §10 corpus rows (Khronos glTF-Sample-Assets; the 2 Artifex exports are a recorded gap).
let requiredModels: [CorpusModel] = [
    .init(path: "Box/glTF/Box.gltf", feature: "mesh, external .bin"),
    .init(path: "BoxTextured/glTF/BoxTextured.gltf", feature: "external .bin + png"),
    .init(path: "Duck/glTF-Binary/Duck.glb", feature: "GLB embedded texture"),
    .init(path: "DamagedHelmet/glTF-Binary/DamagedHelmet.glb", feature: "GLB PBR MR base/normal/ORM/emissive"),
    .init(path: "CesiumMilkTruck/glTF/CesiumMilkTruck.gltf", feature: "node hierarchy/transforms, .gltf + jpg"),
]

private let maximumLoad = Duration.seconds(2)
private let maximumFileSize = 20_000_000

@MainActor
@Suite(.serialized)
struct CorpusTests {
    /// Loads through the product path (preflight, background parse, main-actor conversion) and measures the wall clock.
    private func load(_ path: String) async throws -> (model: LoadedModel, wall: Duration) {
        let clock = ContinuousClock()
        let start = clock.now
        let model = try await ModelLoader.load(url: Fixtures.url(path))
        return (model, clock.now - start)
    }

    /// Animations only run on entities in a scene: hosts `entity` in an offscreen RealityRenderer, loops its first
    /// animation, steps 10 frames and runs `check` while the scene is still alive.
    private func playFirstAnimation(of entity: Entity, _ check: (AnimationPlaybackController) -> Void) throws {
        let renderer = try RealityRenderer()
        renderer.entities.append(entity)
        let animation = try #require(entity.availableAnimations.first)
        let controller = entity.playAnimation(animation.repeat())
        for _ in 0..<10 { try renderer.update(1 / 30) }
        check(controller)
    }

    // MARK: Required rows

    @Test("Loads, bounds within 1% of glTF accessor reference, ≤ 2 s, no missing textures", arguments: requiredModels)
    func requiredModelLoads(model: CorpusModel) async throws {
        let url = Fixtures.url(model.path)
        let reference = try ReferenceGeometry(url: url)
        let (loaded, wall) = try await load(model.path)
        let r = loaded.report
        let deviation = loaded.bounds.relativeDeviation(from: reference.bounds)

        record(["model": url.lastPathComponent, "bytes": "\(r.fileSize)",
                "parse_ms": String(format: "%.1f", r.parseDuration.milliseconds),
                "convert_ms": String(format: "%.1f", r.convertDuration.milliseconds),
                "total_ms": String(format: "%.1f", r.totalDuration.milliseconds),
                "wall_ms": String(format: "%.1f", wall.milliseconds),
                "bbox_dev_pct": String(format: "%.4f", deviation * 100),
                "tex_slots": "\(r.convertedTextureSlots)/\(r.expectedTextureSlots)",
                "warnings": "\(r.textureWarnings.count)",
                "ext": r.extensionsUsed.isEmpty ? "-" : r.extensionsUsed.joined(separator: ",")])

        #expect(!loaded.bounds.isEmpty)
        #expect(deviation <= 0.01, "measured \(loaded.bounds) vs reference \(reference.bounds)")
        #expect(r.fileSize <= maximumFileSize)
        #expect(r.totalDuration <= maximumLoad)
        #expect(wall <= maximumLoad)
        #expect(r.textureWarnings.isEmpty, "\(r.textureWarnings)")
        #expect(r.convertedTextureSlots == r.expectedTextureSlots)
    }

    @Test("+Y up: per-axis extents match the reference (no axis swap or mirror)", arguments: requiredModels)
    func yUpOrientation(model: CorpusModel) async throws {
        let url = Fixtures.url(model.path)
        let reference = try ReferenceGeometry(url: url)
        let (loaded, _) = try await load(model.path)
        // Root of the converted scene must not add any up-axis conversion.
        #expect(loaded.entity.transform.matrix == matrix_identity_float4x4)
        let tolerance = reference.bounds.diagonal * 0.01
        for axis in 0..<3 {
            #expect(abs(loaded.bounds.min[axis] - reference.bounds.min[axis]) <= tolerance, "axis \(axis) min")
            #expect(abs(loaded.bounds.max[axis] - reference.bounds.max[axis]) <= tolerance, "axis \(axis) max")
        }
        record(["model": url.lastPathComponent,
                "ref_extents": String(format: "%.4f,%.4f,%.4f", reference.bounds.extents.x,
                                      reference.bounds.extents.y, reference.bounds.extents.z),
                "rk_extents": String(format: "%.4f,%.4f,%.4f", loaded.bounds.extents.x,
                                     loaded.bounds.extents.y, loaded.bounds.extents.z)])
    }

    @Test("Node hierarchy: entity world transforms equal glTF node world matrices")
    func nodeHierarchyTransforms() async throws {
        let path = "CesiumMilkTruck/glTF/CesiumMilkTruck.gltf"
        let reference = try ReferenceGeometry(url: Fixtures.url(path))
        let (loaded, _) = try await load(path)
        let names = reference.nodes.compactMap(\.name)
        var compared = 0
        for node in reference.nodes {
            guard let name = node.name, names.filter({ $0 == name }).count == 1,
                  let entity = loaded.entity.findEntity(named: name) else { continue }
            let m = entity.transformMatrix(relativeTo: nil)
            for c in 0..<4 {
                #expect(simd_length(m[c] - node.worldMatrix[c]) < 1e-4, "\(name) column \(c)")
            }
            compared += 1
        }
        #expect(compared >= 5)
        record(["model": "CesiumMilkTruck.gltf", "nodes_compared": "\(compared)", "nodes_total": "\(reference.nodes.count)"])
    }

    @Test("Official one-call API GLTFRealityKitLoader.load(from:) gives the same bounds")
    func officialAsyncLoaderAPI() async throws {
        let url = Fixtures.url(Fixtures.helmet)
        let entity = try await GLTFRealityKitLoader.load(from: url)
        let reference = try ReferenceGeometry(url: url)
        #expect(ModelLoader.measuredBounds(of: entity).relativeDeviation(from: reference.bounds) <= 0.01)
    }

    @Test("Missing-texture detector fires when a referenced image is absent (negative control)")
    func missingTextureIsReported() async throws {
        let (loaded, _) = try await withTemporaryDirectory { dir in
            for file in ["BoxTextured.gltf", "BoxTextured0.bin"] { // CesiumLogoFlat.png deliberately not copied
                try FileManager.default.copyItem(at: Fixtures.url("BoxTextured/glTF/\(file)"), to: dir.appending(path: file))
            }
            let clock = ContinuousClock()
            let start = clock.now
            return (try await ModelLoader.load(url: dir.appending(path: "BoxTextured.gltf")), clock.now - start)
        }
        record(["model": "BoxTextured(no png)", "warnings": "\(loaded.report.textureWarnings.count)",
                "first": loaded.report.textureWarnings.first?.replacingOccurrences(of: " ", with: "_") ?? "-"])
        #expect(!loaded.report.textureWarnings.isEmpty)
        #expect(loaded.report.convertedTextureSlots < loaded.report.expectedTextureSlots)
    }

    // MARK: Error path (typed error, no crash)

    @Test func malformedGLTFThrowsTypedError() async {
        let error = await loadError(Fixtures.malformed)
        guard case .malformed(let reason)? = error else { Issue.record("got \(String(describing: error))"); return }
        record(["case": "malformed.gltf", "error": "malformed", "reason": reason.replacingOccurrences(of: " ", with: "_")])
    }

    @Test func fbxIsRejectedAsUnsupportedFormat() async {
        #expect(await loadError(Fixtures.fbx) == .unsupportedFormat(fileExtension: "fbx"))
    }

    @Test("FBX bytes renamed to .glb/.gltf fail cleanly", arguments: ["glb", "gltf"])
    func fbxBytesDisguisedAsGLTF(ext: String) async throws {
        let error = try await withTemporaryDirectory { dir in
            let url = dir.appending(path: "fake.\(ext)")
            try FileManager.default.copyItem(at: Fixtures.url(Fixtures.fbx), to: url)
            return await loadError(url)
        }
        guard case .malformed? = error else { Issue.record("got \(String(describing: error))"); return }
        record(["case": "fake.fbx-as-.\(ext)", "error": "malformed"])
    }

    @Test func missingExternalBufferThrowsTypedError() async {
        let error = await loadError(Fixtures.missingBuffer)
        record(["case": "missing-buffer.gltf", "error": "\(String(describing: error))".replacingOccurrences(of: " ", with: "_")])
        #expect(error == .missingResource("does-not-exist.bin"))
    }

    @Test func nonexistentFileThrowsFileNotFound() async {
        #expect(await loadError("Errors/does-not-exist.glb") == .fileNotFound)
    }

    @Test("Draco: GLTFKit2 ships no decoder; required-extension files are refused up front",
          arguments: ["Box/glTF-Draco/Box.gltf", "Duck/glTF-Draco/Duck.gltf"])
    func dracoIsRefused(path: String) async throws {
        try #require(Fixtures.exists(path))
        // What GLTFKit2 itself does with the file, recorded for the corpus results.
        var rawOutcome = "parsed"
        do {
            let asset = try GLTFAsset(url: Fixtures.url(path), options: [:])
            rawOutcome = "parsed(required=\(asset.extensionsRequired.joined(separator: ",")))"
        } catch {
            rawOutcome = "threw(\((error as NSError).code))"
        }
        record(["model": path, "gltfkit2_raw": rawOutcome])
        #expect(await loadError(path) == .unsupportedRequiredExtensions(["KHR_draco_mesh_compression"]))
    }

    // MARK: Optional rows

    @Test("Skinning/animation: animations exposed on the entity and playing",
          arguments: ["CesiumMan/glTF-Binary/CesiumMan.glb", "RiggedSimple/glTF-Binary/RiggedSimple.glb"])
    func skinnedAnimation(path: String) async throws {
        try #require(Fixtures.exists(path))
        let (loaded, _) = try await load(path)
        let r = loaded.report
        record(["model": (path as NSString).lastPathComponent, "skins": "\(r.hasSkins)",
                "gltf_anims": "\(r.gltfAnimationCount)", "rk_anims": "\(r.availableAnimationCount)",
                "total_ms": String(format: "%.1f", r.totalDuration.milliseconds)])
        #expect(r.hasSkins)
        #expect(r.availableAnimationCount == r.gltfAnimationCount)
        try playFirstAnimation(of: loaded.entity) { controller in
            record(["model": (path as NSString).lastPathComponent, "playing": "\(controller.isPlaying)",
                    "time_s": String(format: "%.3f", controller.time)])
            #expect(controller.isPlaying)
            #expect(controller.time > 0)
        }
    }

    /// GLTFKit2 0.5.15 samples a node's channels every `duration / keyCount` seconds, so a zero-duration channel group
    /// (one keyframe, the usual "pose" export) traps in `stride(by: 0)`. Node 0 has such a channel in both animations;
    /// node 1 moves over 1 s in the second.
    @Test("Zero-duration animation channels: load without crash, skipped and reported as unsupported")
    func zeroDurationAnimationChannelsAreSkipped() async throws {
        func floats(_ values: [Float]) -> Data { values.withUnsafeBytes { Data($0) } }
        let bin = Data(count: 36) + floats([0]) + floats([1, 0, 0]) + floats([0, 1]) + floats([0, 0, 0, 0, 1, 0])
        let data = try triangleAsset { json in
            json["scenes"] = [["nodes": [0, 1]]]
            json["nodes"] = [["mesh": 0, "name": "Posed"], ["mesh": 0, "name": "Moving"]]
            json["buffers"] = [["uri": "data:application/octet-stream;base64," + bin.base64EncodedString(), "byteLength": bin.count]]
            json["bufferViews"] = [(0, 36), (36, 4), (40, 12), (52, 8), (60, 24)].map {
                ["buffer": 0, "byteOffset": $0.0, "byteLength": $0.1]
            }
            json["accessors"] = [
                ["bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3", "min": [0, 0, 0], "max": [0, 0, 0]],
                ["bufferView": 1, "componentType": 5126, "count": 1, "type": "SCALAR", "min": [0], "max": [0]],
                ["bufferView": 2, "componentType": 5126, "count": 1, "type": "VEC3"],
                ["bufferView": 3, "componentType": 5126, "count": 2, "type": "SCALAR", "min": [0], "max": [1]],
                ["bufferView": 4, "componentType": 5126, "count": 2, "type": "VEC3"],
            ]
            json["animations"] = [
                ["name": "Pose", "samplers": [["input": 1, "output": 2]],
                 "channels": [["sampler": 0, "target": ["node": 0, "path": "translation"]]]],
                ["name": "Move", "samplers": [["input": 3, "output": 4], ["input": 1, "output": 2]],
                 "channels": [["sampler": 0, "target": ["node": 1, "path": "translation"]],
                              ["sampler": 1, "target": ["node": 0, "path": "translation"]]]],
            ]
        }
        try await withTemporaryDirectory { dir in
            let url = dir.appending(path: "pose.gltf")
            try data.write(to: url)
            let loaded = try await ModelLoader.load(url: url)
            let r = loaded.report
            record(["model": "pose.gltf", "gltf_anims": "\(r.gltfAnimationCount)", "rk_anims": "\(r.availableAnimationCount)",
                    "skipped_channels": "\(r.skippedAnimationChannels)",
                    "unsupported": r.unsupportedFeatures.joined(separator: ",")])
            #expect(r.gltfAnimationCount == 2)
            #expect(r.availableAnimationCount == 1)
            #expect(r.skippedAnimationChannels == 2)
            #expect(r.unsupportedFeatures.contains("animation channels without a duration"))

            try playFirstAnimation(of: loaded.entity) { controller in
                #expect(controller.isPlaying)
                #expect(controller.time > 0)
            }
        }
    }

    /// The skeletal path: one joint group without a duration sets the interval of the whole skeletal animation to 0.
    @Test func zeroDurationJointChannelsAreSkipped() async throws {
        let path = "CesiumMan/glTF-Binary/CesiumMan.glb"
        try #require(Fixtures.exists(path))
        let asset = try GLTFAsset(url: Fixtures.url(path), options: [:])
        let animation = try #require(asset.animations.first)
        let joint = try #require(animation.channels.first { $0.target.node?.isJoint == true }?.target.node)
        let jointChannels = animation.channels.filter { $0.target.node === joint }
        for channel in jointChannels { channel.sampler.input.minValues = channel.sampler.input.maxValues }

        #expect(AnimationFilter.removeUnsampleableChannels(from: asset) == jointChannels.count)
        #expect(asset.animations.count == 1)
        let entity = GLTFRealityKitLoader.convert(scene: try #require(asset.defaultScene), asset: asset)
        try playFirstAnimation(of: entity) { controller in
            #expect(controller.isPlaying)
            #expect(controller.time > 0)
        }
    }

    @Test("Morph targets: load without crash and are reported as unsupported")
    func morphTargetsReportedUnsupported() async throws {
        let path = "AnimatedMorphCube/glTF-Binary/AnimatedMorphCube.glb"
        try #require(Fixtures.exists(path))
        let (loaded, _) = try await load(path)
        let r = loaded.report
        record(["model": "AnimatedMorphCube.glb", "morph": "\(r.hasMorphTargets)",
                "gltf_anims": "\(r.gltfAnimationCount)", "rk_anims": "\(r.availableAnimationCount)",
                "unsupported": r.unsupportedFeatures.joined(separator: ",")])
        #expect(r.hasMorphTargets)
        #expect(r.unsupportedFeatures.contains("morph targets"))
    }

    @Test func transmissionIsParsedButNotConverted() async throws {
        let path = "TransmissionTest/glTF-Binary/TransmissionTest.glb"
        try #require(Fixtures.exists(path))
        let (loaded, _) = try await load(path)
        record(["model": "TransmissionTest.glb", "ext": loaded.report.extensionsUsed.joined(separator: ","),
                "unsupported": loaded.report.unsupportedFeatures.joined(separator: ","),
                "warnings": "\(loaded.report.textureWarnings.count)"])
        #expect(loaded.report.extensionsUsed.contains("KHR_materials_transmission"))
        #expect(loaded.report.unsupportedFeatures.contains("KHR_materials_transmission"))
    }

    @Test func clearcoatIsConverted() async throws {
        let path = "ClearCoatTest/glTF-Binary/ClearCoatTest.glb"
        try #require(Fixtures.exists(path))
        let (loaded, _) = try await load(path)
        var coated = 0
        func visit(_ e: Entity) {
            for m in e.components[ModelComponent.self]?.materials ?? [] {
                if let pbr = m as? PhysicallyBasedMaterial, pbr.clearcoat.scale > 0 { coated += 1 }
            }
            e.children.forEach(visit)
        }
        visit(loaded.entity)
        record(["model": "ClearCoatTest.glb", "clearcoat_materials": "\(coated)",
                "unsupported": loaded.report.unsupportedFeatures.joined(separator: ",")])
        #expect(loaded.report.extensionsUsed.contains("KHR_materials_clearcoat"))
        #expect(coated > 0)
    }

    // MARK: Helpers

    private func loadError(_ path: String) async -> ModelLoadError? { await loadError(Fixtures.url(path)) }

    private func loadError(_ url: URL) async -> ModelLoadError? {
        do { _ = try await ModelLoader.load(url: url) } catch { return error }
        return nil
    }
}
