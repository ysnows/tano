# Setting Up a Tano App in Xcode (iOS Simulator)

## Quick Start

### Option 1: Use `tano dev` (no Xcode project needed)

```bash
tano create my-app
cd my-app
tano dev
```

This starts the Bun server and opens the simulator with Safari pointing to localhost. No Xcode project required for development.

### Option 2: Create an Xcode Project

For full native integration (TanoWebView, plugins, App Store submission):

#### 1. Create a new Xcode project

- Open Xcode → File → New → Project → iOS App
- Language: Swift, Interface: SwiftUI
- Bundle ID: `com.yourcompany.myapp`

#### 2. Add Tano as a Swift Package

- File → Add Package Dependencies
- URL: `https://github.com/user/tano.git` (or local path)
- Select the `Tano` product (all-in-one)

#### 3. Add your server.js and web files

- Drag your `dist/server.js` into the Xcode project (check "Copy items")
- Drag your `dist/web/` folder into the project
- Ensure they're in the "Copy Bundle Resources" build phase

#### 4. Wire up the app

```swift
// MyApp.swift
import SwiftUI
import Tano

@main
struct MyApp: App {
    @StateObject private var appState = TanoAppState()

    var body: some Scene {
        WindowGroup {
            TanoWebView(
                config: TanoWebViewConfig(serverPort: 18899),
                pluginRouter: appState.pluginRouter
            )
            .ignoresSafeArea()
            .onAppear { appState.start() }
        }
    }
}

class TanoAppState: ObservableObject {
    var runtime: TanoRuntime?
    let pluginRouter = PluginRouter()

    func start() {
        // Register plugins
        pluginRouter.register(plugin: SQLitePlugin())
        pluginRouter.register(plugin: ClipboardPlugin())
        pluginRouter.register(plugin: CryptoPlugin())

        // Start runtime
        guard let serverPath = Bundle.main.path(forResource: "server", ofType: "js") else {
            print("server.js not found in bundle")
            return
        }

        let config = TanoConfig(serverEntry: serverPath)
        runtime = TanoRuntime(config: config)
        runtime?.start()
    }
}
```

#### 5. Build and run

- Select an iOS Simulator (iPhone 15 Pro recommended)
- Cmd+R to build and run
- The app starts the Bun server, loads the WebView, and you can use all plugins

## Build for Device

1. Run `tano build ios` to bundle server + web
2. In Xcode, select your physical device
3. Set up signing (Team, Bundle ID)
4. Cmd+R

## Troubleshooting

| Issue | Fix |
|-------|-----|
| "server.js not found" | Ensure it's in Copy Bundle Resources |
| WebView shows blank | Check server port matches config |
| Plugins not responding | Verify plugins are registered before runtime.start() |
| Build error "No such module" | Clean build folder (Cmd+Shift+K), re-resolve packages |
