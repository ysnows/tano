# 2026-03-21 — Phase 2: Bridge Protocol

## What was built

Ported and cleaned up the UDS bridge from ios-demo into `packages/bridge/` as the `TanoBridge` SPM package.

### Components

| File | Purpose | Origin |
|------|---------|--------|
| FrameCodec.swift | 4-byte length-prefixed frame encoding/decoding | Ported, removed legacy newline mode |
| TanoBridgeMessage.swift | Message types + builders (request/response/stream/error/event) | Rewritten from JobTalk.swift |
| UDSocket.swift | Base socket class, sockaddr_un construction | Ported, renamed from Enconvo |
| UDSServer.swift | CFSocket-based UDS server | Ported, NSLock replaces objc_sync |
| UDSClient.swift | CFSocket-based UDS client with frame decoding | Ported, cleaned API |
| TanoPlugin.swift | Plugin protocol (name, permissions, handle) | New |
| PluginRouter.swift | Routes messages to registered plugins | New |
| BridgeManager.swift | Coordinates UDS server + plugin routing | New |

### Tests: 29 passing
- FrameCodec: 11 tests (round-trips, partial frames, large payloads, big-endian)
- PluginRouter: 8 tests (routing, errors, register/unregister)
- TanoBridgeMessage: 10 tests (builders, JSON round-trip, constants)

### Cleanup from ios-demo
- All Enconvo naming → Tano
- Removed: stateId, sendId, needResult, requestId (Enconvo-specific)
- Added: plugin field for routing
- Simplified message types
- objc_sync_enter/exit → NSLock

## What's next
- Phase 2 remaining: WKScriptMessageHandler bridge + window.Tano.invoke() JS API
- These depend on Phase 3 (WebView layer), so may merge Phase 2 remaining into Phase 3
- OR: proceed to Phase 3 directly since the native bridge layer is now complete
