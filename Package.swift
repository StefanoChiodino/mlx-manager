// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MLXManager",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
    ],
    targets: [
        .target(
            name: "MLXManager",
            dependencies: ["Yams"],
            path: "Sources/MLXManager"
        ),
        .executableTarget(
            name: "MLXManagerApp",
            dependencies: ["MLXManager"],
            path: "Sources/MLXManagerApp",
            resources: [
                .copy("presets.yaml"),
            ]
        ),
        .testTarget(
            name: "MLXManagerTests",
            dependencies: ["MLXManager"],
            path: "Tests/MLXManagerTests"
        ),
    ]
)
