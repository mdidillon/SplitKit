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
        // Animations only run on entities in a scene: host it in an offscreen RealityRenderer, start playback, step.
        let renderer = try RealityRenderer()
        renderer.entities.append(loaded.entity)
        let animation = try #require(loaded.entity.availableAnimations.first)
        let controller = loaded.entity.playAnimation(animation.repeat())
        for _ in 0..<10 { try renderer.update(1 / 30) }
        record(["model": (path as NSString).lastPathComponent, "playing": "\(controller.isPlaying)",
                "time_s": String(format: "%.3f", controller.time)])
        #expect(controller.isPlaying)
        #expect(controller.time > 0)
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
