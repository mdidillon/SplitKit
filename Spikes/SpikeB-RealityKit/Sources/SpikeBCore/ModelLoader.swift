import Foundation
@preconcurrency import GLTFKit2
import RealityKit

/// Typed load error (the ModelViewer3D product will map this to `ContentError`, spec §12).
public enum ModelLoadError: Error, Equatable, CustomStringConvertible {
    /// The extension is not glTF/GLB (e.g. `.fbx`, which §10 rules out). Checked before parsing.
    case unsupportedFormat(fileExtension: String)
    case fileNotFound
    /// GLTFKit2 refused the file. `code` is a `GLTFErrorCode` (1001...1012) or another NSError code.
    case malformed(code: Int, message: String)
    /// The file uses an extension listed in `extensionsRequired` that the converter cannot honour.
    case unsupportedRequiredExtensions([String])
    case noDefaultScene

    public var description: String {
        switch self {
        case .unsupportedFormat(let ext): "Unsupported file type “.\(ext)”. Only glTF (.gltf) and GLB (.glb) can be opened."
        case .fileNotFound: "The file could not be found."
        case .malformed(let code, let message): "The file is not a valid glTF asset (\(code)): \(message)"
        case .unsupportedRequiredExtensions(let names): "The file requires unsupported glTF extensions: \(names.joined(separator: ", "))."
        case .noDefaultScene: "The glTF asset contains no scene to display."
        }
    }
}

/// Load diagnostics recorded for the §10 corpus criteria.
public struct LoadReport: Sendable {
    /// Wall-clock time for GLTFKit2 parse + RealityKit conversion.
    public var parseDuration: Duration
    public var convertDuration: Duration
    public var totalDuration: Duration { parseDuration + convertDuration }
    public var fileSize: Int
    /// Texture slots the glTF material declared but the converted RealityKit material lacks, plus images
    /// that cannot be decoded. GLTFKit2 0.5.15 drops such textures silently, so this audit is how
    /// "missing-texture warnings" become observable.
    public var textureWarnings: [String]
    public var expectedTextureSlots: Int
    public var convertedTextureSlots: Int
    public var extensionsUsed: [String]
    public var extensionsRequired: [String]
    /// Number of glTF animations vs. animations RealityKit exposes on the root entity.
    public var gltfAnimationCount: Int
    public var availableAnimationCount: Int
    public var hasSkins: Bool
    public var hasMorphTargets: Bool

    /// Extensions whose data the GLTFKit2 0.5.15 RealityKit converter actually maps (read from
    /// GLTFRealityKit.swift at tag 0.5.15). Anything else in `extensionsUsed` is parsed but not rendered.
    public static let convertedExtensions: Set<String> = [
        "KHR_materials_clearcoat", "KHR_materials_emissive_strength", "KHR_materials_unlit",
        "KHR_lights_punctual", "KHR_texture_basisu",
    ]

    /// Features present in the file that the converter ignores; what a viewer reports as "unsupported".
    public var unsupportedFeatures: [String] {
        var result = extensionsUsed.filter { !Self.convertedExtensions.contains($0) }.sorted()
        if hasMorphTargets { result.append("morph targets") }
        return result
    }
}

extension Duration {
    public var milliseconds: Double {
        Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15
    }
}

@MainActor
public struct LoadedModel {
    public var entity: Entity
    public var report: LoadReport
    /// World-space visual bounds of the converted entity.
    public var bounds: AxisAlignedBox
}

@MainActor
public enum ModelLoader {
    public static let supportedExtensions: Set<String> = ["gltf", "glb"]

    /// Draco needs a decoder class registered through `GLTFAsset.dracoDecompressorClassName`; none ships
    /// with GLTFKit2 0.5.15, so a file that *requires* it cannot be shown.
    public static let unsupportedRequiredExtensions: Set<String> = ["KHR_draco_mesh_compression"]

    /// Loads a .gltf/.glb with `GLTFAsset(url:options:)` + `GLTFRealityKitLoader.convert(scene:asset:)`.
    public static func load(url: URL) throws(ModelLoadError) -> LoadedModel {
        let ext = url.pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else { throw .unsupportedFormat(fileExtension: ext) }
        guard FileManager.default.fileExists(atPath: url.path) else { throw .fileNotFound }
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0

        let clock = ContinuousClock()
        let parseStart = clock.now
        let asset: GLTFAsset
        do {
            asset = try GLTFAsset(url: url, options: [:])
        } catch {
            let ns = error as NSError
            switch (ns.domain, ns.code) {
            case (GLTFErrorDomain, 1006): throw .fileNotFound
            case (GLTFErrorDomain, 1012): // GLTFErrorCodeUnsupportedExtension, e.g. Draco without a decoder
                throw .unsupportedRequiredExtensions(ReferenceGeometry.requiredExtensions(url: url))
            default: throw .malformed(code: ns.code, message: ns.localizedDescription)
            }
        }
        let parseDuration = clock.now - parseStart

        let blocked = asset.extensionsRequired.filter(unsupportedRequiredExtensions.contains)
        guard blocked.isEmpty else { throw .unsupportedRequiredExtensions(blocked) }
        guard let scene = asset.defaultScene ?? asset.scenes.first else { throw .noDefaultScene }

        let convertStart = clock.now
        let entity = GLTFRealityKitLoader.convert(scene: scene, asset: asset)
        let convertDuration = clock.now - convertStart

        var audit = TextureAudit()
        audit.walk(nodes: scene.nodes, entities: Array(entity.children))
        audit.checkImages(asset.images)

        let hasSkins = !asset.skins.isEmpty
        let hasMorphTargets = asset.meshes.contains { $0.primitives.contains { !$0.targets.isEmpty } }
        let report = LoadReport(
            parseDuration: parseDuration,
            convertDuration: convertDuration,
            fileSize: fileSize,
            textureWarnings: audit.warnings,
            expectedTextureSlots: audit.expected,
            convertedTextureSlots: audit.converted,
            extensionsUsed: asset.extensionsUsed,
            extensionsRequired: asset.extensionsRequired,
            gltfAnimationCount: asset.animations.count,
            availableAnimationCount: entity.availableAnimations.count,
            hasSkins: hasSkins,
            hasMorphTargets: hasMorphTargets
        )
        return LoadedModel(entity: entity, report: report, bounds: measuredBounds(of: entity))
    }

    public static func measuredBounds(of entity: Entity) -> AxisAlignedBox {
        let b = entity.visualBounds(relativeTo: nil)
        return AxisAlignedBox(min: b.min, max: b.max)
    }
}

/// Walks the glTF node tree and the converted entity tree in parallel. GLTFKit2 0.5.15 creates one
/// entity per node, children in node order, one ModelComponent material per triangle primitive.
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
