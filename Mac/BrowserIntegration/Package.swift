// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "BrowserIntegration",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "BrowserIntegration",
            targets: ["BrowserIntegration"]
        )
    ],
    targets: [
        .target(name: "BrowserIntegration"),
        .testTarget(
            name: "BrowserIntegrationTests",
            dependencies: ["BrowserIntegration"]
        )
    ]
)
