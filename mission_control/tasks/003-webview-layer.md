# Task 003: WebView Layer

**Status**: Next Up
**Phase**: 3 — WebView Layer
**Priority**: Critical (connects user's web app to the runtime)

## Goal

Create TanoWebView — a WKWebView wrapper that loads the developer's web app, injects the `window.Tano` bridge JS, and enables bidirectional communication between the WebView and TanoJSC runtime via both WKScriptMessageHandler (control) and HTTP localhost (data).

## Acceptance Criteria

- [ ] `TanoWebView` SwiftUI component in `packages/webview/`
- [ ] Loads HTML from app bundle or localhost URL
- [ ] `window.Tano.invoke(plugin, method, params)` → Promise (via WKScriptMessageHandler)
- [ ] `window.Tano.on(event, callback)` for server → WebView events
- [ ] `window.Tano.send(event, data)` for fire-and-forget messages
- [ ] `fetch('/api/...')` works to localhost Bun.serve() (data channel)
- [ ] Bridge JS auto-injected at document start
- [ ] evaluateJavaScript for server → WebView responses
- [ ] Works in iOS simulator
- [ ] Tests for message routing, bridge injection, invoke/on/send

## Dependencies

- `packages/core/` — TanoRuntime (Bun.serve for HTTP data channel)
- `packages/bridge/` — BridgeManager, PluginRouter, TanoPlugin protocol

## Files to Create

```
packages/webview/
├── Sources/TanoWebView/
│   ├── TanoWebView.swift           # SwiftUI UIViewRepresentable wrapping WKWebView
│   ├── TanoMessageHandler.swift    # WKScriptMessageHandler — routes invoke() calls
│   ├── TanoBridgeJS.swift          # The window.Tano JS bridge (injected into WebView)
│   └── TanoWebViewConfig.swift     # Configuration (entry URL, allowed origins, etc.)
├── Tests/TanoWebViewTests/
│   └── TanoBridgeJSTests.swift     # Test bridge JS generation
├── Package.swift
└── README.md
```

## Source Reference

Existing WebView code to reference:
- `examples/ios-demo/EdgeJSDemo/WebBridgeView.swift` — WKWebView + script handler
- `examples/ios-demo/EdgeJSDemo/WebappView.swift` — webapp-specific WebView
