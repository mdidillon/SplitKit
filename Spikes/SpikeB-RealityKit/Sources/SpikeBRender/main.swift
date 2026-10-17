// Renders the PBR corpus offscreen for the §10 side-by-side evidence.
// Usage (from Spikes/SpikeB-RealityKit): swift run SpikeBRender [Fixtures dir] [output dir]
import Foundation
import SpikeBCore

let arguments = CommandLine.arguments
let fixtures = URL(fileURLWithPath: arguments.count > 1 ? arguments[1] : "Fixtures")
let output = URL(fileURLWithPath: arguments.count > 2 ? arguments[2] : "../../Docs/ADR/assets/spikeB/renders")

let models = [
    "DamagedHelmet/glTF-Binary/DamagedHelmet.glb",
    "Duck/glTF-Binary/Duck.glb",
    "BoxTextured/glTF/BoxTextured.gltf",
    "CesiumMilkTruck/glTF/CesiumMilkTruck.gltf",
]

var failures = 0
for path in models {
    let url = fixtures.appendingPathComponent(path)
    let name = url.deletingPathExtension().lastPathComponent
    do {
        let loaded = try ModelLoader.load(url: url)
        let destination = output.appendingPathComponent("\(name)-realitykit.png")
        try await OffscreenRenderer.renderPNG(entity: loaded.entity, to: destination)
        print("rendered \(name) -> \(destination.path)")
    } catch {
        failures += 1
        print("FAILED \(name): \(error)")
    }
}
exit(failures == 0 ? 0 : 1)
