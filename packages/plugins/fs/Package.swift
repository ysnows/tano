// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TanoPluginFS",
    platforms: [.iOS(.v15), .macOS(.v13)],
    products: [
        .library(name: "TanoPluginFS", targets: ["TanoPluginFS"]),
    ],
    dependencies: [
        .package(path: "../../bridge"),
    ],
    targets: [
        .target(
            name: "TanoPluginFS",
            dependencies: [
                .product(name: "TanoBridge", package: "bridge"),
            ],
            path: "Sources/TanoPluginFS"
        ),
        .testTarget(
            name: "TanoPluginFSTests",
            dependencies: ["TanoPluginFS"],
            path: "Tests/TanoPluginFSTests"
        ),
    ]
)
