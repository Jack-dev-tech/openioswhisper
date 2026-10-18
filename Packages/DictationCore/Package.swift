// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "DictationCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DictationCore", targets: ["DictationCore"]),
    ],
    targets: [
        .target(name: "DictationCore"),
        .testTarget(name: "DictationCoreTests", dependencies: ["DictationCore"]),
    ]
)
