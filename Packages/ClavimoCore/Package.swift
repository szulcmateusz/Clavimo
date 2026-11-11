// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClavimoCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ClavimoCore", targets: ["ClavimoCore"])
    ],
    targets: [
        .target(name: "ClavimoCore"),
        .testTarget(name: "ClavimoCoreTests", dependencies: ["ClavimoCore"]),
    ]
)
