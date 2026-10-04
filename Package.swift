// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "mrdpd",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FrameKit", targets: ["FrameKit"]),
        .library(name: "InputKit", targets: ["InputKit"]),
        .library(name: "EngineKit", targets: ["EngineKit"]),
        .executable(name: "mrdpd-serve", targets: ["mrdpd-serve"]),
        .executable(name: "mrdpd-host", targets: ["mrdpd-host"]),
    ],
    dependencies: [
        .package(path: "Packages/ViewportKit"),
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
        .executableTarget(
            name: "mrdpd-serve",
            dependencies: ["EngineKit", "FrameKit", "InputKit"]
        ),
        // Lab oracle for `just live-check`; not shipped.
        .executableTarget(name: "mrdpd-probe"),
        // Native viewport host (ADR 0008): the iPad app connects here.
        .target(
            name: "HostKit",
            dependencies: [
                "InputKit",
                .product(name: "ViewportProtocol", package: "ViewportKit"),
                .product(name: "ViewportTransport", package: "ViewportKit"),
            ]
        ),
        .executableTarget(name: "mrdpd-host", dependencies: ["HostKit"]),
        .testTarget(name: "FrameKitTests", dependencies: ["FrameKit"]),
        .testTarget(name: "InputKitTests", dependencies: ["InputKit"]),
        .testTarget(name: "EngineKitTests", dependencies: ["EngineKit", "FrameKit", "InputKit"]),
        .testTarget(
            name: "HostKitTests",
            dependencies: [
                "HostKit",
                .product(name: "ViewportClient", package: "ViewportKit"),
            ]
        ),
    ]
)
