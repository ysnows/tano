# Bridge Protocol

## Overview

Tano uses three communication channels to connect the WebView, TanoJSC runtime, and native plugins. Each channel is optimized for a specific use case.

## Channel 1: Control Bridge

**WebView <-> TanoJSC via native message handler**

```
WebView JS                      Native Shell                    TanoJSC
    │                               │                               │
    │── window.Tano.invoke() ──────►│                               │
    │   (WKScriptMessageHandler)    │── forward via UDS ───────────►│
    │                               │                               │── process
    │                               │◄── response via UDS ─────────│
    │◄── evaluateJavaScript() ─────│                               │
    │   (resolve Promise)           │                               │
```

### WebView API

```typescript
// Injected by tano-webview as window.Tano
interface TanoBridge {
    // Call a plugin method
    invoke(plugin: string, method: string, params?: any): Promise<any>

    // Listen for events from the server
    on(event: string, callback: (data: any) => void): () => void

    // One-way message to server
    send(event: string, data?: any): void
}

// Usage
const result = await window.Tano.invoke('clipboard', 'read')
const unsub = window.Tano.on('notification', (data) => console.log(data))
```

### iOS Implementation

```swift
class TanoMessageHandler: NSObject, WKScriptMessageHandler {
    func userContentController(_ controller: WKUserContentController,
                                didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let callId = body["callId"] as? String,
              let plugin = body["plugin"] as? String,
              let method = body["method"] as? String else { return }

        let params = body["params"] as? [String: Any] ?? [:]

        // Route to plugin via UDS bridge
        bridge.send(plugin: plugin, method: method, params: params) { result in
            // Send response back to WebView
            let js = "window.__tano_resolve('\(callId)', \(result.json))"
            self.webView.evaluateJavaScript(js)
        }
    }
}
```

## Channel 2: Data Bridge

**WebView <-> TanoJSC via HTTP localhost**

```
WebView JS                              TanoJSC (Bun.serve)
    │                                        │
    │── fetch('http://localhost:18899') ─────►│
    │                                        │── handle request
    │◄── Response (JSON, SSE, binary) ──────│
    │                                        │
```

### Use Cases

| Pattern | Example |
|---------|---------|
| REST API | `fetch('/api/todos')` → JSON response |
| Server-Sent Events | `new EventSource('/api/stream')` → LLM streaming |
| File upload | `fetch('/api/upload', { method: 'POST', body: formData })` |
| File download | `fetch('/api/file/photo.jpg')` → binary blob |

### Why HTTP?

- WKScriptMessage serializes everything to JSON, has size limits (~128MB but slow for large data)
- HTTP is natural for web developers — no new API to learn
- SSE works out of the box for streaming
- Supports binary data without base64 encoding
- Standard CORS / caching / compression

## Channel 3: Native Bridge

**TanoJSC <-> Native Plugins via Unix Domain Socket**

```
TanoJSC Runtime                 UDS (JobTalk)                Native Plugin
    │                               │                            │
    │── {callId, method, params} ──►│                            │
    │   (length-prefixed frame)     │── route to plugin ────────►│
    │                               │                            │── execute
    │                               │◄── {callId, result} ──────│
    │◄── response frame ───────────│                            │
    │                               │                            │
```

### JobTalk Protocol

Messages are length-prefixed JSON frames over Unix Domain Socket:

```
┌──────────┬────────────────────────┐
│ 4 bytes  │ N bytes                │
│ (length) │ (JSON payload)         │
└──────────┴────────────────────────┘
```

### Message Types

```typescript
// Request: TanoJSC → Plugin
{
    "type": "request",
    "callId": "uuid-1234",
    "plugin": "sqlite",
    "method": "query",
    "params": {
        "db": "app.db",
        "sql": "SELECT * FROM users",
        "args": []
    }
}

// Response: Plugin → TanoJSC
{
    "type": "response",
    "callId": "uuid-1234",
    "result": [{"id": 1, "name": "Alice"}]
}

// Stream response: Plugin → TanoJSC (for LLM, large data)
{
    "type": "responseStream",
    "callId": "uuid-1234",
    "chunk": "partial data..."
}

// Stream end
{
    "type": "responseEnd",
    "callId": "uuid-1234"
}

// Error
{
    "type": "error",
    "callId": "uuid-1234",
    "error": {"code": "NOT_FOUND", "message": "Plugin not registered"}
}
```

## Typed RPC System

For type-safe communication between WebView and server:

```typescript
// Shared schema definition
import { createBridge } from '@tano/bridge'

const bridge = createBridge({
    // Server-side handlers (TanoJSC)
    server: {
        getTodos: () => Promise<Todo[]>,
        addTodo: (text: string) => Promise<Todo>,
        streamChat: (prompt: string) => AsyncGenerator<string>,
    },
    // Client-side handlers (WebView)
    client: {
        onPushNotification: (payload: NotificationData) => void,
        onThemeChange: (theme: 'light' | 'dark') => void,
    }
})

// In WebView — fully typed
const todos = await bridge.server.getTodos()
bridge.client.onPushNotification((data) => alert(data.title))

// In server — fully typed
bridge.server.handle('getTodos', async () => {
    return db.query('SELECT * FROM todos')
})
bridge.client.send('onThemeChange', 'dark')
```

## Security

- HTTP server binds to `127.0.0.1` only — not accessible from network
- UDS socket is in the app sandbox — no other app can connect
- WebView navigation whitelist prevents loading external pages
- Plugin permissions must be declared — runtime enforces access control
- No `eval()` in production builds
