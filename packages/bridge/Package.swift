// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TanoBridge",
    platforms: [.iOS(.v15), .macOS(.v13)],
    products: [
        .library(name: "TanoBridge", targets: ["TanoBridge"]),
    ],
    dependencies: [
        .package(path: "../core"),
    ],
    targets: [
        .target(
            name: "TanoBridge",
            dependencies: [
                .product(name: "TanoCore", package: "core"),
            ],
            path: "Sources/TanoBridge"
        ),
        .testTarget(
            name: "TanoBridgeTests",
            dependencies: ["TanoBridge"],
            path: "Tests/TanoBridgeTests"
        ),
    ]
)
