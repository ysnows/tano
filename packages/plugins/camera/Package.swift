// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TanoPluginCamera",
    platforms: [.iOS(.v15), .macOS(.v13)],
    products: [
        .library(name: "TanoPluginCamera", targets: ["TanoPluginCamera"]),
    ],
    dependencies: [
        .package(path: "../../bridge"),
    ],
    targets: [
        .target(
            name: "TanoPluginCamera",
            dependencies: [
                .product(name: "TanoBridge", package: "bridge"),
            ],
            path: "Sources/TanoPluginCamera"
        ),
        .testTarget(
            name: "TanoPluginCameraTests",
            dependencies: ["TanoPluginCamera"],
            path: "Tests/TanoPluginCameraTests"
        ),
    ]
)
