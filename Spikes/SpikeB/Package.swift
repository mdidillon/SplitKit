// swift-tools-version: 6.2
import PackageDescription

// Phase 1 Spike B (spec §10, §11 Gate B): standalone GLTFKit2 -> RealityKit evaluation.
// Deliberately independent of SplitKit and SplitKitViews.
let package = Package(
    name: "SpikeB",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SpikeBCore", targets: ["SpikeBCore"]),
        .executable(name: "SpikeBDemo", targets: ["SpikeBDemo"]),
        .executable(name: "SpikeBRender", targets: ["SpikeBRender"]),
    ],
    dependencies: [
        .package(url: "https://github.com/warrenm/GLTFKit2.git", exact: "0.5.15"),
    ],
    targets: [
        .target(
            name: "SpikeBCore",
            dependencies: [.product(name: "GLTFKit2", package: "GLTFKit2")]
        ),
        .executableTarget(name: "SpikeBDemo", dependencies: ["SpikeBCore"]),
        .executableTarget(name: "SpikeBRender", dependencies: ["SpikeBCore"]),
        .testTarget(
            name: "SpikeBCoreTests",
            dependencies: ["SpikeBCore", .product(name: "GLTFKit2", package: "GLTFKit2")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
