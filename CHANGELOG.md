# Changelog

## v0.1.0 (2026-03-21)

### Core Runtime
- TanoJSC: JavaScriptCore-based runtime with Bun-compatible APIs
- `Bun.serve()` HTTP server via NWListener
- `Bun.file()`, `Bun.write()`, `Bun.env`, `Bun.sleep()`
- `fetch()` → URLSession bridge
- `WebSocket` → URLSessionWebSocketTask bridge
- `console.log/warn/error` → OSLog
- `setTimeout`/`setInterval` with thread-safe callbacks
- `Response`/`Request`/`Headers`/`URL` Web API polyfills
- Thread-safe cross-thread access via `performOnJSCThread()`

### Bridge Protocol
- UDS (Unix Domain Socket) with length-prefixed framing
- TanoPlugin protocol for native plugins
- PluginRouter for message routing
- BridgeManager coordinating UDS + plugins

### WebView
- TanoWebView (SwiftUI WKWebView wrapper)
- `window.Tano.invoke(plugin, method, params)` → Promise
- `window.Tano.on(event, callback)` for server events
- `window.Tano.send(event, data)` for fire-and-forget
- Dev mode (localhost) and production (bundle) URL loading

### Plugins (11)
- `@tano/plugin-sqlite` — SQLite database (open, query, run, close)
- `@tano/plugin-clipboard` — copy, read
- `@tano/plugin-haptics` — impact, notification, selection
- `@tano/plugin-keychain` — key-value storage
- `@tano/plugin-fs` — file system (read, write, exists, delete, list, mkdir)
- `@tano/plugin-crypto` — hash, hmac, encrypt/decrypt (AES-GCM), random
- `@tano/plugin-biometrics` — Face ID / Touch ID authentication
- `@tano/plugin-share` — share sheet
- `@tano/plugin-notifications` — local notifications
- `@tano/plugin-http` — native HTTP client
- `@tano/plugin-camera` — camera & photo picker

### CLI
- `tano create <name>` — project scaffolding (default, react, vue, nextjs templates)
- `tano dev` — development server with HMR + iOS Simulator
- `tano build ios` — bundle server + web, run xcodebuild
- `tano run ios` — build + install + launch on simulator
- `tano doctor` — environment check

### Android
- Full Kotlin port (20 files) mirroring iOS Swift packages
- All 11 plugins ported
- Gradle build configuration

### Distribution
- Root Package.swift for iOS SPM distribution
- Android build.gradle.kts

### Documentation
- Architecture docs (overview, runtime, bridge, plugins)
- Integration guides (iOS, Android, Xcode setup)
- Performance guide
- 4 example apps (demo, todo, chat, notes)

### Tests
- 118 tests from root Package.swift, 0 failures
- Individual plugin packages: 167+ tests total
