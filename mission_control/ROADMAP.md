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

### Phase 5: CLI Tooling — MOSTLY COMPLETE
- [x] `tano create <name>` — project scaffolding with default template
- [x] `tano doctor` — environment check (Bun, Xcode, simulators, Android SDK)
- [x] `tano dev` — Bun server + file watch + opens iOS Simulator
- [x] `tano build ios` — bundles server + web via Bun.build, runs xcodebuild
- [x] `tano run ios` — build + install + launch on simulator
- [x] CLI framework with help, version, command routing
- [x] Default project template (server.ts + web UI + tano.config.ts)
- [ ] `tano build android` / `tano run android` (after Phase 6)
- [ ] `tano plugin add/create`

### Phase 6: Android Sync — IN PROGRESS
- [x] TanoRuntime.kt — runtime lifecycle with HandlerThread + Handler
- [x] FrameCodec.kt — length-prefixed framing (ByteBuffer)
- [x] TanoBridgeMessage.kt — message protocol (matches iOS)
- [x] TanoPlugin.kt + PluginRouter.kt — plugin interface + routing
- [x] BridgeManager.kt — UDS coordinator
- [x] TanoWebView.kt — Android WebView + addJavascriptInterface bridge
- [x] TanoBridgeJS.kt — bridge JS with Android adapter
- [x] SqlitePlugin.kt, ClipboardPlugin.kt, FSPlugin.kt — 3 plugins ported
- [ ] Integrate jsc-android or edge_embed JNI for actual JSC execution
- [ ] Gradle build configuration
- [ ] `tano build android` / `tano run android` in CLI
- [ ] End-to-end test on Android emulator

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
