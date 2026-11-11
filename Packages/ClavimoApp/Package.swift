// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClavimoApp",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Clavimo", targets: ["ClavimoApp"])
    ],
    dependencies: [
        .package(path: "../ClavimoCore"),
        .package(path: "../ClavimoQuartz"),
    ],
    targets: [
        .executableTarget(
            name: "ClavimoApp",
            dependencies: [
                .product(name: "ClavimoCore", package: "ClavimoCore"),
                .product(name: "ClavimoQuartz", package: "ClavimoQuartz"),
            ]
        ),
        .testTarget(name: "ClavimoAppTests", dependencies: ["ClavimoApp"]),
    ]
)
