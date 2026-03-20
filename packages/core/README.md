# TanoCore

JavaScriptCore-based runtime with Bun-compatible APIs for iOS and Android.

## Usage

```swift
import TanoCore

let config = TanoConfig(
    serverEntry: Bundle.main.path(forResource: "server", ofType: "js")!,
    env: ["API_KEY": "xxx"]
)

let runtime = TanoRuntime(config: config)
runtime.start()
// Server is now running on localhost
```

## Implemented Bun APIs

- `Bun.serve()` — HTTP server (NWListener)
- `Bun.file()` — File reading (text, json, exists, size)
- `Bun.write()` — File writing
- `Bun.env` — Environment variables
- `Bun.sleep()` — Async delay
- `fetch()` — HTTP client (URLSession)
- `Response` / `Request` / `Headers` / `URL`
- `console.log/warn/error/info` → OSLog
- `setTimeout` / `setInterval` / `clearTimeout` / `clearInterval`
