// swift-tools-version: 6.0
import PackageDescription

// S0 skeleton. S1 does not own this file except to uncomment nothing here.
// S2 fills FrameKit sources. S3 fills InputKit. S4 adds EngineKit usage of the dylib.
let package = Package(
    name: "mrdpd",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FrameKit", targets: ["FrameKit"]),
        .library(name: "InputKit", targets: ["InputKit"]),
        .library(name: "EngineKit", targets: ["EngineKit"]),
    ],
    targets: [
        .target(name: "FrameKit"),
        .target(name: "InputKit"),
        .target(name: "EngineKit", dependencies: ["FrameKit", "InputKit"]),
        .testTarget(name: "FrameKitTests", dependencies: ["FrameKit"]),
        .testTarget(name: "InputKitTests", dependencies: ["InputKit"]),
        .testTarget(name: "EngineKitTests", dependencies: ["EngineKit"]),
    ]
)
