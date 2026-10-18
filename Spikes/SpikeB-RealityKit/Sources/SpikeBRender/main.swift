// Renders the PBR corpus offscreen for the §10 side-by-side evidence.
// Usage (from Spikes/SpikeB-RealityKit): swift run SpikeBRender [Fixtures dir] [output dir]
// (the fixtures live in SplitKitViews/Tests/Fixtures/Models since P4b)
import Foundation
import SpikeBCore

let arguments = CommandLine.arguments
let fixtures = URL(fileURLWithPath: arguments.count > 1 ? arguments[1] : "../../SplitKitViews/Tests/Fixtures/Models")
let output = URL(fileURLWithPath: arguments.count > 2 ? arguments[2] : ".build/renders")
try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

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
