# 2026-03-21 — Tier 1 Features Complete (RN-Inspired)

## Delivered

| Feature | Commits | Tests |
|---------|---------|-------|
| Dev Overlay | `cde53979` | — (JS, visual) |
| Deep Linking | `814cf0cb` | 12 |
| OTA Updates | `da6e0678`, `ace93246` | 12 |
| Tano Go App | `ace93246`, `79e1c7ea` | — (iOS app) |

## Dev Overlay
- In-WebView error panel (bottom of screen, semi-transparent)
- Intercepts: console.error, window.onerror, unhandled rejections, failed Tano.invoke
- Shows last 5 errors with expandable stack traces
- Double-tap top to toggle, shake to show
- Only active when `TanoDevOverlay.enabled = true`

## Deep Linking
- `TanoDeepLink.parse(url:)` — extracts path + query params
- `TanoDeepLink.navigationJS()` — generates pushState + Tano event JS
- `TanoDeepLinkHandler` — connects to WKWebView, handles Universal Links
- `Tano.onDeepLink(callback)` — JS convenience API

## OTA Updates
- `TanoOTAUpdate` — full lifecycle: check manifest, download bundles, SHA-256 verify, rollback
- Pending/applied state tracking via filesystem
- Channel system (production, staging, canary)
- Example OTA server at `examples/ota-server/`

## Tano Go Companion App
- `apps/tano-go/` — SwiftUI app with connect screen + WebView
- Bonjour/mDNS network scanner for auto-discovery
- Bridge JS proxies plugin calls via HTTP to dev server
- `tano dev` now shows LAN IP for Tano Go connection

## Stats
- 73 commits total
- 142+ tests across all packages, 0 failures
