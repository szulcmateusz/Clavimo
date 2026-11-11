// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClavimoQuartz",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ClavimoQuartz", targets: ["ClavimoQuartz"]),
        .executable(name: "clavimo-probe", targets: ["ClavimoProbe"]),
    ],
    dependencies: [
        .package(path: "../ClavimoCore")
    ],
    targets: [
        .target(name: "ClavimoQuartz", dependencies: ["ClavimoCore"]),
        .executableTarget(name: "ClavimoProbe", dependencies: ["ClavimoQuartz", "ClavimoCore"]),
        .testTarget(name: "ClavimoQuartzTests", dependencies: ["ClavimoQuartz", "ClavimoCore"]),
    ]
)
