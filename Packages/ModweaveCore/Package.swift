// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ModweaveCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ModweaveCore", targets: ["ModweaveCore"])
    ],
    targets: [
        .target(name: "ModweaveCore"),
        .testTarget(name: "ModweaveCoreTests", dependencies: ["ModweaveCore"]),
    ]
)
