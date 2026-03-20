// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TanoPluginKeychain",
    platforms: [.iOS(.v15), .macOS(.v13)],
    products: [
        .library(name: "TanoPluginKeychain", targets: ["TanoPluginKeychain"]),
    ],
    dependencies: [
        .package(path: "../../bridge"),
    ],
    targets: [
        .target(
            name: "TanoPluginKeychain",
            dependencies: [
                .product(name: "TanoBridge", package: "bridge"),
            ],
            path: "Sources/TanoPluginKeychain"
        ),
        .testTarget(
            name: "TanoPluginKeychainTests",
            dependencies: ["TanoPluginKeychain"],
            path: "Tests/TanoPluginKeychainTests"
        ),
    ]
)
