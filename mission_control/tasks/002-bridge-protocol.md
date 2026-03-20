# Task 002: Bridge Protocol

**Status**: Next Up
**Phase**: 2 — Bridge Protocol
**Priority**: Critical (connects runtime to WebView and native plugins)

## Goal

Port the UDS bridge from the existing ios-demo, add a WKScriptMessageHandler control channel, and implement a typed RPC system for WebView ↔ TanoJSC ↔ native plugin communication.

## Acceptance Criteria

- [ ] FrameCodec (length-prefixed framing) ported to `packages/bridge/ios/`
- [ ] JobTalk message protocol ported and cleaned up
- [ ] UDSServer + UDSClient ported to `packages/bridge/ios/`
- [ ] TanoJSC can connect to UDS server as a client
- [ ] Native plugins can receive method calls via UDS and return responses
- [ ] WKScriptMessageHandler bridge for WebView → native control messages
- [ ] `window.Tano.invoke(plugin, method, params)` JS API returns Promise
- [ ] Typed RPC system: `Tano.createBridge({ server: {...}, client: {...} })`
- [ ] Bidirectional: server can push events to WebView
- [ ] Tests for frame encoding/decoding, UDS round-trip, RPC type safety

## Source Reference

Existing UDS bridge code to port from:
- `examples/ios-demo/EdgeJSDemo/Socket/FrameCodec.swift` — length-prefixed framing
- `examples/ios-demo/EdgeJSDemo/Socket/JobTalk.swift` — message constants
- `examples/ios-demo/EdgeJSDemo/Socket/UDSServer.swift` — CFSocket-based server
- `examples/ios-demo/EdgeJSDemo/Socket/UDSClient.swift` — client connections
- `examples/ios-demo/EdgeJSDemo/Socket/SocketManager.swift` — singleton coordinator
- `examples/ios-demo/EdgeJSDemo/Socket/Producer.swift` — message routing
- `examples/ios-demo/EdgeJSDemo/Socket/TaskContext.swift` — request context
- `examples/ios-demo/js/lib/framing.js` — JS-side frame encoding
- `examples/ios-demo/js/lib/commander-ios.js` — JS-side UDS client

## Files to Create

```
packages/bridge/
├── ios/
│   ├── FrameCodec.swift          # Port from existing, clean up
│   ├── JobTalk.swift             # Message protocol constants
│   ├── UDSServer.swift           # Unix Domain Socket server
│   ├── UDSClient.swift           # UDS client
│   ├── BridgeManager.swift       # Coordinates UDS + plugin routing
│   ├── PluginRouter.swift        # Routes method calls to registered plugins
│   └── TanoPluginProtocol.swift  # Plugin interface (prep for Phase 4)
├── js/
│   ├── bridge.ts                 # window.Tano client (invoke, on, send)
│   ├── rpc.ts                    # Typed RPC system
│   └── framing.ts                # Frame encoding/decoding (port from JS)
└── Package.swift                 # SPM package, depends on TanoCore
```

## Architecture

```
WebView                    TanoJSC Runtime              Native Plugins
   │                            │                            │
   │── Tano.invoke() ──────────►│                            │
   │   (WKScriptMessage)        │── UDS request ────────────►│
   │                            │                            │── handle
   │                            │◄── UDS response ──────────│
   │◄── evaluateJS(resolve) ───│                            │
   │                            │                            │
   │── fetch('/api/...') ──────►│                            │
   │   (HTTP localhost)         │   (Bun.serve handles)     │
   │◄── Response ──────────────│                            │
```

## Notes
- Reuse existing CFSocket-based UDS implementation (proven, works on iOS)
- Clean up: remove Enconvo-specific naming, generalize for Tano
- The HTTP data channel already works (Bun.serve from Phase 1)
- Bridge JS will be injected into WKWebView in Phase 3
