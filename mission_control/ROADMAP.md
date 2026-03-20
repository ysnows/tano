# Tano Roadmap

## Vision
Cross-platform mobile framework: on-device Bun-compatible runtime + WebView UI + native plugin bridge.
Integrate into existing iOS/Android projects or create standalone apps.

## Phases

### Phase 1: Core Runtime — COMPLETE
- [x] TanoJSC — JavaScriptCore embedding on iOS (`packages/core/`)
- [x] Bun API shims: `Bun.serve()`, `Bun.file()`, `Bun.write()`, `Bun.env`, `Bun.sleep()`
- [x] `fetch` → URLSession, `console.*` → OSLog on JSC
- [x] Runtime lifecycle, thread-safe `performOnJSCThread()`, timers, Web API polyfills
- [x] HTTP server via NWListener, 40 tests

### Phase 2: Bridge Protocol — COMPLETE
- [x] UDS bridge (FrameCodec, UDSServer, UDSClient) in `packages/bridge/`
- [x] TanoBridgeMessage protocol, TanoPlugin protocol, PluginRouter, BridgeManager
- [x] 29 tests

### Phase 3: WebView Layer — COMPLETE
- [x] TanoWebView (SwiftUI WKWebView) in `packages/webview/`
- [x] Bridge JS (`window.Tano.invoke/on/send/emit`), WKScriptMessageHandler → PluginRouter
- [x] Dev mode (localhost) and production (bundle) loading, 41 tests

### Phase 4: Plugin System (Current)
- [x] `TanoPlugin` Swift protocol (in bridge package)
- [x] Plugin registration and routing via PluginRouter
- [x] @tano/plugin-sqlite — open, query, run, close (7 tests)
- [x] @tano/plugin-clipboard — copy, read (4 tests)
- [ ] @tano/plugin-biometrics — Face ID / Touch ID
- [x] @tano/plugin-haptics — impact/notification/selection (6 tests)
- [x] @tano/plugin-fs — read/write/exists/delete/list/mkdir (7 tests)
- [x] @tano/plugin-crypto — hash/hmac/encrypt/decrypt/random via CryptoKit (8 tests)
- [x] @tano/plugin-keychain — set/get/delete via UserDefaults (5 tests)
- [ ] @tano/plugin-share — share sheet
- [ ] @tano/plugin-notifications — local notifications
- [ ] @tano/plugin-http — native HTTP client
- [ ] @tano/plugin-camera — camera & photo picker
- [ ] Verify: Full CRUD app with SQLite + biometrics

### Phase 5: CLI Tooling
- [ ] `tano create` — project scaffolding with templates
- [ ] `tano dev` — dev server + simulator management + hot reload
- [ ] `tano build ios` / `tano build android`
- [ ] `tano run ios` / `tano run android`
- [ ] `tano plugin add/create`
- [ ] `tano doctor` — environment check

### Phase 6: Android Sync
- [ ] Embed JSC on Android via JNI
- [ ] Port TanoJSC runtime, bridge, WebView, plugins to Kotlin

### Phase 7: Existing App Integration
- [ ] Swift Package / CocoaPod + Gradle dependency
- [ ] Documentation for adding Tano to existing apps

### Phase 8: Ecosystem
- [ ] Plugin marketplace, community templates, example apps

## Test Summary
| Package | Tests |
|---------|-------|
| core | 40 |
| bridge | 29 |
| webview | 41 |
| plugin-sqlite | 7 |
| plugin-clipboard | 4 |
| plugin-haptics | 6 |
| plugin-keychain | 5 |
| plugin-fs | 7 |
| plugin-crypto | 8 |
| **Total** | **147** |

## Development Strategy
- **iOS-first**: Build and test on iOS simulator, then sync to Android
- **Bun reference**: `refs/bun/` | **Electrobun reference**: `refs/electrobun/`
