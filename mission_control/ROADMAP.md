# Tano Roadmap

## Vision
Cross-platform mobile framework: on-device Bun-compatible runtime + WebView UI + native plugin bridge.
Integrate into existing iOS/Android projects or create standalone apps.

## Phases

### Phase 1: Core Runtime — COMPLETE
- [x] TanoJSC runtime, Bun API shims, fetch, console, timers, Web APIs, HTTP server
- [x] 40 tests in `packages/core/`

### Phase 2: Bridge Protocol — COMPLETE
- [x] UDS bridge, TanoBridgeMessage, TanoPlugin protocol, PluginRouter, BridgeManager
- [x] 29 tests in `packages/bridge/`

### Phase 3: WebView Layer — COMPLETE
- [x] TanoWebView, bridge JS (invoke/on/send/emit), WKScriptMessageHandler
- [x] 41 tests in `packages/webview/`

### Phase 4: Plugin System — COMPLETE
- [x] @tano/plugin-sqlite — open, query, run, close (7 tests)
- [x] @tano/plugin-clipboard — copy, read (4 tests)
- [x] @tano/plugin-haptics — impact, notification, selection (6 tests)
- [x] @tano/plugin-keychain — set, get, delete (5 tests)
- [x] @tano/plugin-fs — read, write, exists, delete, list, mkdir (7 tests)
- [x] @tano/plugin-crypto — hash, hmac, encrypt/decrypt, random (8 tests)
- [x] @tano/plugin-biometrics — authenticate via LAContext (3 tests)
- [x] @tano/plugin-share — share sheet (4 tests)
- [x] @tano/plugin-notifications — requestPermission, schedule, cancel (5 tests)
- [x] @tano/plugin-http — native HTTP client (4 tests)
- [x] @tano/plugin-camera — takePicture, pickImage (4 tests)
- [x] All 11 plugins: 57 tests total

### Phase 5: CLI Tooling — IN PROGRESS
- [x] `tano create <name>` — project scaffolding with default template
- [x] `tano doctor` — environment check (Bun, Xcode, simulators, Android SDK)
- [x] CLI framework with help, version, command routing
- [x] Default project template (server.js + web UI + tano.config.ts)
- [ ] `tano dev` — dev server + simulator management + hot reload
- [ ] `tano build ios` / `tano build android`
- [ ] `tano run ios` / `tano run android`
- [ ] `tano plugin add/create`

### Phase 6: Android Sync
- [ ] Embed JSC on Android via JNI
- [ ] Port all packages to Kotlin

### Phase 7: Existing App Integration
- [ ] Swift Package / CocoaPod + Gradle dependency
- [ ] Documentation

### Phase 8: Ecosystem
- [ ] Plugin marketplace, templates, example apps

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
| plugin-biometrics | 3 |
| plugin-share | 4 |
| plugin-notifications | 5 |
| plugin-http | 4 |
| plugin-camera | 4 |
| **Total** | **167** |
