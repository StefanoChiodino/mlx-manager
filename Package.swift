// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MLXManager",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "MLXManager",
            path: "Sources/MLXManager"
        ),
        .testTarget(
            name: "MLXManagerTests",
            dependencies: ["MLXManager"],
            path: "Tests/MLXManagerTests"
        ),
    ]
)
