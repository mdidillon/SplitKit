// swift-tools-version: 6.2
import PackageDescription

// Phase 1 Spike A (spec §11, §14 risk 1): cross-window live-content transfer.
// Standalone: does not depend on the SplitKit or SplitKitViews packages.
let package = Package(
    name: "SpikeA",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SpikeACore", targets: ["SpikeACore"]),
        .executable(name: "SpikeADemo", targets: ["SpikeADemo"]),
    ],
    targets: [
        .target(
            name: "SpikeACore",
            swiftSettings: [.define("DEBUG", .when(configuration: .debug))]
        ),
        .executableTarget(name: "SpikeADemo", dependencies: ["SpikeACore"]),
        .testTarget(name: "SpikeACoreTests", dependencies: ["SpikeACore"]),
    ],
    swiftLanguageModes: [.v6]
)
