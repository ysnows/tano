# Tano OTA Update Server

A simple Bun server that serves OTA (Over-The-Air) update manifests and bundles for Tano apps.

## How It Works

Tano apps can update their JavaScript bundles (server.js + web assets) without going through App Store review. This server provides the update manifest and bundle files that the `TanoOTAUpdate` client downloads at runtime.

## Setup

### 1. Build your app

```bash
tano build ios
```

This produces the compiled bundles in your project's `dist/` directory.

### 2. Prepare the update directory

Create the updates directory structure:

```
updates/
  production/
    manifest.json
    server.js
    web.zip
  staging/
    manifest.json
    server.js
    web.zip
```

Copy your built bundles into the appropriate channel directory:

```bash
mkdir -p updates/production
cp dist/server.js updates/production/
# If you have web assets, zip them:
cd dist/web && zip -r ../../updates/production/web.zip . && cd ../..
```

### 3. Create a manifest

Create `updates/production/manifest.json`:

```json
{
  "version": "1.1.0",
  "hash": "<sha256 hash of combined bundles>",
  "channel": "production",
  "serverBundle": {
    "url": "https://your-ota-server.com/bundles/production/server.js",
    "hash": "<sha256 of server.js>",
    "size": 45678
  },
  "webBundle": {
    "url": "https://your-ota-server.com/bundles/production/web.zip",
    "hash": "<sha256 of web.zip>",
    "size": 123456
  },
  "createdAt": "2026-03-21T10:00:00Z"
}
```

Generate hashes with:

```bash
shasum -a 256 updates/production/server.js
shasum -a 256 updates/production/web.zip
```

### 4. Run the server

```bash
bun run index.ts
```

The server starts on port 3001.

## API Endpoints

### `GET /manifest`

Returns the latest update manifest for a given channel.

Query parameters:
- `channel` (default: `production`) — update channel to check
- `current` (default: empty) — hash of the currently installed version

Responses:
- `200` with manifest JSON — an update is available
- `204` — client already has the latest version
- `404` — no manifest found for the channel

### `GET /bundles/<channel>/<filename>`

Serves the actual bundle files (server.js, web.zip).

### `GET /`

Returns server info and available endpoints.

## Configuring Your App

In your iOS app, configure the OTA client to point to this server:

```swift
import TanoCore

let otaConfig = TanoOTAUpdate.Config(
    updateURL: "https://your-ota-server.com/manifest",
    currentHash: currentBundleHash,
    channel: "production"
)

let ota = TanoOTAUpdate(config: otaConfig)

// Check for updates
let status = try await ota.checkForUpdate()
if case .available(let manifest) = status {
    try await ota.downloadUpdate(manifest: manifest)
    // Update will be applied on next app launch
}

// On app launch, check for pending updates
if let pending = ota.pendingUpdate() {
    // Use pending.serverEntry and pending.webDir
    // instead of the bundled versions
    let config = TanoConfig(serverEntry: pending.serverEntry)
    let runtime = TanoRuntime(config: config)
    runtime.start()

    // If the app runs successfully, mark as applied
    ota.markApplied()
}
```

## Channels

Use channels to manage different release tracks:

- `production` — stable releases for all users
- `staging` — pre-release testing
- `canary` — bleeding-edge builds for internal testing

Configure the channel in `TanoOTAUpdate.Config` to control which updates your app receives.
