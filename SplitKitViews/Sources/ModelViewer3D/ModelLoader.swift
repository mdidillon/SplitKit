import Foundation
@preconcurrency import GLTFKit2
import RealityKit

/// Load diagnostics recorded for the spec §10 corpus criteria.
struct LoadReport: Sendable {
    /// Wall-clock time for the GLTFKit2 parse (off the main actor) and the RealityKit conversion (main actor).
    var parseDuration: Duration
    var convertDuration: Duration
    var totalDuration: Duration { parseDuration + convertDuration }
    var fileSize: Int
    /// Texture slots the glTF material declared but the converted RealityKit material lacks, plus images that can't
    /// be decoded. GLTFKit2 0.5.15 drops such textures silently, so this audit is how "missing-texture warnings"
    /// become observable.
    var textureWarnings: [String]
    var expectedTextureSlots: Int
    var convertedTextureSlots: Int
    var extensionsUsed: [String]
    var extensionsRequired: [String]
    /// Number of glTF animations vs. animations RealityKit exposes on the root entity.
    var gltfAnimationCount: Int
    var availableAnimationCount: Int
    var hasSkins: Bool
    var hasMorphTargets: Bool

    /// Extensions whose data the GLTFKit2 0.5.15 RealityKit converter actually maps (read from GLTFRealityKit.swift at
    /// tag 0.5.15). Anything else in `extensionsUsed` is parsed but not rendered.
    static let convertedExtensions: Set<String> = [
        "KHR_materials_clearcoat", "KHR_materials_emissive_strength", "KHR_materials_unlit",
        "KHR_lights_punctual", "KHR_texture_basisu",
    ]

    /// Features present in the file that the converter ignores; what the viewer reports as unsupported.
    var unsupportedFeatures: [String] {
        var result = extensionsUsed.filter { !Self.convertedExtensions.contains($0) }.sorted()
        if hasMorphTargets { result.append("morph targets") }
        return result
    }
}

extension Duration {
    var milliseconds: Double {
        Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15
    }
}

struct LoadedModel {
    var entity: Entity
    var report: LoadReport
    /// World-space visual bounds of the converted entity.
    var bounds: AxisAlignedBox
}

/// A parsed `GLTFAsset` handed from the background parse to the main-actor conversion. GLTFKit2 types aren't
/// `Sendable`; the asset is created on one executor and then only used by the one that receives it.
private struct ParsedAsset: @unchecked Sendable {
    let asset: GLTFAsset
    let duration: Duration
}

/// Loads a `.gltf`/`.glb` with `GLTFAsset(url:options:)` + `GLTFRealityKitLoader.convert(scene:asset:)` (spec §11.1):
/// preflight, the parse off the main actor, the conversion on it.
enum ModelLoader {
    @MainActor static func load(url: URL) async throws(ModelLoadError) -> LoadedModel {
        try await load(url: url, summary: GLTFPreflight.check(url: url))
    }

    /// For a caller that already ran `GLTFPreflight.check` (the content does, in `init`).
    @MainActor static func load(url: URL, summary: GLTFPreflight.Summary) async throws(ModelLoadError) -> LoadedModel {
        let parsed = try await parse(url: url)
        return try convert(parsed, summary: summary)
    }

    @concurrent private static func parse(url: URL) async throws(ModelLoadError) -> ParsedAsset {
        let clock = ContinuousClock()
        let start = clock.now
        do {
            let asset = try GLTFAsset(url: url, options: [:])
            return ParsedAsset(asset: asset, duration: clock.now - start)
        } catch {
            let ns = error as NSError
            throw .malformed(reason: "\(ns.localizedDescription) (\(ns.domain) \(ns.code))")
        }
    }

