// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ModweaveApp",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Modweave", targets: ["ModweaveApp"])
    ],
    dependencies: [
        .package(path: "../ModweaveCore"),
        .package(path: "../ModweaveQuartz"),
    ],
    targets: [
        .executableTarget(
            name: "ModweaveApp",
            dependencies: [
                .product(name: "ModweaveCore", package: "ModweaveCore"),
                .product(name: "ModweaveQuartz", package: "ModweaveQuartz"),
            ]
        ),
        .testTarget(name: "ModweaveAppTests", dependencies: ["ModweaveApp"]),
    ]
)
