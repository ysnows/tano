// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TanoPluginNotifications",
    platforms: [.iOS(.v15), .macOS(.v13)],
    products: [
        .library(name: "TanoPluginNotifications", targets: ["TanoPluginNotifications"]),
    ],
    dependencies: [
        .package(path: "../../bridge"),
    ],
    targets: [
        .target(
            name: "TanoPluginNotifications",
            dependencies: [
                .product(name: "TanoBridge", package: "bridge"),
            ],
            path: "Sources/TanoPluginNotifications"
        ),
        .testTarget(
            name: "TanoPluginNotificationsTests",
            dependencies: ["TanoPluginNotifications"],
            path: "Tests/TanoPluginNotificationsTests"
        ),
    ]
)
