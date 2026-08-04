// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "PinaxNativeHost",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "PinaxNativeMessaging",
            targets: ["PinaxNativeMessaging"]
        ),
        .executable(
            name: "PinaxNativeHost",
            targets: ["PinaxNativeHost"]
        )
    ],
    targets: [
        .target(name: "PinaxNativeMessaging"),
        .executableTarget(
            name: "PinaxNativeHost",
            dependencies: ["PinaxNativeMessaging"]
        ),
        .testTarget(
            name: "PinaxNativeMessagingTests",
            dependencies: ["PinaxNativeMessaging"]
        )
    ]
)
