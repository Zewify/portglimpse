// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PortGlimpseCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PortGlimpseCore", targets: ["PortGlimpseCore"]),
    ],
    targets: [
        // Every rule the app follows: scanning, inspecting, labelling, classifying,
        // overrides, the kill flow and version comparison. Foundation and Darwin only.
        .target(name: "PortGlimpseCore"),
        .testTarget(name: "PortGlimpseCoreTests", dependencies: ["PortGlimpseCore"]),
    ]
)
