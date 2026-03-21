# Tano Performance Characteristics

## Startup Time

| Framework | Startup (cold) | Runtime Engine |
|-----------|---------------|----------------|
| **Tano** | ~200ms* | JavaScriptCore (native iOS, embedded Android) |
| React Native | ~300-500ms | Hermes |
| Flutter | ~200-300ms | Dart VM |
| Capacitor | ~100ms | No runtime (WebView only) |

*Estimated. Includes JSC context creation + Bun.serve() initialization.

JSC on iOS benefits from being the system framework — no dynamic library loading overhead.

## App Size

| Framework | Base Size | With 5 plugins |
|-----------|-----------|-----------------|
| **Tano** | ~5MB (runtime + bridge) | ~6MB |
| React Native | ~25MB | ~30MB |
| Flutter | ~12MB | ~15MB |
| Capacitor | ~3MB | ~5MB |

Tano is lightweight because:
- JSC is part of iOS (not bundled)
- Plugins are Swift source compiled into the app
- No JavaScript bundle for native views

## Memory

- TanoJSC runs on a single dedicated thread with its own JSC context
- HTTP server (NWListener) uses OS-managed networking
- WebView is system WKWebView (process-isolated by iOS)
- Plugin calls are synchronous on the JSC thread (no context switching overhead)

## Network

- HTTP between WebView and Bun.serve() stays on localhost (`127.0.0.1`)
- No network latency — kernel-level loopback
- UDS bridge for plugin calls — even lower latency than localhost HTTP

## Bridge Performance

| Channel | Latency | Use Case |
|---------|---------|----------|
| WKScriptMessageHandler | ~1ms | Plugin invocations (Tano.invoke) |
| HTTP localhost | ~2-5ms | Data transfer (fetch) |
| UDS (JobTalk) | <1ms | Native plugin calls |

## Optimization Tips

1. **Use HTTP for large data** — WKScriptMessageHandler serializes to JSON; fetch handles binary natively
2. **Batch plugin calls** — Each invoke has ~1ms overhead; batch operations in one call when possible
3. **Use SSE for streaming** — Server-Sent Events via Bun.serve() for real-time updates instead of polling
4. **Minimize WebView reloads** — Use CSS-only updates when possible; full reload is ~100ms
5. **SQLite over REST** — The sqlite plugin is faster than HTTP round-trips for database operations

## Benchmarking

Run on device (not simulator) for accurate numbers:

```swift
let start = CFAbsoluteTimeGetCurrent()
runtime.start()
// Wait for .running state
let elapsed = CFAbsoluteTimeGetCurrent() - start
print("Startup: \(elapsed * 1000)ms")
```

For HTTP latency:
```javascript
const start = performance.now();
const res = await fetch('/api/info');
const elapsed = performance.now() - start;
console.log(`Fetch: ${elapsed.toFixed(1)}ms`);
```
