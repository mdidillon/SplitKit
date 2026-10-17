import RealityKit
import SwiftUI

/// Live 3D content: a procedurally generated mesh in a RealityView. The rotation angle
/// lives in the object, so a re-hosted view continues from the same pose.
@MainActor @Observable public final class SpinnerContent: SpikeContent {
    public let id: ContentID
    /// Radians around +Y.
    public var angle: Double
    /// Radians per second while attached.
    public var speed: Double = 0.8
    public let autoRotate: Bool
    public let responderKind = ResponderKind.paneContainer
    @ObservationIgnored public private(set) var attachmentCount = 0
    @ObservationIgnored public private(set) var makeViewCalls = 0
    @ObservationIgnored private var ticker: Task<Void, Never>?

    public var title: String { "3D Spinner" }
    /// The rotation driver runs only while attached to a pane; a leaked driver is residue.
    public var isTicking: Bool { ticker != nil }

    public init(id: ContentID = ContentID(), angle: Double = 0, autoRotate: Bool = true) {
        self.id = id
        self.angle = angle
        self.autoRotate = autoRotate
    }

    public func makeView() -> AnyView {
        makeViewCalls += 1
        return AnyView(SpinnerView(model: self))
    }

    public func didAttach(to host: HostID) {
        attachmentCount += 1
        if attachmentCount > 1 { SpikeInvariant.failure("\(id) attached twice") }
        startTicker()
    }

    public func willDetach(from host: HostID) {
        attachmentCount -= 1
        if attachmentCount == 0 { stopTicker() }
    }

    private func startTicker() {
        guard autoRotate, ticker == nil else { return }
        ticker = Task { [weak self] in
            let clock = ContinuousClock()
            var last = clock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                guard let self else { return }
                let now = clock.now
                let elapsed = last.duration(to: now)
                last = now
                self.angle += self.speed * (Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18)
            }
        }
    }

    private func stopTicker() {
        ticker?.cancel()
        ticker = nil
    }
}

struct SpinnerView: View {
    let model: SpinnerContent

    var body: some View {
        let angle = model.angle
        ZStack(alignment: .bottomLeading) {
            RealityView { content in
                let root = Entity()
                root.name = "spinner"
                root.addChild(ModelEntity(
                    mesh: SpinnerMesh.make(),
                    materials: [SimpleMaterial(color: .systemOrange, roughness: 0.35, isMetallic: true)]
                ))
                content.add(root)

                let camera = PerspectiveCamera()
                camera.look(at: .zero, from: [0, 0.12, 0.55], relativeTo: nil)
                content.add(camera)

                let light = DirectionalLight()
                light.light.intensity = 4000
                light.look(at: .zero, from: [0.6, 1, 0.8], relativeTo: nil)
                content.add(light)
            } update: { content in
                content.entities.first { $0.name == "spinner" }?.transform.rotation =
                    simd_quatf(angle: Float(angle), axis: [0, 1, 0])
            }
            Text(String(format: "angle %.1f°", (angle * 180 / .pi).truncatingRemainder(dividingBy: 360)))
                .font(.caption.monospaced())
                .padding(6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A procedurally generated, deliberately asymmetric octahedron (flat-shaded) so rotation is visible.
@MainActor enum SpinnerMesh {
    static func make() -> MeshResource {
        let v: [SIMD3<Float>] = [
            [0.16, 0, 0], [-0.08, 0, 0], [0, 0.12, 0], [0, -0.12, 0], [0, 0, 0.1], [0, 0, -0.1],
        ]
        let faces: [(Int, Int, Int)] = [
            (0, 2, 4), (4, 2, 1), (1, 2, 5), (5, 2, 0),
            (4, 3, 0), (1, 3, 4), (5, 3, 1), (0, 3, 5),
        ]
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        for (a, b, c) in faces {
            let n = simd_normalize(simd_cross(v[b] - v[a], v[c] - v[a]))
            for i in [a, b, c] {
                indices.append(UInt32(positions.count))
                positions.append(v[i])
                normals.append(n)
            }
        }
        var descriptor = MeshDescriptor(name: "spinner")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        return (try? MeshResource.generate(from: [descriptor])) ?? .generateBox(size: 0.15)
    }
}
