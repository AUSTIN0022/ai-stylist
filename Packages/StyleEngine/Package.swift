// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StyleEngine",
    platforms: [.iOS("27.0"), .macOS("27.0")],
    products: [
        .library(name: "StyleEngine", targets: ["StyleEngine"]),
        .library(name: "WardrobeImaging", targets: ["WardrobeImaging"]),
    ],
    targets: [
        .target(name: "StyleEngine", resources: [.process("Resources")]),
        .target(name: "WardrobeImaging", dependencies: ["StyleEngine"]),
        .testTarget(name: "StyleEngineTests", dependencies: ["StyleEngine"], resources: [.copy("Fixtures")]),
        .testTarget(name: "WardrobeImagingTests", dependencies: ["WardrobeImaging", "StyleEngine"]),
    ]
)
