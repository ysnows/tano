# TanoJSC Runtime

## Overview

TanoJSC is a lightweight JavaScriptCore-based runtime that implements Bun-compatible APIs on mobile devices. It is NOT a Bun port — it's a purpose-built mobile runtime that speaks the same API surface.

## Design Principles

1. **Bun API compatibility** — Write `Bun.serve()`, it works on device
2. **Mobile-first** — No APIs that don't make sense on mobile (no `spawn`, no TCP servers)
3. **JSC everywhere** — Same engine on iOS (native) and Android (embedded)
4. **Thin shims** — Most work delegated to native via bridge, not reimplemented in JS

## Architecture

```
┌──────────────────────────────────────────────┐
│  TanoJSC Runtime                              │
│                                               │
│  ┌─────────────────┐  ┌──────────────────┐  │
│  │  JSC Engine      │  │  Bun API Shims   │  │
│  │  (JavaScriptCore)│  │  serve, file,    │  │
│  │                  │  │  write, env,     │  │
│  │  • JS execution  │  │  sleep, fetch    │  │
│  │  • GC            │  └────────┬─────────┘  │
│  │  • JIT (iOS)     │           │             │
│  └────────┬─────────┘  ┌────────▼─────────┐  │
│           │             │  Native Bindings  │  │
│           │             │  (C API → JSC)    │  │
│           │             │  • HTTP server    │  │
│           │             │  • File I/O       │  │
│           │             │  • UDS client     │  │
│           │             │  • Timers         │  │
│           │             └────────┬─────────┘  │
│           │                      │             │
│  ┌────────▼──────────────────────▼─────────┐  │
│  │  Event Loop (CFRunLoop)                   │  │
│  └──────────────────────────────────────────┘  │
└──────────────────────────────────────────────┘
```

## Implementation Status (Phase 1 Complete)

The runtime is implemented at `packages/core/` as a Swift Package (SPM).

| File | Purpose |
|------|---------|
| `TanoRuntime.swift` | JSC lifecycle, dedicated Thread + CFRunLoop, `performOnJSCThread()` |
| `TanoGlobals.swift` | Unified injection of all globals into JSContext |
| `TanoConsole.swift` | `console.*` → OSLog |
| `TanoTimers.swift` | setTimeout/setInterval via DispatchSourceTimer + JSC thread marshalling |
| `TanoWebAPIs.swift` | Response/Request/Headers/URL/URLSearchParams JS polyfills |
| `TanoBunAPI.swift` | Bun.file/write/env/sleep/serve |
| `TanoFetch.swift` | fetch() → URLSession with JSC thread marshalling |
| `TanoHTTPServer.swift` | NWListener-based HTTP/1.1 server |
| `TanoHTTPParser.swift` | Raw HTTP request parser |
| `TanoHTTPResponse.swift` | HTTP response builder |
| `JSCHelpers.swift` | JSC convenience wrappers |

### Thread Safety Model

All JSC operations are confined to a single dedicated thread (`dev.tano.runtime`). Other threads (Network.framework, URLSession, DispatchSourceTimer) marshal work back via:

```swift
public func performOnJSCThread(_ block: @escaping () -> Void) {
    CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue, block)
    CFRunLoopWakeUp(runLoop)
}
```

This is the single most important method in the runtime — it enables safe cross-thread JSC access.

## Bun API Shims

### Bun.serve()

```typescript
// What developers write:
Bun.serve({
    port: 18899,
    async fetch(req) {
        return new Response("Hello from Tano!")
    }
})
```

Implementation: Lightweight HTTP/1.1 server bound to `127.0.0.1`. On iOS, backed by `NWListener` or a minimal C HTTP parser. Supports:
- Request/Response (standard Web API)
- JSON responses (`Response.json()`)
- SSE streaming
- Static file serving (`Bun.file()`)
- WebSocket upgrade

### Bun.file() / Bun.write()

```typescript
const file = Bun.file("data.json")
const text = await file.text()
const json = await file.json()

await Bun.write("output.txt", "hello")
await Bun.write("data.json", JSON.stringify({ key: "value" }))
```