    @MainActor private static func convert(_ parsed: ParsedAsset, summary: GLTFPreflight.Summary) throws(ModelLoadError) -> LoadedModel {
        let asset = parsed.asset
        guard let scene = asset.defaultScene ?? asset.scenes.first else { throw .noDefaultScene }

        let clock = ContinuousClock()
        let start = clock.now
        let entity = GLTFRealityKitLoader.convert(scene: scene, asset: asset)
        let convertDuration = clock.now - start

        var audit = TextureAudit()
        audit.walk(nodes: scene.nodes, entities: Array(entity.children))
        audit.checkImages(asset.images)

        let report = LoadReport(
            parseDuration: parsed.duration,
            convertDuration: convertDuration,
            fileSize: summary.fileSize,
            textureWarnings: audit.warnings,
            expectedTextureSlots: audit.expected,
            convertedTextureSlots: audit.converted,
            extensionsUsed: asset.extensionsUsed,
            extensionsRequired: asset.extensionsRequired,
            gltfAnimationCount: asset.animations.count,
            availableAnimationCount: entity.availableAnimations.count,
            hasSkins: !asset.skins.isEmpty,
            hasMorphTargets: asset.meshes.contains { $0.primitives.contains { !$0.targets.isEmpty } }
        )
        return LoadedModel(entity: entity, report: report, bounds: measuredBounds(of: entity))
    }

    @MainActor static func measuredBounds(of entity: Entity) -> AxisAlignedBox {
        let b = entity.visualBounds(relativeTo: nil)
        return AxisAlignedBox(min: b.min, max: b.max)
    }
}

/// Walks the glTF node tree and the converted entity tree in parallel. GLTFKit2 0.5.15 creates one entity per node,
/// children in node order, one ModelComponent material per triangle primitive.
@MainActor
struct TextureAudit {
    var warnings: [String] = []
    var expected = 0
    var converted = 0

    mutating func walk(nodes: [GLTFNode], entities: [Entity]) {
        guard nodes.count == entities.count else {
            warnings.append("entity tree does not mirror node tree (\(nodes.count) nodes, \(entities.count) entities)")
            return
        }
        for (node, entity) in zip(nodes, entities) {
            if let mesh = node.mesh {
                let triangles = mesh.primitives.filter { $0.primitiveType == .triangles }
                let materials = entity.components[ModelComponent.self]?.materials ?? []
                for (index, primitive) in triangles.enumerated() {
                    let material = index < materials.count ? materials[index] : nil
                    check(primitive.material, against: material,
                          label: "\(node.name ?? "node")/\(mesh.name ?? "mesh")[\(index)]")
                }
            }
            walk(nodes: node.childNodes, entities: Array(entity.children))
        }
    }

    private mutating func slot(_ declared: GLTFTextureParams?, _ present: Bool, _ name: String, _ label: String) {
        guard declared != nil else { return }
        expected += 1
        if present { converted += 1 } else { warnings.append("\(label): \(name) texture missing after conversion") }
    }

    private mutating func check(_ gltf: GLTFMaterial?, against material: (any RealityKit.Material)?, label: String) {
        guard let gltf else { return }
        let mr = gltf.metallicRoughness
        if let pbr = material as? PhysicallyBasedMaterial {
            slot(mr?.baseColorTexture, pbr.baseColor.texture != nil, "baseColor", label)
            slot(mr?.metallicRoughnessTexture, pbr.roughness.texture != nil, "roughness (MR.g)", label)
            slot(mr?.metallicRoughnessTexture, pbr.metallic.texture != nil, "metallic (MR.b)", label)
            slot(gltf.normalTexture, pbr.normal.texture != nil, "normal", label)
            slot(gltf.occlusionTexture, pbr.ambientOcclusion.texture != nil, "occlusion", label)
            slot(gltf.emissive?.emissiveTexture, pbr.emissiveColor.texture != nil, "emissive", label)
        } else if let unlit = material as? UnlitMaterial {
            slot(mr?.baseColorTexture, unlit.color.texture != nil, "baseColor (unlit)", label)
        } else {
            for (params, name) in [(mr?.baseColorTexture, "baseColor"), (gltf.normalTexture, "normal")] {
                slot(params, false, name, label)
            }
        }
    }

    mutating func checkImages(_ images: [GLTFImage]) {
        for (index, image) in images.enumerated() where image.inferMediaType() != GLTFMediaTypeKTX2 {
            if image.newCGImage()?.takeRetainedValue() == nil {
                warnings.append("image[\(index)] \(image.uri?.lastPathComponent ?? image.name ?? "") could not be decoded")
            }
        }
    }
}
