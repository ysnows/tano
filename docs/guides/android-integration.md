# Add Tano to an Existing Android Project

## 1. Add the Dependency

In your `build.gradle.kts`:
```kotlin
dependencies {
    implementation("dev.tano:core:0.1.0")
    implementation("dev.tano:webview:0.1.0")
    implementation("dev.tano:plugin-sqlite:0.1.0")
    // ... other plugins as needed
}
```

> Note: Tano Android packages are not yet published to Maven Central.
> For now, include the `packages/android/` source directly in your project.

## 2. Add Your Server Script

Place `server.js` in `app/src/main/assets/`:
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

```kotlin
import dev.tano.core.TanoRuntime
import dev.tano.core.TanoConfig

val runtime = TanoRuntime(TanoConfig(
    serverEntry = "server.js",
    env = mapOf("TANO_ENV" to "production")
))
runtime.start()
```

## 4. Add the WebView

```kotlin
import dev.tano.webview.TanoWebView
import dev.tano.bridge.PluginRouter
import dev.tano.plugins.SqlitePlugin
import dev.tano.plugins.ClipboardPlugin

val pluginRouter = PluginRouter()
pluginRouter.register(SqlitePlugin(context.filesDir.absolutePath))
pluginRouter.register(ClipboardPlugin(context))

// In your layout
val webView = TanoWebView(context).apply {
    this.pluginRouter = pluginRouter
    loadUrl("http://127.0.0.1:18899")
}
```

## 5. Call Plugins from Your Web App

```javascript
const result = await window.Tano.invoke('sqlite', 'open', { path: 'app.db' });
const hash = await window.Tano.invoke('crypto', 'hash', { algorithm: 'sha256', data: 'hello' });
```