Implementation: Bridge to native `FileManager` (iOS) / `java.io.File` (Android) via JSC C API bindings. Paths are sandboxed to the app container.

### fetch / Response / Request

```typescript
const res = await fetch("https://api.example.com/data")
const data = await res.json()
```

Implementation: Delegates to native `URLSession` (iOS) / `OkHttp` (Android) for actual HTTP requests. The JSC shim converts between JS Request/Response objects and native types. Benefits:
- Proper TLS/certificate handling by the OS
- HTTP/2 support for free
- Respects system proxy settings
- Cookie jar integration

### WebSocket

```typescript
const ws = new WebSocket("wss://example.com/ws")
ws.onmessage = (event) => console.log(event.data)
```

Implementation: Native `URLSessionWebSocketTask` (iOS) / `OkHttp WebSocket` (Android).

### console.*

```typescript
console.log("debug info")    // → os_log(.debug)
console.warn("warning")      // → os_log(.default)
console.error("error!")      // → os_log(.error)
```

Implementation: Maps to `OSLog` (iOS) / `Log` (Android). In dev mode, also forwards to the host Bun process for terminal output.

### Timers

```typescript
setTimeout(() => {}, 1000)
setInterval(() => {}, 5000)
await Bun.sleep(500)
```

Implementation: DispatchSourceTimer fires on GCD queue, callback marshalled to JSC thread via `performOnJSCThread()`.

### Bun.env

```typescript
const apiKey = Bun.env.API_KEY
const debug = Bun.env.DEBUG === "true"
```

Implementation: Injected from native at runtime startup. Sources:
1. `tano.config.ts` build-time env
2. Native runtime config passed via `TanoRuntime(config:)`
3. Secure storage for secrets (Keychain-backed)

## What's NOT Implemented

These Bun APIs are desktop/server concepts that don't apply to mobile:

| Bun API | Why not on mobile |
|---------|------------------|
| `Bun.spawn()` / `Bun.spawnSync()` | iOS forbids spawning child processes |
| `Bun.listen()` (TCP) | No use case for raw TCP server on phone |
| `Bun.connect()` (TCP) | Use `fetch` or `WebSocket` instead |
| `worker_threads` | JSC has its own concurrency model |
| `node:child_process` | Same as spawn — forbidden on iOS |
| `node:cluster` | Single device, single process |
| `Bun.build()` | Bundling happens at build time on host |
| `bun:test` | Tests run on host with real Bun |
| `bun:ffi` | Use the plugin system instead |

## Lifecycle (Actual Implementation)

```swift
let config = TanoConfig(
    serverEntry: "server.js",
    env: ["API_KEY": "xxx"]
)

let runtime = TanoRuntime(config: config)
runtime.start()   // spawns "dev.tano.runtime" Thread
// ...
runtime.stop()    // CFRunLoopStop → cleanup → .stopped
```

Internally, `start()` spawns a dedicated Thread that:
1. Creates JSContext
2. Stores CFRunLoopGetCurrent() for cross-thread scheduling
3. Creates TanoTimers with jscPerform closure
4. Calls TanoGlobals.inject() — console, timers, Web APIs, Bun shims, fetch, polyfills
5. Evaluates the server entry script
6. Enters CFRunLoopRun() — blocks until stop()

## Event Loop

**Decision: CFRunLoop** (implemented). The runtime thread uses `CFRunLoopRun()` as the event loop. Cross-thread work is scheduled via `CFRunLoopPerformBlock` + `CFRunLoopWakeUp`. Timers use `DispatchSourceTimer` with callbacks marshalled to the JSC thread.

No libuv dependency. For Android, we'll evaluate whether CFRunLoop can be replaced with a similar construct or if libuv is needed.

## Testing

40 tests in `packages/core/Tests/TanoCoreTests/`:
- Runtime lifecycle (3 tests)
- Console (4 tests)
- Timers (4 tests)
- Web APIs (7 tests)
- Bun APIs (6 tests)
- Fetch (3 tests)
- HTTP server + parser (9 tests)
- Integration — full Bun.serve() (4 tests)

Run: `cd packages/core && swift test`
