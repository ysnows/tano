// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TanoWebView",
    platforms: [.iOS(.v15), .macOS(.v13)],
    products: [
        .library(name: "TanoWebView", targets: ["TanoWebView"]),
    ],
    dependencies: [
        .package(path: "../core"),
        .package(path: "../bridge"),
    ],
    targets: [
        .target(
            name: "TanoWebView",
            dependencies: [
                .product(name: "TanoCore", package: "core"),
                .product(name: "TanoBridge", package: "bridge"),
            ],
            path: "Sources/TanoWebView"
        ),
        .testTarget(
            name: "TanoWebViewTests",
            dependencies: ["TanoWebView"],
            path: "Tests/TanoWebViewTests"
        ),
    ]
)
