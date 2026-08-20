// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "mrdpd",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FrameKit", targets: ["FrameKit"]),
        .library(name: "InputKit", targets: ["InputKit"]),
        .library(name: "EngineKit", targets: ["EngineKit"]),
    ],
    targets: [
        .target(
            name: "CEngine",
            path: "include",
            publicHeadersPath: "."
        ),
        .target(name: "FrameKit"),
        .target(name: "InputKit"),
        .target(name: "EngineKit", dependencies: ["CEngine", "FrameKit", "InputKit"]),
        .testTarget(name: "FrameKitTests", dependencies: ["FrameKit"]),
        .testTarget(name: "InputKitTests", dependencies: ["InputKit"]),
        .testTarget(name: "EngineKitTests", dependencies: ["EngineKit", "FrameKit", "InputKit"]),
    ]
)
