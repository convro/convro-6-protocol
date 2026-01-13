// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ConvroApp",
    platforms: [
        .iOS(.v15)
    ],
    products: [],
    dependencies: [
        // C6P Protocol (local development)
        .package(path: "../../"), // Points to main Package.swift with C6PProtocol
    ],
    targets: []
)
