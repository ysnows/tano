// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TanoPluginHaptics",
    platforms: [.iOS(.v15), .macOS(.v13)],
    products: [
        .library(name: "TanoPluginHaptics", targets: ["TanoPluginHaptics"]),
    ],
    dependencies: [
        .package(path: "../../bridge"),
    ],
    targets: [
        .target(
            name: "TanoPluginHaptics",
            dependencies: [
                .product(name: "TanoBridge", package: "bridge"),
            ],
            path: "Sources/TanoPluginHaptics"
        ),
        .testTarget(
            name: "TanoPluginHapticsTests",
            dependencies: ["TanoPluginHaptics"],
            path: "Tests/TanoPluginHapticsTests"
        ),
    ]
)
