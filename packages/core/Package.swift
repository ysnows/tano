// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TanoCore",
    platforms: [.iOS(.v15), .macOS(.v13)],
    products: [
        .library(name: "TanoCore", targets: ["TanoCore"]),
    ],
    targets: [
        .target(
            name: "TanoCore",
            path: "Sources/TanoCore"
        ),
        .testTarget(
            name: "TanoCoreTests",
            dependencies: ["TanoCore"],
            path: "Tests/TanoCoreTests"
        ),
    ]
)
