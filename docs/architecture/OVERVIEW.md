# Tano Architecture Overview

## Core Concept

Tano runs a **Bun-compatible JavaScript/TypeScript server on the mobile device** and renders UI in a **native WebView**. The server and WebView communicate via localhost HTTP and native bridge channels.

This is the same mental model as web development: your frontend talks to your backend via `fetch()`. Except both run on the same device.

## Layer Architecture

```
┌──────────────────────────────────────────────────────┐
│  Developer's App (JS/TS + HTML/CSS)                  │ ← what you write
├──────────────────────────────────────────────────────┤
│  tano-plugins                                         │ ← native APIs
│  (@tano/plugin-sqlite, camera, biometrics, etc.)     │
├──────────────────────────────────────────────────────┤
│  tano-webview                                         │ ← UI rendering
│  (WKWebView / Android WebView + bridge.js)           │
├──────────────────────────────────────────────────────┤
│  tano-bridge                                          │ ← IPC protocol
│  (UDS JobTalk + HTTP localhost + typed RPC)           │
├──────────────────────────────────────────────────────┤
│  tano-core                                            │ ← runtime engine
│  (TanoJSC: JavaScriptCore + Bun API shims)           │
├──────────────────────────────────────────────────────┤
│  tano-cli                                             │ ← dev tooling
│  (create, dev, build, run, plugin management)        │
└──────────────────────────────────────────────────────┘
```

## Two Modes

### Development Mode

```
Host Machine (macOS)              iOS Simulator / Android Emulator
┌──────────────────┐              ┌──────────────────┐
│  Bun (stock)     │── WebSocket──│  WebView          │
│  • dev server    │              │  • HMR client     │
│  • file watcher  │              │  • bridge.js      │
│  • bundler       │◄── fetch ───│                    │
└──────────────────┘              └──────────────────┘
```

- Real Bun runs on your machine — full Bun API, fast bundling, file watching
- WebView in simulator connects to your dev server
- Hot Module Replacement for instant feedback
- Server code changes hot-reload without full restart

### Production Mode

```
On Device (iOS / Android)
┌──────────────────────────────────────────┐
│  Native Shell (Swift / Kotlin)           │
│  ┌──────────────┐  ┌─────────────────┐  │
│  │ TanoJSC      │  │ Native Plugins  │  │
│  │ (JSC engine) │◄─┤ sqlite, camera  │  │
│  │              │  │ biometrics, fs  │  │
│  │ Bun.serve()  │  └─────────────────┘  │
│  │ Bun.file()   │                        │
│  │ fetch, WS    │                        │
│  └──────┬───────┘                        │
│         │ HTTP localhost                 │
│         ▼                                │
│  ┌──────────────────────────────────┐   │
│  │ WebView (bundled web app)        │   │
│  │ React / Vue / Next.js / HTML     │   │
│  └──────────────────────────────────┘   │
└──────────────────────────────────────────┘
```

- Bun bundler pre-compiles server + web code at build time
- TanoJSC (our lightweight JSC runtime) runs the bundled server code
- WebView loads static files from the app bundle
- All communication stays on `localhost` — no network required

## TanoJSC Runtime

TanoJSC is NOT a full Bun port. It's a **minimal JSC-based runtime** that implements the subset of Bun APIs needed for mobile:

| Bun API | TanoJSC Implementation |
|---------|----------------------|
| `Bun.serve()` | HTTP server on JSC (libuv event loop) |
| `Bun.file()` | Bridge to native file system |
| `Bun.write()` | Bridge to native file system |
| `Bun.env` | Injected from native config at startup |
| `Bun.sleep()` | JSC timer + run loop |
| `fetch` | Native URLSession (iOS) / OkHttp (Android) |
| `WebSocket` | Native WebSocket implementation |
| `console.*` | OSLog (iOS) / Logcat (Android) |
| `crypto` | CryptoKit (iOS) / javax.crypto (Android) |

APIs that don't apply to mobile (`Bun.spawn()`, `Bun.listen()` on TCP, worker threads) are not implemented.

JavaScriptCore is used on **both platforms** — native on iOS, embedded on Android — for consistent behavior.

## IPC Protocol

Three communication channels between the layers:

### Channel 1: Control Bridge (WebView <-> TanoJSC)
- **Transport**: WKScriptMessageHandler (iOS) / addJavascriptInterface (Android)
- **Use**: Low-latency control messages, plugin invocations from UI
- **API**: `window.Tano.invoke(plugin, method, params)` → Promise
- **Direction**: Bidirectional

### Channel 2: Data Bridge (WebView <-> TanoJSC)
- **Transport**: HTTP on localhost (dynamic port)
- **Use**: Large payloads, file uploads, SSE streaming
- **API**: Standard `fetch()` from WebView
- **Why separate**: WKScriptMessage has size limits

