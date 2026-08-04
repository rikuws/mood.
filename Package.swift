// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PinaxCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "PinaxCore", targets: ["PinaxCore"]),
        .library(name: "PinaxCloudSync", targets: ["PinaxCloudSync"]),
        .executable(name: "pinax-agent", targets: ["PinaxAgent"]),
    ],
    targets: [
        .target(
            name: "PinaxCore",
            path: "Shared"
        ),
        .target(
            name: "PinaxCloudSync",
            dependencies: ["PinaxCore"],
            path: "Sync/Sources"
        ),
        .executableTarget(
            name: "PinaxAgent",
            dependencies: ["PinaxCore"],
            path: "AgentAPI/Sources/PinaxAgent"
        ),
        .testTarget(
            name: "PinaxCoreTests",
            dependencies: ["PinaxCore"],
            path: "Tests/PinaxCoreTests"
        ),
        .testTarget(
            name: "PinaxCloudSyncTests",
            dependencies: ["PinaxCloudSync", "PinaxCore"],
            path: "Sync/Tests"
        ),
    ]
)
