# Add Tano to an Existing iOS Project

## 1. Add the Swift Package

In Xcode:
1. File -> Add Package Dependencies
2. Enter: `https://github.com/user/tano.git`
3. Select the `Tano` library (includes everything)

Or add to your `Package.swift`:
```swift
dependencies: [
    .package(url: "https://github.com/user/tano.git", from: "0.1.0")
]
```

## 2. Add Your Server Script

Create `server.js` in your app bundle:
```javascript
const server = Bun.serve({
    port: 18899,
    fetch(req) {
        const url = new URL(req.url);
        if (url.pathname === '/api/hello') {
            return Response.json({ message: 'Hello from Tano!' });
        }
        return new Response('Not Found', { status: 404 });
    }
});
```

## 3. Start the Runtime

```swift
import Tano

// In your App or ViewController
let runtime = TanoRuntime(config: TanoConfig(
    serverEntry: Bundle.main.path(forResource: "server", ofType: "js")!
))
runtime.start()
```

## 4. Add the WebView (Optional)

```swift
import SwiftUI

struct MyTanoView: View {
    let pluginRouter = PluginRouter()

    init() {
        pluginRouter.register(plugin: SQLitePlugin())
        pluginRouter.register(plugin: ClipboardPlugin())
    }

    var body: some View {
        TanoWebView(
            config: TanoWebViewConfig(serverPort: 18899),
            pluginRouter: pluginRouter
        )
    }
}
```

## 5. Call Plugins from Your Web App

```javascript
// In your web app's JavaScript
const result = await window.Tano.invoke('clipboard', 'copy', { text: 'Hello!' });
const data = await fetch('/api/hello').then(r => r.json());
```

That's it! Your existing iOS app now has an on-device server and plugin bridge.
