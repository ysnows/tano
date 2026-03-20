// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Tano",
    platforms: [.iOS(.v15), .macOS(.v13)],
    products: [
        .library(name: "TanoCore", targets: ["TanoCore"]),
        .library(name: "TanoBridge", targets: ["TanoBridge"]),
        .library(name: "TanoWebView", targets: ["TanoWebView"]),
        .library(name: "TanoPluginSQLite", targets: ["TanoPluginSQLite"]),
        .library(name: "TanoPluginClipboard", targets: ["TanoPluginClipboard"]),
        .library(name: "TanoPluginHaptics", targets: ["TanoPluginHaptics"]),
        .library(name: "TanoPluginKeychain", targets: ["TanoPluginKeychain"]),
        .library(name: "TanoPluginFS", targets: ["TanoPluginFS"]),
        .library(name: "TanoPluginCrypto", targets: ["TanoPluginCrypto"]),
        .library(name: "TanoPluginBiometrics", targets: ["TanoPluginBiometrics"]),
        .library(name: "TanoPluginShare", targets: ["TanoPluginShare"]),
        .library(name: "TanoPluginNotifications", targets: ["TanoPluginNotifications"]),
        .library(name: "TanoPluginHTTP", targets: ["TanoPluginHTTP"]),
        .library(name: "TanoPluginCamera", targets: ["TanoPluginCamera"]),
        // Convenience: all-in-one
        .library(name: "Tano", targets: ["Tano"]),
    ],
    targets: [
        // Core
        .target(name: "TanoCore", path: "packages/core/Sources/TanoCore"),

        // Bridge (depends on Core)
        .target(name: "TanoBridge", dependencies: ["TanoCore"], path: "packages/bridge/Sources/TanoBridge"),

        // WebView (depends on Core + Bridge)
        .target(name: "TanoWebView", dependencies: ["TanoCore", "TanoBridge"], path: "packages/webview/Sources/TanoWebView"),

        // Plugins (each depends on Bridge)
        .target(name: "TanoPluginSQLite", dependencies: ["TanoBridge"], path: "packages/plugins/sqlite/Sources/TanoPluginSQLite", linkerSettings: [.linkedLibrary("sqlite3")]),
        .target(name: "TanoPluginClipboard", dependencies: ["TanoBridge"], path: "packages/plugins/clipboard/Sources/TanoPluginClipboard"),
        .target(name: "TanoPluginHaptics", dependencies: ["TanoBridge"], path: "packages/plugins/haptics/Sources/TanoPluginHaptics"),
        .target(name: "TanoPluginKeychain", dependencies: ["TanoBridge"], path: "packages/plugins/keychain/Sources/TanoPluginKeychain"),
        .target(name: "TanoPluginFS", dependencies: ["TanoBridge"], path: "packages/plugins/fs/Sources/TanoPluginFS"),
        .target(name: "TanoPluginCrypto", dependencies: ["TanoBridge"], path: "packages/plugins/crypto/Sources/TanoPluginCrypto"),
        .target(name: "TanoPluginBiometrics", dependencies: ["TanoBridge"], path: "packages/plugins/biometrics/Sources/TanoPluginBiometrics"),
        .target(name: "TanoPluginShare", dependencies: ["TanoBridge"], path: "packages/plugins/share/Sources/TanoPluginShare"),
        .target(name: "TanoPluginNotifications", dependencies: ["TanoBridge"], path: "packages/plugins/notifications/Sources/TanoPluginNotifications"),
        .target(name: "TanoPluginHTTP", dependencies: ["TanoBridge"], path: "packages/plugins/http/Sources/TanoPluginHTTP"),
        .target(name: "TanoPluginCamera", dependencies: ["TanoBridge"], path: "packages/plugins/camera/Sources/TanoPluginCamera"),

        // All-in-one convenience target
        .target(name: "Tano", dependencies: [
            "TanoCore", "TanoBridge", "TanoWebView",
            "TanoPluginSQLite", "TanoPluginClipboard", "TanoPluginHaptics",
            "TanoPluginKeychain", "TanoPluginFS", "TanoPluginCrypto",
            "TanoPluginBiometrics", "TanoPluginShare", "TanoPluginNotifications",
            "TanoPluginHTTP", "TanoPluginCamera",
        ], path: "Sources/Tano"),

        // Tests
        .testTarget(name: "TanoCoreTests", dependencies: ["TanoCore"], path: "packages/core/Tests/TanoCoreTests"),
        .testTarget(name: "TanoBridgeTests", dependencies: ["TanoBridge"], path: "packages/bridge/Tests/TanoBridgeTests"),
        .testTarget(name: "TanoWebViewTests", dependencies: ["TanoWebView"], path: "packages/webview/Tests/TanoWebViewTests"),
    ]
)
