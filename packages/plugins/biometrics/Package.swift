// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TanoPluginBiometrics",
    platforms: [.iOS(.v15), .macOS(.v13)],
    products: [
        .library(name: "TanoPluginBiometrics", targets: ["TanoPluginBiometrics"]),
    ],
    dependencies: [
        .package(path: "../../bridge"),
    ],
    targets: [
        .target(
            name: "TanoPluginBiometrics",
            dependencies: [
                .product(name: "TanoBridge", package: "bridge"),
            ],
            path: "Sources/TanoPluginBiometrics"
        ),
        .testTarget(
            name: "TanoPluginBiometricsTests",
            dependencies: ["TanoPluginBiometrics"],
            path: "Tests/TanoPluginBiometricsTests"
        ),
    ]
)
