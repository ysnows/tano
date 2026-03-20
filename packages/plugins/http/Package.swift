// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TanoPluginHTTP",
    platforms: [.iOS(.v15), .macOS(.v13)],
    products: [
        .library(name: "TanoPluginHTTP", targets: ["TanoPluginHTTP"]),
    ],
    dependencies: [
        .package(path: "../../bridge"),
    ],
    targets: [
        .target(
            name: "TanoPluginHTTP",
            dependencies: [
                .product(name: "TanoBridge", package: "bridge"),
            ],
            path: "Sources/TanoPluginHTTP"
        ),
        .testTarget(
            name: "TanoPluginHTTPTests",
            dependencies: ["TanoPluginHTTP"],
            path: "Tests/TanoPluginHTTPTests"
        ),
    ]
)
