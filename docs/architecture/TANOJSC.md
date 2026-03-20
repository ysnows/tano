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
│  │  Event Loop (libuv or CFRunLoop)         │  │
│  └──────────────────────────────────────────┘  │
└──────────────────────────────────────────────┘
```

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

Implementation: Backed by the event loop (libuv timers or CFRunLoop timers).

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

## Lifecycle

```swift
// iOS — TanoRuntime manages the JSC lifecycle
class TanoRuntime {
    private var jsContext: JSContext
    private var httpServer: TanoHTTPServer
    private var udsClient: UDSClient

    func start(serverEntry: String) {
        // 1. Create JSC context
        jsContext = JSContext()

        // 2. Inject Bun API shims
        injectBunGlobals(jsContext)
        injectFetchGlobal(jsContext)
        injectWebSocketGlobal(jsContext)
        injectConsoleGlobal(jsContext)
        injectTimerGlobals(jsContext)

        // 3. Connect to native bridge (UDS)
        udsClient = UDSClient(socketPath: socketPath)
        udsClient.connect()

        // 4. Evaluate bundled server code
        let code = try! String(contentsOfFile: serverEntry)
        jsContext.evaluateScript(code)

        // 5. Start event loop
        startEventLoop()
    }

    func shutdown() {
        httpServer.stop()
        udsClient.disconnect()
        // JSC context is ARC-managed
    }
}
```

## Event Loop

TanoJSC needs an event loop for timers, async I/O, and HTTP serving. Two options:

### Option A: CFRunLoop integration (iOS-native)
- Use the existing CFRunLoop on the runtime thread
- CFRunLoop sources for: timers, socket I/O, file I/O callbacks
- Pro: No extra dependency, plays well with iOS
- Con: More manual wiring

### Option B: libuv (portable)
- Embed libuv for the event loop (same as Node.js/Bun use internally)
- Pro: Well-tested, portable to Android, handles all I/O patterns
- Con: Extra ~200KB dependency

**Recommendation**: Start with CFRunLoop on iOS for simplicity. Evaluate libuv if we need more complex I/O patterns or for Android parity.

## Testing Strategy

- **API compatibility tests**: Run the same test suite on real Bun and TanoJSC, verify matching output
- **iOS simulator**: Primary test environment via `tano dev`
- **Subset tracking**: Maintain a compatibility matrix of which Bun APIs are implemented
