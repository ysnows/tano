# Tano Android (Kotlin)

Android library module for the Tano cross-platform mobile framework. This is the Kotlin port of the iOS packages (`packages/core/`, `packages/bridge/`, `packages/webview/`, `packages/plugins/`).

## Package Structure

```
src/main/kotlin/dev/tano/
├── core/
│   └── TanoRuntime.kt          # Runtime lifecycle — HandlerThread + Handler (mirrors iOS CFRunLoop)
├── bridge/
│   ├── FrameCodec.kt           # Length-prefixed framing via ByteBuffer (port of Swift FrameCodec)
│   ├── TanoBridgeMessage.kt    # Message protocol constants and builders
│   ├── TanoPlugin.kt           # Plugin interface (port of Swift TanoPlugin protocol)
│   ├── PluginRouter.kt         # Thread-safe plugin routing with coroutine dispatch
│   └── BridgeManager.kt        # UDS socket coordinator — reads frames, routes, responds
├── webview/
│   ├── TanoWebView.kt          # Android WebView with bridge injection via addJavascriptInterface
│   └── TanoBridgeJS.kt         # window.Tano bridge JS (Android-adapted from iOS)
└── plugins/
    ├── SqlitePlugin.kt         # SQLite via android.database.sqlite
    ├── ClipboardPlugin.kt      # ClipboardManager integration
    └── FSPlugin.kt             # Sandboxed file system operations
```

## How It Mirrors iOS

| iOS (Swift)                              | Android (Kotlin)                          |
|------------------------------------------|-------------------------------------------|
| `Thread` + `CFRunLoop`                   | `HandlerThread` + `Handler`               |
| `WKWebView` + `WKScriptMessageHandler`  | `WebView` + `addJavascriptInterface`      |
| `NSLock`                                 | `@Synchronized` / `synchronized {}`       |
| `async/await` (Swift concurrency)        | `suspend fun` + coroutines                |
| `Data` + `withUnsafeBytes`               | `ByteBuffer` + `ByteOrder.BIG_ENDIAN`    |
| `webkit.messageHandlers.tano.postMessage`| `TanoAndroid.invoke()` via JS interface   |
| `evaluateJavaScript()`                   | `evaluateJavascript()`                    |
| `UIPasteboard`                           | `ClipboardManager`                        |
| `SQLite3` (C API)                        | `android.database.sqlite.SQLiteDatabase`  |
| `FileManager`                            | `java.io.File`                            |

## Integration

The actual JSC embedding uses the existing `edge_embed` native library (loaded via `System.loadLibrary`). This Kotlin layer provides the API surface that wraps the JNI bridge, matching the iOS API design 1:1.

## Usage

```kotlin
// Create runtime
val config = TanoConfig(
    serverEntry = "/path/to/app.js",
    env = mapOf("NODE_ENV" to "production"),
    dataPath = context.filesDir.absolutePath
)
val runtime = TanoRuntime(config)

// Set up plugins
val router = PluginRouter()
router.register(SqlitePlugin(context.filesDir.absolutePath + "/db"))
router.register(ClipboardPlugin(context))
router.register(FSPlugin(context.filesDir.absolutePath))

// Set up WebView
val webView = TanoWebView(context)
webView.pluginRouter = router
webView.loadUrl("file:///android_asset/index.html")

// Start runtime
runtime.start()
```
