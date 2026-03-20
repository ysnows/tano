# Task 004: Plugin System

**Status**: Next Up
**Phase**: 4 — Plugin System
**Priority**: High (native API access for apps)

## Goal

Create the first official plugins by extracting native capabilities from the existing ios-demo's ProducerTasks.swift. Start with the most essential: SQLite, clipboard, and biometrics.

## Acceptance Criteria

- [ ] `@tano/plugin-sqlite` — open, query, run, close
- [ ] `@tano/plugin-clipboard` — copy, read
- [ ] `@tano/plugin-biometrics` — authenticate (Face ID / Touch ID)
- [ ] Each plugin: Swift implementation + JS API
- [ ] Plugins register with PluginRouter
- [ ] End-to-end: WebView invoke → PluginRouter → Plugin → response
- [ ] Tests for each plugin

## Source Reference

- `examples/ios-demo/EdgeJSDemo/Socket/ProducerTasks.swift` — all native APIs
- `examples/ios-demo/EdgeJSDemo/Socket/SQLiteBridge.swift` — SQLite implementation
- `packages/bridge/Sources/TanoBridge/TanoPlugin.swift` — plugin protocol

## Files to Create

```
packages/plugins/
├── sqlite/
│   ├── Sources/TanoPluginSQLite/SQLitePlugin.swift
│   ├── Tests/TanoPluginSQLiteTests/SQLitePluginTests.swift
│   └── Package.swift
├── clipboard/
│   ├── Sources/TanoPluginClipboard/ClipboardPlugin.swift
│   ├── Tests/TanoPluginClipboardTests/ClipboardPluginTests.swift
│   └── Package.swift
└── biometrics/
    ├── Sources/TanoPluginBiometrics/BiometricsPlugin.swift
    ├── Tests/TanoPluginBiometricsTests/BiometricsPluginTests.swift
    └── Package.swift
```
