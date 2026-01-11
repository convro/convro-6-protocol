// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "C6PProtocol",

    platforms: [
        .iOS(.v13),
        .macOS(.v11)
    ],

    products: [
        // Main product - Swift wrapper + binary framework
        .library(
            name: "C6PProtocol",
            targets: ["C6PProtocol"]
        ),
    ],

    targets: [
        // Binary XCFramework target
        // This will be updated with remote URL and checksum for releases
        .binaryTarget(
            name: "C6PProtocolFFI",
            // For local development, use path:
            path: "build/xcframework/C6PProtocol.xcframework"

            // For releases, this will be replaced with:
            // url: "https://github.com/convro/convro-6-protocol/releases/download/v0.1.0/C6PProtocol-0.1.0.xcframework.zip",
            // checksum: "CHECKSUM_WILL_BE_GENERATED_BY_BUILD_SCRIPT"
        ),

        // Swift wrapper target (optional - provides high-level API)
        // Uncomment when Sources/C6PProtocol directory is created
        /*
        .target(
            name: "C6PProtocol",
            dependencies: ["C6PProtocolFFI"],
            path: "Sources/C6PProtocol"
        ),
        */

        // For now, just expose the binary directly
        .target(
            name: "C6PProtocol",
            dependencies: ["C6PProtocolFFI"],
            path: "Sources/C6PProtocol",
            sources: ["Placeholder.swift"]
        ),

        // Tests target
        .testTarget(
            name: "C6PProtocolTests",
            dependencies: ["C6PProtocol"],
            path: "Tests/C6PProtocolTests"
        ),
    ]
)
