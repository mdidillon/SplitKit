import CoreGraphics
import Foundation
import ImageIO
import Metal
import RealityKit
import UniformTypeIdentifiers

/// Offscreen RealityKit render to PNG via `RealityRenderer`, used for the §10 PBR side-by-side evidence.
/// The framing comes from `OrbitCameraController`, so the render shows the framed default pose.
@MainActor
public enum OffscreenRenderer {
    public enum RenderError: Error {
        case noMetalDevice
        case textureCreationFailed
        case imageCreationFailed
        case writeFailed
    }

    public static func renderPNG(entity: Entity, to url: URL, size: Int = 768) async throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw RenderError.noMetalDevice }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb,
                                                                  width: size, height: size, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw RenderError.textureCreationFailed }

        let renderer = try RealityRenderer()
        let controller = OrbitCameraController(bounds: ModelLoader.measuredBounds(of: entity), aspectRatio: 1)
        let camera = Entity()
        camera.components.set(PerspectiveCameraComponent(
            near: max(controller.minDistance * 0.1, 0.0001),
            far: controller.maxDistance * 2,
            fieldOfViewInDegrees: controller.configuration.verticalFieldOfView * 180 / .pi))
        camera.transform = Transform(matrix: controller.transform)

        let light = Entity()
        light.components.set(DirectionalLightComponent(color: .white, intensity: 2000))
        light.look(at: .zero, from: SIMD3(1, 2, 2), relativeTo: nil)

        renderer.entities.append(contentsOf: [entity, camera, light])
        renderer.activeCamera = camera
        renderer.cameraSettings.colorBackground = .color(CGColor(gray: 0.82, alpha: 1))
        if let sky = studioEnvironmentImage() {
            renderer.lighting.resource = try? await EnvironmentResource(equirectangular: sky, withName: "SpikeBStudio")
            renderer.lighting.intensityExponent = 0
        }

        let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
        // A few updates let RealityKit finish uploading textures before the captured frame.
        for _ in 0..<3 {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                do {
                    try renderer.updateAndRender(deltaTime: 1 / 60, cameraOutput: output,
                                                 onComplete: { _ in continuation.resume() })
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        let bytesPerRow = size * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * size)
        texture.getBytes(&pixels, bytesPerRow: bytesPerRow, from: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0)
        try writePNG(bgra: pixels, width: size, height: size, to: url)
    }

    static func writePNG(bgra pixels: [UInt8], width: Int, height: Int, to url: URL) throws {
        let info = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGBitmapInfo(rawValue: info), provider: provider,
                                  decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { throw RenderError.imageCreationFailed }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw RenderError.writeFailed }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw RenderError.writeFailed }
    }

    /// Procedural equirectangular "studio" environment: bright sky fading to a grey floor.
    static func studioEnvironmentImage(width: Int = 512, height: Int = 256) -> CGImage? {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            let t = Float(y) / Float(height - 1) // 0 = zenith, 1 = nadir
            let value: Float = t < 0.5 ? 1.0 - 0.25 * t : 0.45 - 0.2 * (t - 0.5)
            for x in 0..<width {
                let i = (y * width + x) * 4
                pixels[i] = UInt8(min(255, value * 255))
                pixels[i + 1] = UInt8(min(255, value * 250))
                pixels[i + 2] = UInt8(min(255, value * 245))
                pixels[i + 3] = 255
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
