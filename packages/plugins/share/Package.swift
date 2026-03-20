// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TanoPluginShare",
    platforms: [.iOS(.v15), .macOS(.v13)],
    products: [
        .library(name: "TanoPluginShare", targets: ["TanoPluginShare"]),
    ],
    dependencies: [
        .package(path: "../../bridge"),
    ],
    targets: [
        .target(
            name: "TanoPluginShare",
            dependencies: [
                .product(name: "TanoBridge", package: "bridge"),
            ],
            path: "Sources/TanoPluginShare"
        ),
        .testTarget(
            name: "TanoPluginShareTests",
            dependencies: ["TanoPluginShare"],
            path: "Tests/TanoPluginShareTests"
        ),
    ]
)
