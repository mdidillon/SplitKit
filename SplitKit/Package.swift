// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SplitKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SplitKitModel", targets: ["SplitKitModel"]),
        .library(name: "SplitKitContent", targets: ["SplitKitContent"]),
        .library(name: "SplitKit", targets: ["SplitKit"]),
    ],
    targets: [
        .target(name: "SplitKitModel"),
        .target(name: "SplitKitContent", dependencies: ["SplitKitModel"]),
        .target(name: "SplitKitWindows", dependencies: ["SplitKitModel"]),
        .target(name: "SplitKit", dependencies: ["SplitKitContent", "SplitKitWindows", "SplitKitModel"]),
        .testTarget(name: "SplitKitModelTests", dependencies: ["SplitKitModel"], exclude: ["Fixtures"]),
        .testTarget(name: "SplitKitContentTests", dependencies: ["SplitKitContent"]),
        .testTarget(name: "SplitKitWindowsTests", dependencies: ["SplitKitWindows"]),
        .testTarget(name: "SplitKitTests", dependencies: ["SplitKit"]),
    ],
    swiftLanguageModes: [.v6]
)
