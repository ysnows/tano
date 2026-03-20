// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TanoPluginCrypto",
    platforms: [.iOS(.v15), .macOS(.v13)],
    products: [
        .library(name: "TanoPluginCrypto", targets: ["TanoPluginCrypto"]),
    ],
    dependencies: [
        .package(path: "../../bridge"),
    ],
    targets: [
        .target(
            name: "TanoPluginCrypto",
            dependencies: [
                .product(name: "TanoBridge", package: "bridge"),
            ],
            path: "Sources/TanoPluginCrypto"
        ),
        .testTarget(
            name: "TanoPluginCryptoTests",
            dependencies: ["TanoPluginCrypto"],
            path: "Tests/TanoPluginCryptoTests"
        ),
    ]
)
