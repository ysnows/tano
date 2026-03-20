# 2026-03-21 — Crypto Plugin + iOS Demo App

## Crypto plugin
- @tano/plugin-crypto: hash (SHA-256/384/512), hmac, randomUUID, randomBytes, encrypt/decrypt (AES-GCM)
- 8 tests passing via CryptoKit

## iOS demo app created
- `examples/tano-demo/` — wires all packages together
- TanoDemoApp.swift: registers 6 plugins, starts TanoRuntime
- server.js: Bun.serve() with `/` and `/api/info` endpoints
- web/index.html: interactive UI with buttons to test all plugins
- Ready for iOS simulator testing (needs Xcode project generation)

## Plugin summary: 6 of 11 complete

| Plugin | Tests | Status |
|--------|-------|--------|
| sqlite | 7 | Done |
| clipboard | 4 | Done |
| haptics | 6 | Done |
| keychain | 5 | Done |
| fs | 7 | Done |
| crypto | 8 | Done |
| biometrics | — | Needs iOS simulator |
| share | — | Needs iOS simulator |
| notifications | — | Needs iOS simulator |
| http | — | Planned |
| camera | — | Needs iOS simulator |

## Running totals: 147 tests, 0 failures across 9 packages
