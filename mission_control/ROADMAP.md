# Tano Roadmap

## Vision
Cross-platform mobile framework: on-device Bun-compatible runtime + WebView UI + native plugin bridge.
Integrate into existing iOS/Android projects or create standalone apps.

## Phases

### Phase 1: Core Runtime (Current)
- [ ] TanoJSC — JavaScriptCore embedding on iOS
- [ ] Bun API shims: `Bun.serve()`, `Bun.file()`, `Bun.write()`, `Bun.env`
- [ ] `fetch`, `WebSocket`, `console.*` on JSC
- [ ] Runtime lifecycle (init, run, shutdown) managed from Swift
- [ ] Verify: "Hello World" Bun server running in iOS simulator

### Phase 2: Bridge Protocol
- [ ] Port UDS bridge (FrameCodec, JobTalk) to `packages/bridge/`
- [ ] HTTP localhost data channel
- [ ] WKScriptMessageHandler control channel
- [ ] Typed RPC system (`Tano.createBridge()`)
- [ ] Verify: WebView <-> TanoJSC bidirectional communication

### Phase 3: WebView Layer
- [ ] TanoWebView (WKWebView wrapper) in `packages/webview/`
- [ ] Bridge JS injection (`window.Tano.invoke()`)
- [ ] HMR client for dev mode
- [ ] Framework proxy (Vite, Next.js static export)
- [ ] Verify: HTML page loads, fetch() hits TanoJSC server

### Phase 4: Plugin System
- [ ] `TanoPlugin` Swift protocol
- [ ] Plugin registration and routing
- [ ] Extract existing ProducerTasks into individual plugins:
  - [ ] @tano/plugin-sqlite
  - [ ] @tano/plugin-clipboard
  - [ ] @tano/plugin-biometrics
  - [ ] @tano/plugin-haptics
  - [ ] @tano/plugin-fs
  - [ ] @tano/plugin-crypto
  - [ ] @tano/plugin-keychain
  - [ ] @tano/plugin-share
  - [ ] @tano/plugin-notifications
  - [ ] @tano/plugin-http
  - [ ] @tano/plugin-camera
- [ ] JS API packages for each plugin
- [ ] Verify: Full CRUD app with SQLite + biometrics

### Phase 5: CLI Tooling
- [ ] `tano create` — project scaffolding with templates
- [ ] `tano dev` — dev server + simulator management + hot reload
- [ ] `tano build ios` / `tano build android`
- [ ] `tano run ios` / `tano run android`
- [ ] `tano plugin add/create`
- [ ] `tano doctor` — environment check
- [ ] Verify: `tano create my-app && cd my-app && tano dev` works end-to-end

### Phase 6: Android Sync
- [ ] Embed JSC on Android via JNI
- [ ] Port TanoJSC runtime to Kotlin
- [ ] Port bridge (UDS + HTTP) to Kotlin
- [ ] Port TanoWebView to Kotlin + Android WebView
- [ ] Port all plugins to Kotlin
- [ ] Verify: Same app runs on both iOS and Android

### Phase 7: Existing App Integration
- [ ] `TanoRuntime` as a Swift Package / CocoaPod
- [ ] `dev.tano:core` as a Gradle dependency
- [ ] Documentation: "Add Tano to existing iOS project"
- [ ] Documentation: "Add Tano to existing Android project"
- [ ] Minimal integration example (3 lines of code)

### Phase 8: Ecosystem
- [ ] Plugin marketplace / npm discovery
- [ ] Community plugin template
- [ ] Starter templates: React, Vue, Next.js, Svelte, plain HTML
- [ ] Example apps: todo, chat/LLM, notes, e-commerce

## Development Strategy
- **iOS-first**: All features built and tested on iOS simulator first
- **Android-sync**: Android implementation follows once iOS is stable
- **Bun reference**: `refs/bun/` for API compatibility reference
- **Electrobun reference**: `refs/electrobun/` for architecture patterns

## Self-Evolution
This project uses `mission_control/` for continuous improvement:
- `tasks/` — Active development tasks
- `logs/` — Progress logs and decisions
- `ROADMAP.md` — This file, updated as project progresses
