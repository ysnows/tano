// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TanoPluginClipboard",
    platforms: [.iOS(.v15), .macOS(.v13)],
    products: [
        .library(name: "TanoPluginClipboard", targets: ["TanoPluginClipboard"]),
    ],
    dependencies: [
        .package(path: "../../bridge"),
    ],
    targets: [
        .target(
            name: "TanoPluginClipboard",
            dependencies: [
                .product(name: "TanoBridge", package: "bridge"),
            ],
            path: "Sources/TanoPluginClipboard"
        ),
        .testTarget(
            name: "TanoPluginClipboardTests",
            dependencies: ["TanoPluginClipboard"],
            path: "Tests/TanoPluginClipboardTests"
        ),
    ]
)
