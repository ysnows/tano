# Task 006: Android Sync

**Status**: Next Up
**Phase**: 6 — Android Sync
**Priority**: High (cross-platform promise)

## Goal

Port all iOS packages to Android (Kotlin) so the same Tano app runs on both platforms.

## Strategy

1. Embed JavaScriptCore on Android via JNI (using jsc-android or similar)
2. Port TanoRuntime (JSC lifecycle, Bun API shims) to Kotlin
3. Port bridge (UDS server/client, FrameCodec, PluginRouter) to Kotlin
4. Port TanoWebView (Android WebView + bridge JS injection) to Kotlin
5. Port all 11 plugins to Kotlin
6. Update CLI: `tano build android` and `tano run android`

## Key Decisions

- **JSC on Android**: Use `jsc-android` npm package or build JSC from WebKit source
- **UDS on Android**: Unix domain sockets work on Android via `LocalSocket`
- **WebView**: Android WebView with `addJavascriptInterface` (replaces WKScriptMessageHandler)
- **Build**: Gradle with CMake for JNI, Kotlin for app code
- **Shared**: bridge.js, web APIs polyfills, Bun shims JS code are shared across platforms

## Acceptance Criteria

- [ ] JSC embedded and running on Android emulator
- [ ] Bun.serve() works on Android
- [ ] WebView loads and bridge.js works
- [ ] At least 3 plugins ported (sqlite, clipboard, fs)
- [ ] `tano build android` and `tano run android` work
- [ ] Same demo app runs on both iOS and Android

## Source Reference

- `examples/android-demo/` — existing Android demo with Kotlin/Compose
- `packages/core/Sources/TanoCore/` — iOS runtime to port
- `packages/bridge/Sources/TanoBridge/` — iOS bridge to port
