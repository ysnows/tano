# Task 008: Post-v0.1.0 Features (Inspired by React Native)

**Status**: Planning
**Priority**: High

## Tier 1: Must Build

### OTA Updates
- Manifest-based update checking (version hash + asset list)
- Delta/diff updates via bsdiff (~75% smaller downloads)
- Rollback on crash (revert if app crashes within N seconds of new bundle)
- Channel system (production, staging, canary)
- Both web UI and server bundles updatable without App Store review

### "Tano Go" Companion App
- Pre-built iOS/Android app with TanoJSC runtime + all 11 plugins
- Developer scans QR code → app connects to dev machine
- Loads web app + server code over network
- Instant preview on real device without Xcode build
- Easier than Expo Go — just a WebView + runtime

### Dev Overlay
- In-WebView error overlay during development
- Shows: server errors, bridge call failures, plugin errors
- Clickable stack traces that open in editor
- Inject only in dev mode

### Deep Linking
- Universal Links (iOS) / App Links (Android) support
- Route OS-level deep links to WebView's client-side router
- Declare link patterns in `tano.config.ts`

## Tier 2: Should Build

### Lazy Plugin Loading
- Load plugin native code on first `tano.invoke()` call
- Reduces startup time (mirrors RN TurboModules)

### Bridge Inspector
- Browser-based dashboard showing all plugin invocations
- Method, params, response time, errors
- SQLite browser for @tano/plugin-sqlite

### Typed Bridge Codegen
- Auto-generate TypeScript types from plugin definitions
- Full autocomplete for `window.Tano.invoke()` calls

## Key Insight
Tano's structural advantages over React Native:
- No bridge bottleneck (WebView renders natively)
- No navigation library wars (web routing is mature)
- No animation thread issues (CSS animations on compositor)
- OTA is easier (entire app is JS/TS)
- No New Architecture migration burden
