<div align="center">

# Tano

### The mobile runtime for web apps

**Tano** is a cross-platform mobile framework that lets you build native iOS and Android apps using JavaScript/TypeScript and web technologies. Powered by an on-device [Bun](https://bun.sh)-compatible runtime with native system APIs.

**Integrate into existing iOS/Android projects or start fresh.**

[![iOS](https://img.shields.io/badge/iOS-15%2B-blue?logo=apple)](/)
[![Android](https://img.shields.io/badge/Android-API%2024%2B-green?logo=android)](/)
[![Bun](https://img.shields.io/badge/Bun-compatible-f472b6?logo=bun)](/)
[![License](https://img.shields.io/badge/license-MIT-blue)](/LICENSE)

</div>

---

## What is Tano?

Tano gives you a **full JavaScript/TypeScript server runtime running locally on the device**, a **WebView for UI**, and a **native bridge** for platform APIs. Think of it as bringing the power of Bun to mobile.

```
Your Web App (React, Vue, Next.js, Svelte, plain HTML)
       │ fetch() / WebSocket
       ▼
Bun-compatible Server (runs ON the device)
       │ UDS / native bridge
       ▼
Native APIs (camera, biometrics, SQLite, fs, crypto...)
```

Write your server in TypeScript with `Bun.serve()`. Write your UI with any web framework. Tano runs both on the device.

## Why Tano?

| | **Tano** | Tauri | React Native | Capacitor |
|---|----------|-------|-------------|-----------|
| **Platform** | **iOS + Android** | Desktop | Mobile | Mobile |
| **UI** | **WebView** (any framework) | WebView | Native views | WebView |
| **Runtime** | **Bun-compatible (on-device)** | Rust | Hermes JS | No runtime |
| **Server on device** | **Yes** (`Bun.serve()`) | No | No | No |
| **npm ecosystem** | **Yes** | N/A | Partial | Partial |
| **Native APIs** | **Plugin system** | Rust FFI | Bridge modules | Capacitor plugins |
| **Integrate existing app** | **Yes** | No | Partial | Yes |
| **App size** | **~15MB** | ~3MB | ~30MB | ~5MB |

### What makes Tano unique

- **On-device server**: Your app has a real HTTP server running locally. Your WebView talks to it via `fetch()`. This is the same architecture you use in web development — no new paradigms to learn.
- **Bun-compatible**: Write standard `Bun.serve()`, `Bun.file()`, use npm packages. Develop with real Bun on your machine, deploy to TanoJSC runtime on device.
- **Framework agnostic**: Use React, Vue, Svelte, Next.js (static export), Astro, or plain HTML. If it builds to static files, it works.
- **Drop into existing apps**: Add Tano to your existing Swift/Kotlin project as a library. No need to rewrite your app.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     DEVELOPMENT                              │
│                                                              │
│  Your Machine                       iOS Simulator            │
│  ┌──────────────┐   hot reload   ┌──────────────────┐      │
│  │  Bun (stock)  │ ──── WS ────→ │  WebView          │      │
│  │  dev server   │               │  HMR client       │      │
│  │  file watch   │←── fetch ──── │  bridge.js        │      │
│  └──────────────┘                └──────────────────┘      │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                     PRODUCTION (on device)                    │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Native Shell (Swift / Kotlin)                        │   │
│  │                                                        │   │
│  │  ┌─────────────┐    UDS     ┌──────────────────────┐  │   │
│  │  │ TanoJSC     │◄─JobTalk─►│  Native Plugins       │  │   │
│  │  │ Runtime     │           │  sqlite, camera,      │  │   │
│  │  │             │           │  biometrics, fs...     │  │   │
│  │  │ Bun.serve() │           └──────────────────────┘  │   │
│  │  │ Bun.file()  │                                      │   │
│  │  │ fetch, WS   │     HTTP localhost                   │   │
│  │  └──────┬──────┘          │                           │   │
│  │         └────────────┬────┘                           │   │
│  │                      ▼                                │   │
│  │  ┌──────────────────────────────────────────────┐    │   │
│  │  │  WebView (your web app)                       │    │   │
│  │  │  React / Vue / Next.js / Svelte / HTML        │    │   │
│  │  └──────────────────────────────────────────────┘    │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Quick Start

### Create a new app

```bash
# Install CLI
bun add -g @tano/cli

# Create project
tano create my-app
cd my-app

# Start development (opens iOS simulator)
tano dev
```

### Integrate into existing iOS project

```swift
// AppDelegate.swift or any SwiftUI view
import Tano

// Initialize Tano runtime
let tano = TanoRuntime(config: .init(
    serverEntry: Bundle.main.path(forResource: "server", ofType: "js")!,
    webEntry: Bundle.main.path(forResource: "index", ofType: "html", inDirectory: "web")!,
    plugins: [SqlitePlugin(), BiometricsPlugin(), ClipboardPlugin()]
))

// Add TanoWebView to your view hierarchy
struct ContentView: View {
    var body: some View {
        TanoWebView(runtime: tano)
    }
}
```

### Integrate into existing Android project

```kotlin
// build.gradle.kts
dependencies {
    implementation("dev.tano:core:0.1.0")
    implementation("dev.tano:webview:0.1.0")
    implementation("dev.tano:plugin-sqlite:0.1.0")
}
```

```kotlin
// MainActivity.kt
import dev.tano.core.TanoRuntime
import dev.tano.webview.TanoWebView

val tano = TanoRuntime(
    serverEntry = "server.js",
    plugins = listOf(SqlitePlugin(), BiometricsPlugin())
)

// In your Compose UI
@Composable
fun MyScreen() {
    TanoWebView(runtime = tano)
}
```

## Write Your App

### Server (runs on device via TanoJSC)

```typescript
// src/server/index.ts
import { sqlite } from '@tano/plugin-sqlite'

const db = await sqlite.open('app.db')
await db.run('CREATE TABLE IF NOT EXISTS todos (id INTEGER PRIMARY KEY, text TEXT, done INTEGER)')

export default Bun.serve({
    port: 18899,
    async fetch(req) {
        const url = new URL(req.url)

        if (url.pathname === '/api/todos') {
            return Response.json(await db.query('SELECT * FROM todos'))
        }

        if (url.pathname === '/api/todos' && req.method === 'POST') {
            const { text } = await req.json()
            await db.run('INSERT INTO todos (text, done) VALUES (?, 0)', [text])
            return Response.json({ ok: true })
        }

        // Serve static web files
        return new Response(Bun.file(`./web${url.pathname}`))
    }
})
```

### UI (any web framework)

```html
<!-- src/web/index.html -->
<div id="app"></div>
<script>
    // Just standard fetch — your server runs on the same device
    const todos = await fetch('/api/todos').then(r => r.json())
</script>
```

Or use React, Vue, Next.js — whatever you prefer:

```typescript
// src/web/App.tsx (React + Vite example)
import { invoke } from '@tano/bridge'

function App() {
    const [todos, setTodos] = useState([])

    useEffect(() => {
        fetch('/api/todos').then(r => r.json()).then(setTodos)
    }, [])

    const authenticate = async () => {
        await invoke('biometrics', 'authenticate', { reason: 'Confirm action' })
    }

    return <div>{todos.map(t => <p key={t.id}>{t.text}</p>)}</div>
}
```

## Configuration

```typescript
// tano.config.ts
import { defineConfig } from '@tano/cli'

export default defineConfig({
    app: {
        name: 'My App',
        identifier: 'com.example.myapp',
        version: '1.0.0',
    },
    server: {
        entry: './src/server/index.ts',
    },
    web: {
        entry: './src/web/index.html',
        // framework: 'vite',     // or 'next', or omit for plain HTML
    },
    plugins: [
        '@tano/plugin-sqlite',
        '@tano/plugin-biometrics',
        '@tano/plugin-clipboard',
    ],
    ios: { deploymentTarget: '15.0' },
    android: { minSdk: 24 },
})
```

## Plugins

| Plugin | Description | iOS | Android |
|--------|------------|-----|---------|
| `@tano/plugin-sqlite` | SQLite database | ✅ | ✅ |
| `@tano/plugin-clipboard` | Copy/paste | ✅ | ✅ |
| `@tano/plugin-biometrics` | Face ID / fingerprint | ✅ | ✅ |
| `@tano/plugin-haptics` | Haptic feedback | ✅ | ✅ |
| `@tano/plugin-camera` | Camera & photo picker | ✅ | ✅ |
| `@tano/plugin-fs` | File system access | ✅ | ✅ |
| `@tano/plugin-crypto` | Encryption & hashing | ✅ | ✅ |
| `@tano/plugin-keychain` | Secure storage | ✅ | ✅ |
| `@tano/plugin-share` | Share sheet | ✅ | ✅ |
| `@tano/plugin-notifications` | Local notifications | ✅ | ✅ |
| `@tano/plugin-http` | Native HTTP (URLSession/OkHttp) | ✅ | ✅ |

### Create a plugin

```bash
tano plugin create my-plugin
```

```
@tano/plugin-my-plugin/
├── src/
│   ├── index.ts              # JS API
│   ├── ios/MyPlugin.swift    # Native iOS
│   └── android/MyPlugin.kt  # Native Android
└── tano-plugin.json          # Manifest
```

## CLI

```bash
tano create <name>              # New project (templates: default, react, vue, next)
tano dev                        # Dev server + iOS simulator
tano dev --android              # Dev server + Android emulator
tano build ios                  # Production iOS build
tano build android              # Production Android build
tano run ios                    # Build + run on simulator
tano run android                # Build + run on emulator
tano plugin add <name>          # Install plugin
tano plugin create <name>       # Scaffold plugin
tano doctor                     # Check environment
```

## How It Works

### Development Mode
1. **Bun** (stock, on your machine) runs the dev server with hot reload
2. **iOS Simulator** loads the WebView pointing to `localhost`
3. Edit server code → Bun re-bundles → TanoJSC hot-reloads
4. Edit web code → HMR pushes to WebView → instant update

### Production Mode
1. **Bun bundler** compiles `src/server/` → `dist/server.js`
2. **Vite/Next/etc** builds `src/web/` → `dist/web/`
3. **Xcode/Gradle** compiles native shell + TanoJSC runtime + plugins
4. Bundled assets embedded in `.app` / `.apk`
5. On device: TanoJSC runs `server.js`, WebView loads `web/index.html`

### TanoJSC Runtime
A lightweight JavaScriptCore-based runtime that implements Bun-compatible APIs on device:
- `Bun.serve()` — HTTP server
- `Bun.file()` / `Bun.write()` — File I/O
- `fetch` / `WebSocket` — Networking (via native URLSession/OkHttp)
- `console.*` — Native logging (OSLog/Logcat)
- Plugin bridge via `@tano/bridge` → UDS → native Swift/Kotlin

JSC runs on both iOS (native) and Android (embedded), keeping the engine consistent across platforms.

## Project Structure

```
tano/
├── packages/
│   ├── core/                   # TanoJSC runtime (JSC + Bun API shims) — 40 tests
│   ├── bridge/                 # IPC protocol (UDS, FrameCodec, PluginRouter) — 29 tests
│   ├── webview/                # WebView container (WKWebView + bridge.js) — 41 tests
│   ├── cli/                    # tano CLI (create, dev, build, run, doctor)
│   └── plugins/                # 11 official plugins — 57 tests
│       ├── sqlite/             #   SQLite database
│       ├── clipboard/          #   Copy/paste
│       ├── haptics/            #   Haptic feedback
│       ├── keychain/           #   Key-value storage
│       ├── fs/                 #   File system
│       ├── crypto/             #   Encryption & hashing
│       ├── biometrics/         #   Face ID / Touch ID
│       ├── share/              #   Share sheet
│       ├── notifications/      #   Local notifications
│       ├── http/               #   Native HTTP client
│       └── camera/             #   Camera & photo picker
├── examples/
│   ├── ios-demo/               # Original EdgeJS demo (reference)
│   ├── android-demo/           # Original Android demo (reference)
│   └── tano-demo/              # New Tano demo app (all plugins wired)
├── docs/                       # Architecture & design docs
├── mission_control/            # Roadmap, tasks & progress logs
└── refs/                       # Reference repos (bun, electrobun)
```

## References

Built with inspiration from:
- [Bun](https://bun.sh) — JavaScript runtime (API compatibility target)
- [Electrobun](https://github.com/nicklockwood/iVersion) — Desktop Bun framework (architecture reference)
- [Tauri](https://tauri.app/) — WebView + native backend philosophy
- [Capacitor](https://capacitorjs.com/) — Plugin system inspiration

## License

MIT

## Contributing

Tano is in active development. See [mission_control/](./mission_control/) for the current roadmap and tasks.
