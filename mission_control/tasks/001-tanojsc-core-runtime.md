# Task 001: TanoJSC Core Runtime

**Status**: Next Up
**Phase**: 1 — Core Runtime
**Priority**: Critical (foundation for everything)

## Goal

Create the TanoJSC runtime — a JSC-based JavaScript runtime that can execute `Bun.serve()` and basic Bun APIs inside an iOS app.

## Acceptance Criteria

- [ ] JSC context created and managed by `TanoRuntime` Swift class
- [ ] `Bun.serve({ fetch(req) { return new Response("hello") } })` works
- [ ] `Bun.file()` reads files from app bundle
- [ ] `Bun.write()` writes files to app data directory
- [ ] `Bun.env` populated from native config
- [ ] `fetch()` works (delegates to URLSession)
- [ ] `console.log/warn/error` mapped to OSLog
- [ ] `setTimeout/setInterval/clearTimeout/clearInterval` work
- [ ] Event loop runs on background thread, doesn't block UI
- [ ] Testable in iOS simulator

## Implementation Notes

- Reference `refs/bun/src/` for Bun API surface
- Reference `refs/electrobun/` for embedding patterns
- Start with existing `examples/ios-demo/` as the test harness
- Port `EdgeJSManager.swift` → `TanoRuntime.swift`
- JSC C API: `JSGlobalContextCreate`, `JSObjectMakeFunctionWithCallback`, etc.

## Files to Create/Modify

```
packages/core/
├── jsc/
│   ├── TanoRuntime.swift          # Main runtime class
│   ├── TanoHTTPServer.swift       # Bun.serve() implementation
│   ├── TanoEventLoop.swift        # Event loop management
│   └── TanoGlobals.swift          # Global injections (fetch, console, timers)
├── bun-shims/
│   ├── bun-globals.js             # Bun.serve, Bun.file, Bun.write, Bun.env
│   └── web-apis.js                # fetch, Response, Request, Headers, URL
└── CMakeLists.txt
```
