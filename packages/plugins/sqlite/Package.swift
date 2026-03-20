// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TanoPluginSQLite",
    platforms: [.iOS(.v15), .macOS(.v13)],
    products: [
        .library(name: "TanoPluginSQLite", targets: ["TanoPluginSQLite"]),
    ],
    dependencies: [
        .package(path: "../../bridge"),
    ],
    targets: [
        .target(
            name: "TanoPluginSQLite",
            dependencies: [
                .product(name: "TanoBridge", package: "bridge"),
            ],
            path: "Sources/TanoPluginSQLite",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "TanoPluginSQLiteTests",
            dependencies: ["TanoPluginSQLite"],
            path: "Tests/TanoPluginSQLiteTests"
        ),
    ]
)
