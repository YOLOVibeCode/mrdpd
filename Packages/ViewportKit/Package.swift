// swift-tools-version: 6.0
import PackageDescription

// Native viewport protocol shared by the Mac host (`HostKit`, root package) and the iPad app
// (`apps/ipad`). ADR 0008. Pure Swift + Apple frameworks; no third-party dependencies.
let package = Package(
    name: "ViewportKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "ViewportProtocol", targets: ["ViewportProtocol"]),
        .library(name: "ViewportTransport", targets: ["ViewportTransport"]),
        .library(name: "ViewportClient", targets: ["ViewportClient"]),
    ],
    targets: [
        .target(name: "ViewportProtocol"),
        .target(name: "ViewportTransport", dependencies: ["ViewportProtocol"]),
        .target(name: "ViewportClient", dependencies: ["ViewportProtocol", "ViewportTransport"]),
        .testTarget(name: "ViewportProtocolTests", dependencies: ["ViewportProtocol"]),
        .testTarget(name: "ViewportTransportTests", dependencies: ["ViewportTransport"]),
        .testTarget(name: "ViewportClientTests", dependencies: ["ViewportClient"]),
    ]
)
