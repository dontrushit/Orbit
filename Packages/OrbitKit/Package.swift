// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "OrbitKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "OrbitKit", targets: ["OrbitKit"]),
    ],
    targets: [
        .target(name: "OrbitKit"),
        .testTarget(name: "OrbitKitTests", dependencies: ["OrbitKit"]),
    ]
)
