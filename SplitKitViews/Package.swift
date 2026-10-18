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
        .package(url: "https://github.com/warrenm/GLTFKit2.git", exact: "0.5.15"),
    ],
    targets: [
        .target(name: "ImageViewer", dependencies: [.product(name: "SplitKitContent", package: "SplitKit")]),
        .target(name: "ModelViewer3D", dependencies: [
            .product(name: "SplitKitContent", package: "SplitKit"),
            .product(name: "GLTFKit2", package: "GLTFKit2"),
        ]),
        .testTarget(name: "ImageViewerTests", dependencies: ["ImageViewer"]),
        .testTarget(name: "ModelViewer3DTests", dependencies: [
            "ModelViewer3D",
            .product(name: "GLTFKit2", package: "GLTFKit2"),
        ]),
    ],
    swiftLanguageModes: [.v6]
)
