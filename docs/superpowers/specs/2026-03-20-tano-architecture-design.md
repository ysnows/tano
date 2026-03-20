# Tano Architecture Design Spec

**Date**: 2026-03-20
**Status**: Approved

## Summary

Tano is a cross-platform mobile framework (iOS + Android) that runs a Bun-compatible JavaScript/TypeScript server on the device, renders UI in a native WebView, and bridges to native APIs via a plugin system. It can integrate into existing iOS/Android projects or create standalone apps.

## Core Architecture Decision

**Hybrid runtime model**: Stock Bun for development, custom TanoJSC (JSC-based) runtime for device.

- **Development**: Real Bun runs on the host machine — dev server, file watching, hot reload to simulator
- **Production**: TanoJSC (lightweight JSC runtime with Bun API shims) runs bundled code on device
- **Engine**: JavaScriptCore on both iOS (native) and Android (embedded) — no V8

## Five Layers

1. **tano-core** (`packages/core/`) — TanoJSC runtime: JSC engine + Bun API shims
2. **tano-bridge** (`packages/bridge/`) — IPC: UDS (JobTalk), HTTP localhost, typed RPC
3. **tano-webview** (`packages/webview/`) — WebView container + bridge.js injection
4. **tano-plugins** (`packages/plugins/`) — Native capabilities as self-contained packages
5. **tano-cli** (`packages/cli/`) — Developer tooling: create, dev, build, run

## Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Runtime | TanoJSC (JSC + Bun shims) | Bun can't run on iOS directly; JSC is native to iOS |
| Dev runtime | Stock Bun | Fast DX, real Bun APIs, no shim bugs during dev |
| JS engine | JSC everywhere | Consistent behavior, no V8 maintenance burden |
| IPC | UDS + HTTP + WKScriptMessage | Three channels optimized for different data patterns |
| Plugin system | TanoPlugin protocol | Clean separation, testable, ecosystem-friendly |
| Frontend | Framework-agnostic | Any static-export web framework works |
| Integration | Library, not app template | Drop into existing Swift/Kotlin projects |

## Build Order (iOS-first)

1. TanoJSC core runtime (JSC + Bun.serve + basic APIs)
2. Bridge protocol (port UDS, add typed RPC)
3. WebView layer (TanoWebView + HMR)
4. Plugins (extract from existing ProducerTasks)
5. CLI (create, dev, build, run)
6. Android sync (port all layers to Kotlin + embedded JSC)
7. Existing app integration (Swift Package, Gradle dependency)

## References

- Architecture docs: `docs/architecture/`
- Bun source reference: `refs/bun/`
- Electrobun reference: `refs/electrobun/`
- Roadmap: `mission_control/ROADMAP.md`
