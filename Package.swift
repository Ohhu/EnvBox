// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "EnvBox",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "EnvBox", targets: ["EnvBox"]),
        .executable(name: "envbox-helper", targets: ["EnvBoxHelper"]),
        .library(name: "EnvBoxCore", targets: ["EnvBoxCore"])
    ],
    targets: [
        .target(
            name: "EnvBoxCore",
            path: "Sources/EnvBoxCore"
        ),
        .target(
            name: "EnvBoxUI",
            dependencies: ["EnvBoxCore"],
            path: "Sources/EnvBoxUI"
        ),
        .executableTarget(
            name: "EnvBox",
            dependencies: ["EnvBoxUI", "EnvBoxCore"],
            path: "Sources/EnvBox"
        ),
        .executableTarget(
            name: "EnvBoxHelper",
            dependencies: ["EnvBoxCore"],
            path: "Sources/EnvBoxHelper"
        ),
        .testTarget(
            name: "EnvBoxCoreTests",
            dependencies: ["EnvBoxCore"],
            path: "Tests/EnvBoxCoreTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
