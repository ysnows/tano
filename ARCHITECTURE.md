# Tano Architecture

Tano is a cross-platform mobile framework that runs a Bun-compatible JavaScript/TypeScript server on the device, renders UI in a native WebView, and bridges to native APIs via a plugin system.

## Core Concept

```
Your Web App (React, Vue, Next.js, HTML)
       │ fetch()
       ▼
Bun-compatible Server (on device, via TanoJSC)
       │ UDS bridge
       ▼
Native Plugins (Swift / Kotlin)
```

## Layers

| Layer | Package | Purpose |
|-------|---------|---------|
| Runtime | `packages/core` | TanoJSC: JSC engine + Bun API shims |
| Bridge | `packages/bridge` | UDS (JobTalk), HTTP localhost, typed RPC |
| WebView | `packages/webview` | WKWebView / Android WebView + bridge.js |
| Plugins | `packages/plugins` | Native APIs (sqlite, camera, biometrics...) |
| CLI | `packages/cli` | create, dev, build, run |

## Runtime Model

- **Development**: Stock Bun on host → hot reload to simulator
- **Production**: TanoJSC (JSC + Bun shims) runs bundled code on device
- **Engine**: JavaScriptCore on both iOS and Android

## Documentation

- [Architecture Overview](docs/architecture/OVERVIEW.md)
- [Bridge Protocol](docs/architecture/BRIDGE.md)
- [TanoJSC Runtime](docs/architecture/TANOJSC.md)
- [Plugin System](docs/architecture/PLUGINS.md)
- [Roadmap](mission_control/ROADMAP.md)
- [Design Spec](docs/superpowers/specs/2026-03-20-tano-architecture-design.md)
