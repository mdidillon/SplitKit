// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SplitKitViews",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ImageViewer", targets: ["ImageViewer"]),
        .library(name: "ModelViewer3D", targets: ["ModelViewer3D"]),
    ],
    dependencies: [
        .package(path: "../SplitKit"),
        // TODO: add GLTFKit2 (MIT) for ModelViewer3D once a version pin is decided (not in spec yet).
    ],
    targets: [
        .target(name: "ImageViewer", dependencies: [.product(name: "SplitKitContent", package: "SplitKit")]),
        .target(name: "ModelViewer3D", dependencies: [.product(name: "SplitKitContent", package: "SplitKit")]),
        .testTarget(name: "ImageViewerTests", dependencies: ["ImageViewer"]),
        .testTarget(name: "ModelViewer3DTests", dependencies: ["ModelViewer3D"]),
    ],
    swiftLanguageModes: [.v6]
)
