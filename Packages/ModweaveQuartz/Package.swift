// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ModweaveQuartz",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ModweaveQuartz", targets: ["ModweaveQuartz"]),
        .executable(name: "modweave-probe", targets: ["ModweaveProbe"]),
    ],
    dependencies: [
        .package(path: "../ModweaveCore")
    ],
    targets: [
        .target(name: "ModweaveQuartz", dependencies: ["ModweaveCore"]),
        .executableTarget(name: "ModweaveProbe", dependencies: ["ModweaveQuartz", "ModweaveCore"]),
        .testTarget(name: "ModweaveQuartzTests", dependencies: ["ModweaveQuartz", "ModweaveCore"]),
    ]
)