### Channel 3: Native Bridge (TanoJSC <-> Plugins)
- **Transport**: Unix Domain Sockets with JobTalk protocol
- **Use**: TanoJSC calling native Swift/Kotlin plugin code
- **Message format**: JSON with callId, method, params, response types
- **Supports**: Request/response, streaming, fire-and-forget

## Plugin System

Every native capability is a plugin with three parts:

```
@tano/plugin-sqlite/
├── src/
│   ├── index.ts                # JS API (what developers import)
│   ├── ios/SqlitePlugin.swift  # Native iOS implementation
│   └── android/SqlitePlugin.kt # Native Android implementation
└── tano-plugin.json            # Manifest (name, permissions)
```

Plugins implement a standard protocol:

```swift
// iOS
protocol TanoPlugin {
    static var name: String { get }
    static var permissions: [String] { get }
    func handle(method: String, params: [String: Any],
                context: TaskContext) async throws -> Any?
}
```

```kotlin
// Android
interface TanoPlugin {
    val name: String
    val permissions: List<String>
    suspend fun handle(method: String, params: JSONObject,
                       context: TaskContext): Any?
}
```

## Existing App Integration

Tano is designed to be embeddable in existing native projects:

### iOS (Swift Package / CocoaPod)
```swift
import Tano

let tano = TanoRuntime(config: .init(
    serverEntry: "server.js",
    webEntry: "web/index.html",
    plugins: [SqlitePlugin(), BiometricsPlugin()]
))

// Add anywhere in your SwiftUI hierarchy
TanoWebView(runtime: tano)
```

### Android (Gradle dependency)
```kotlin
import dev.tano.core.TanoRuntime
import dev.tano.webview.TanoWebView

val tano = TanoRuntime(serverEntry = "server.js", plugins = listOf(SqlitePlugin()))

// Use in any Composable
TanoWebView(runtime = tano)
```

The native app retains full control. Tano views can coexist with native views. Multiple TanoRuntime instances can run simultaneously for different features.

## Build Pipeline

```
tano build ios:

  1. bun build src/server/index.ts → dist/server.js    (Bun bundler)
  2. vite build src/web/ → dist/web/                     (or next export, etc.)
  3. Generate Xcode project with:
     - TanoJSC framework
     - Plugin native code
     - Bundled dist/ assets
  4. xcodebuild → MyApp.app

tano build android:

  1. bun build src/server/index.ts → dist/server.js
  2. vite build src/web/ → dist/web/
  3. Generate Gradle project with:
     - TanoJSC .aar
     - Plugin native code
     - Bundled dist/ assets
  4. gradle assembleRelease → MyApp.apk
```

## Security Model

- Localhost HTTP bound to `127.0.0.1` only (no network exposure)
- WebView navigation restricted to allowed origins
- Plugin permissions declared in `tano.config.ts`, mapped to Info.plist / AndroidManifest.xml
- File system access sandboxed to app container
- No eval() or dynamic code execution in production mode

## Implementation Status

| Package | Path | Tests | Status |
|---------|------|-------|--------|
| TanoCore | `packages/core/` | 40 | Complete — JSC runtime, Bun API shims, HTTP server |
| TanoBridge | `packages/bridge/` | 29 | Complete — UDS, FrameCodec, PluginRouter |
| TanoWebView | `packages/webview/` | 41 | Complete — WKWebView, bridge JS, message handler |
| plugin-sqlite | `packages/plugins/sqlite/` | 7 | Complete |
| plugin-clipboard | `packages/plugins/clipboard/` | 4 | Complete |
| plugin-haptics | `packages/plugins/haptics/` | 6 | Complete |
| plugin-keychain | `packages/plugins/keychain/` | 5 | Complete |
| plugin-fs | `packages/plugins/fs/` | 7 | Complete |
| plugin-crypto | `packages/plugins/crypto/` | 8 | Complete |
| plugin-biometrics | `packages/plugins/biometrics/` | 3 | Complete (iOS stub on macOS) |
| plugin-share | `packages/plugins/share/` | 4 | Complete (iOS stub on macOS) |
| plugin-notifications | `packages/plugins/notifications/` | 5 | Complete (iOS stub on macOS) |
| plugin-http | `packages/plugins/http/` | 4 | Complete |
| plugin-camera | `packages/plugins/camera/` | 4 | Complete (iOS stub on macOS) |
| @tano/cli | `packages/cli/` | — | Complete — create, dev, build, run, doctor |
| Demo app | `examples/tano-demo/` | — | Created — wires all packages for simulator |
| **Total** | **16 packages** | **167** | |

## References

- `refs/bun/` — Bun source for API compatibility reference
- `refs/electrobun/` — Electrobun for Bun embedding patterns
- [Tauri](https://tauri.app/) — WebView + native backend philosophy
- [Capacitor](https://capacitorjs.com/) — Plugin system patterns
