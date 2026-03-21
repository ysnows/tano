# Tano Go

Tano Go is a pre-built companion app for iOS that lets you instantly preview your Tano app on a real device — no Xcode build required for JS/web changes.

## How It Works

1. Run `tano dev` in your project directory
2. Open Tano Go on your iPhone (connected to the same Wi-Fi)
3. Enter the dev server URL shown in the terminal (e.g. `http://192.168.1.100:18899`) or let Tano Go discover it automatically via Bonjour
4. Your app loads in the WebView with the Tano bridge injected

## Limitations

- **Plugin calls are proxied via HTTP** — `Tano.invoke()` calls are sent as HTTP requests to the dev server's `/api/tano/invoke` endpoint rather than calling native plugins directly. Your dev server can handle or simulate these calls.
- **No native plugins** — Tano Go is a generic shell. Native plugins (SQLite, Keychain, etc.) are not bundled. For full native plugin support, build your own app with `tano build`.
- **Local network only** — Tano Go connects over your local Wi-Fi network. Both your development machine and phone must be on the same network.

## Building from Source

Requirements:
- Xcode 15+
- iOS 16.0+ deployment target

Open the Xcode project or add the Swift files to a new iOS App target:

1. Create a new iOS App project in Xcode (SwiftUI, no storyboard)
2. Replace the generated files with the sources in this directory
3. Set the bundle identifier to `dev.tano.go`
4. Add the `Info.plist` entries for local networking permissions
5. Build and run on your device
