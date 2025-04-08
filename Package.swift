// swift-tools-version:5.10

import PackageDescription

let package = Package(
    name: "Pulse",
    platforms: [
        .iOS(.v14),
        .tvOS(.v15),
        .macOS(.v14),
        .watchOS(.v8)
    ],
    products: [
        .library(name: "Pulse", targets: ["Pulse"]),
        .library(name: "PulseUI", targets: ["PulseUI"])
    ],
    targets: [
        .target(name: "Pulse"),
        .target(name: "PulseUI", dependencies: ["Pulse"]),
        .testTarget(name: "PulseTests", dependencies: ["Pulse"]),
        .testTarget(name: "PulseUITests", dependencies: ["PulseUI"])
    ]
)
