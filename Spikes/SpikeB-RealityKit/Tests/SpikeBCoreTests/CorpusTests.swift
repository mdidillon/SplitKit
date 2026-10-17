import Foundation
@preconcurrency import GLTFKit2
import RealityKit
import simd
import SpikeBCore
import Testing

enum Fixtures {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    static func url(_ path: String) -> URL { root.appendingPathComponent(path) }

    static let missingMessage: Comment = "Corpus missing: run ./scripts/fetch-corpus.sh in Spikes/SpikeB-RealityKit"
    static var corpusAvailable: Bool {
        FileManager.default.fileExists(atPath: url("DamagedHelmet/glTF-Binary/DamagedHelmet.glb").path)
    }
    static func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: url(path).path) }
}

/// One machine-greppable line per measurement, summarised in spec §11.1.
func record(_ fields: KeyValuePairs<String, String>) {
    print("SPIKEB-RESULT " + fields.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
}

struct CorpusModel: CustomTestStringConvertible, Sendable {
    let path: String
    let feature: String
    var testDescription: String { path }
}

/// The required §10 corpus rows.
let requiredModels: [CorpusModel] = [
    .init(path: "Box/glTF/Box.gltf", feature: "mesh, external .bin"),
    .init(path: "BoxTextured/glTF/BoxTextured.gltf", feature: "external .bin + png"),
    .init(path: "Duck/glTF-Binary/Duck.glb", feature: "GLB embedded texture"),
    .init(path: "DamagedHelmet/glTF-Binary/DamagedHelmet.glb", feature: "GLB PBR MR base/normal/ORM/emissive"),
    .init(path: "CesiumMilkTruck/glTF/CesiumMilkTruck.gltf", feature: "node hierarchy/transforms, .gltf + jpg"),
]

@MainActor
@Suite(.serialized, .enabled(if: Fixtures.corpusAvailable, Fixtures.missingMessage))
struct CorpusTests {
    // MARK: Required rows

    @Test("Loads, bounds within 1% of glTF accessor reference, ≤ 2 s, no missing textures", arguments: requiredModels)
    func requiredModelLoads(model: CorpusModel) throws {
        let url = Fixtures.url(model.path)
        let reference = try ReferenceGeometry(url: url)
        let loaded = try ModelLoader.load(url: url)
        let r = loaded.report
        let deviation = loaded.bounds.relativeDeviation(from: reference.bounds)

        record(["model": url.lastPathComponent, "bytes": "\(r.fileSize)",
                "parse_ms": String(format: "%.1f", r.parseDuration.milliseconds),
                "convert_ms": String(format: "%.1f", r.convertDuration.milliseconds),
                "total_ms": String(format: "%.1f", r.totalDuration.milliseconds),
                "bbox_dev_pct": String(format: "%.4f", deviation * 100),
                "tex_slots": "\(r.convertedTextureSlots)/\(r.expectedTextureSlots)",
                "warnings": "\(r.textureWarnings.count)",
                "ext": r.extensionsUsed.isEmpty ? "-" : r.extensionsUsed.joined(separator: ",")])

        #expect(!loaded.bounds.isEmpty)
        #expect(deviation <= 0.01, "measured \(loaded.bounds) vs reference \(reference.bounds)")
        #expect(r.fileSize <= 20_000_000)
        #expect(r.totalDuration <= .seconds(2))
        #expect(r.textureWarnings.isEmpty, "\(r.textureWarnings)")
        #expect(r.convertedTextureSlots == r.expectedTextureSlots)
    }

    @Test("+Y up: per-axis extents match the reference (no axis swap or mirror)", arguments: requiredModels)
    func yUpOrientation(model: CorpusModel) throws {
        let url = Fixtures.url(model.path)
        let reference = try ReferenceGeometry(url: url)
        let loaded = try ModelLoader.load(url: url)
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
    func nodeHierarchyTransforms() throws {
        let url = Fixtures.url("CesiumMilkTruck/glTF/CesiumMilkTruck.gltf")
        let reference = try ReferenceGeometry(url: url)
        let loaded = try ModelLoader.load(url: url)
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
        record(["model": url.lastPathComponent, "nodes_compared": "\(compared)", "nodes_total": "\(reference.nodes.count)"])
    }

    @Test("Official one-call API GLTFRealityKitLoader.load(from:) gives the same bounds")
    func officialAsyncLoaderAPI() async throws {
        let url = Fixtures.url("DamagedHelmet/glTF-Binary/DamagedHelmet.glb")
        let entity = try await GLTFRealityKitLoader.load(from: url)
        let reference = try ReferenceGeometry(url: url)
        #expect(ModelLoader.measuredBounds(of: entity).relativeDeviation(from: reference.bounds) <= 0.01)
    }

    @Test("Missing-texture detector fires when a referenced image is absent (negative control)")
    func missingTextureIsReported() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SpikeB-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for file in ["BoxTextured.gltf", "BoxTextured0.bin"] { // CesiumLogoFlat.png deliberately not copied
            try FileManager.default.copyItem(at: Fixtures.url("BoxTextured/glTF/\(file)"),
                                             to: dir.appendingPathComponent(file))
        }
        let loaded = try ModelLoader.load(url: dir.appendingPathComponent("BoxTextured.gltf"))
        record(["model": "BoxTextured(no png)", "warnings": "\(loaded.report.textureWarnings.count)",
                "first": loaded.report.textureWarnings.first?.replacingOccurrences(of: " ", with: "_") ?? "-"])
        #expect(!loaded.report.textureWarnings.isEmpty)
        #expect(loaded.report.convertedTextureSlots < loaded.report.expectedTextureSlots)
    }

    // MARK: Error path

    @Test func malformedGLTFThrowsTypedError() {
        #expect {
            try ModelLoader.load(url: Fixtures.url("Errors/malformed.gltf"))
        } throws: { error in
            guard case .malformed(let code, let message)? = error as? ModelLoadError else { return false }
            record(["case": "malformed.gltf", "error": "malformed", "code": "\(code)",
                    "message": message.replacingOccurrences(of: " ", with: "_")])
            return true
        }
    }

    @Test func fbxIsRejectedAsUnsupportedFormat() {
        #expect(throws: ModelLoadError.unsupportedFormat(fileExtension: "fbx")) {
            try ModelLoader.load(url: Fixtures.url("Errors/fake.fbx"))
        }
    }

    @Test("FBX bytes renamed to .glb/.gltf reach GLTFKit2 and still fail cleanly", arguments: ["glb", "gltf"])
    func fbxBytesDisguisedAsGLTF(ext: String) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SpikeB-fake-\(UUID().uuidString).\(ext)")
        try FileManager.default.copyItem(at: Fixtures.url("Errors/fake.fbx"), to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect {
            try ModelLoader.load(url: url)
        } throws: { error in
            guard case .malformed(let code, _)? = error as? ModelLoadError else { return false }
            record(["case": "fake.fbx-as-.\(ext)", "error": "malformed", "code": "\(code)"])
            return true
        }
    }

    @Test func missingExternalBufferThrowsTypedError() {
        #expect {
            try ModelLoader.load(url: Fixtures.url("Errors/missing-buffer.gltf"))
        } throws: { error in
            record(["case": "missing-buffer.gltf", "error": "\(error)".replacingOccurrences(of: " ", with: "_")])
            return error is ModelLoadError
        }
    }

    @Test func nonexistentFileThrowsFileNotFound() {
        #expect(throws: ModelLoadError.fileNotFound) {
            try ModelLoader.load(url: Fixtures.url("Errors/does-not-exist.glb"))
        }
    }

    // MARK: Optional rows

    @Test("Skinning/animation: animations exposed on the entity",
          arguments: ["CesiumMan/glTF-Binary/CesiumMan.glb", "RiggedSimple/glTF-Binary/RiggedSimple.glb"])
    func skinnedAnimation(path: String) throws {
        try #require(Fixtures.exists(path), Fixtures.missingMessage)
        let loaded = try ModelLoader.load(url: Fixtures.url(path))
        let r = loaded.report
        record(["model": (path as NSString).lastPathComponent, "skins": "\(r.hasSkins)",
                "gltf_anims": "\(r.gltfAnimationCount)", "rk_anims": "\(r.availableAnimationCount)",
                "total_ms": String(format: "%.1f", r.totalDuration.milliseconds)])
        #expect(r.hasSkins)
        #expect(r.availableAnimationCount == r.gltfAnimationCount)
        // Plays: animations only run on entities in a scene, so host it in an offscreen RealityRenderer,
        // start playback and step the simulation.
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
    func morphTargetsReportedUnsupported() throws {
        let path = "AnimatedMorphCube/glTF-Binary/AnimatedMorphCube.glb"
        try #require(Fixtures.exists(path), Fixtures.missingMessage)
        let loaded = try ModelLoader.load(url: Fixtures.url(path))
        let r = loaded.report
        record(["model": "AnimatedMorphCube.glb", "morph": "\(r.hasMorphTargets)",
                "gltf_anims": "\(r.gltfAnimationCount)", "rk_anims": "\(r.availableAnimationCount)",
                "unsupported": r.unsupportedFeatures.joined(separator: ",")])
        #expect(r.hasMorphTargets)
        #expect(r.unsupportedFeatures.contains("morph targets"))
    }

    // MARK: KHR extensions (optional, gap documentation)

    @Test func transmissionIsParsedButNotConverted() throws {
        let path = "TransmissionTest/glTF-Binary/TransmissionTest.glb"
        try #require(Fixtures.exists(path), Fixtures.missingMessage)
        let loaded = try ModelLoader.load(url: Fixtures.url(path))
        record(["model": "TransmissionTest.glb", "ext": loaded.report.extensionsUsed.joined(separator: ","),
                "unsupported": loaded.report.unsupportedFeatures.joined(separator: ","),
                "warnings": "\(loaded.report.textureWarnings.count)"])
        #expect(loaded.report.extensionsUsed.contains("KHR_materials_transmission"))
        #expect(loaded.report.unsupportedFeatures.contains("KHR_materials_transmission"))
    }

    @Test func clearcoatIsConverted() throws {
        let path = "ClearCoatTest/glTF-Binary/ClearCoatTest.glb"
        try #require(Fixtures.exists(path), Fixtures.missingMessage)
        let loaded = try ModelLoader.load(url: Fixtures.url(path))
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

    @Test("Draco: GLTFKit2 ships no decoder; required-extension files are refused with a typed error",
          arguments: ["Box/glTF-Draco/Box.gltf", "Duck/glTF-Draco/Duck.gltf"])
    func dracoIsRefused(path: String) throws {
        try #require(Fixtures.exists(path), Fixtures.missingMessage)
        let url = Fixtures.url(path)
        // What GLTFKit2 itself does with the file, recorded for the spike results (spec §11.1).
        var rawOutcome = "parsed"
        do {
            let asset = try GLTFAsset(url: url, options: [:])
            rawOutcome = "parsed(required=\(asset.extensionsRequired.joined(separator: ",")))"
        } catch {
            rawOutcome = "threw(\((error as NSError).code))"
        }
        record(["model": path, "gltfkit2_raw": rawOutcome])
        #expect(throws: ModelLoadError.unsupportedRequiredExtensions(["KHR_draco_mesh_compression"])) {
            try ModelLoader.load(url: url)
        }
    }
}
