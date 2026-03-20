# Plugin System

## Overview

Every native capability in Tano is a plugin. Plugins are self-contained packages with a TypeScript API, native iOS implementation (Swift), and native Android implementation (Kotlin).

## Plugin Structure

```
@tano/plugin-sqlite/
├── src/
│   ├── index.ts                    # JS API — what developers import
│   ├── ios/
│   │   └── SqlitePlugin.swift      # Native iOS implementation
│   └── android/
│       └── SqlitePlugin.kt         # Native Android implementation
├── tano-plugin.json                # Plugin manifest
└── package.json                    # npm package config
```

## Plugin Manifest

```json
{
    "name": "sqlite",
    "displayName": "SQLite Database",
    "version": "0.1.0",
    "description": "SQLite database access",
    "permissions": ["filesystem.app-data"],
    "ios": {
        "class": "SqlitePlugin",
        "source": "src/ios/SqlitePlugin.swift",
        "frameworks": ["libsqlite3"]
    },
    "android": {
        "class": "dev.tano.plugin.sqlite.SqlitePlugin",
        "source": "src/android/SqlitePlugin.kt",
        "dependencies": []
    }
}
```

## Native Protocol

### iOS (Swift)

```swift
public protocol TanoPlugin: AnyObject {
    /// Unique plugin name (matches JS import)
    static var name: String { get }

    /// Required permissions
    static var permissions: [String] { get }

    /// Called once when the plugin is registered
    func initialize(context: TanoPluginContext)

    /// Handle a method call from JS
    func handle(method: String, params: [String: Any],
                context: TaskContext) async throws -> Any?
}

/// Provided by the runtime
public protocol TanoPluginContext {
    var appDataPath: String { get }
    var cachePath: String { get }
    func log(_ message: String)
}

/// Base class with sensible defaults
open class TanoPluginBase: TanoPlugin {
    open class var name: String { fatalError("Subclass must implement") }
    open class var permissions: [String] { [] }
    open func initialize(context: TanoPluginContext) {}
    open func handle(method: String, params: [String: Any],
                     context: TaskContext) async throws -> Any? { nil }
}
```

### Android (Kotlin)

```kotlin
interface TanoPlugin {
    val name: String
    val permissions: List<String>

    fun initialize(context: TanoPluginContext)
    suspend fun handle(method: String, params: JSONObject,
                       context: TaskContext): Any?
}

interface TanoPluginContext {
    val appDataPath: String
    val cachePath: String
    fun log(message: String)
}
```

## Example: SQLite Plugin

### JS API

```typescript
// @tano/plugin-sqlite/src/index.ts
import { invoke } from '@tano/bridge'

export interface Database {
    query<T = any>(sql: string, params?: any[]): Promise<T[]>
    run(sql: string, params?: any[]): Promise<{ changes: number; lastInsertRowId: number }>
    close(): Promise<void>
}

export async function open(path: string): Promise<Database> {
    const handle = await invoke('sqlite', 'open', { path })

    return {
        async query(sql, params = []) {
            return invoke('sqlite', 'query', { handle, sql, params })
        },
        async run(sql, params = []) {
            return invoke('sqlite', 'run', { handle, sql, params })
        },
        async close() {
            return invoke('sqlite', 'close', { handle })
        }
    }
}
```

### Native iOS

```swift
// @tano/plugin-sqlite/src/ios/SqlitePlugin.swift
import SQLite3

class SqlitePlugin: TanoPluginBase {
    override class var name: String { "sqlite" }
    override class var permissions: [String] { ["filesystem.app-data"] }

    private var databases: [String: OpaquePointer] = [:]

    override func handle(method: String, params: [String: Any],
                         context: TaskContext) async throws -> Any? {
        switch method {
        case "open":
            let path = params["path"] as! String
            let fullPath = context.appDataPath + "/" + path
            var db: OpaquePointer?
            guard sqlite3_open(fullPath, &db) == SQLITE_OK else {
                throw TanoPluginError.native("Failed to open database")
            }
            let handle = UUID().uuidString
            databases[handle] = db
            return handle

        case "query":
            let handle = params["handle"] as! String
            let sql = params["sql"] as! String
            let args = params["params"] as? [Any] ?? []
            guard let db = databases[handle] else {
                throw TanoPluginError.native("Database not found")
            }
            return try executeQuery(db: db, sql: sql, params: args)

        case "run":
            let handle = params["handle"] as! String
            let sql = params["sql"] as! String
            let args = params["params"] as? [Any] ?? []
            guard let db = databases[handle] else {
                throw TanoPluginError.native("Database not found")
            }
            return try executeRun(db: db, sql: sql, params: args)

        case "close":
            let handle = params["handle"] as! String
            if let db = databases.removeValue(forKey: handle) {
                sqlite3_close(db)
            }
            return nil

        default:
            throw TanoPluginError.unknownMethod(method)
        }
    }
}
```

## Plugin Registration

### In tano.config.ts

```typescript
export default defineConfig({
    plugins: [
        '@tano/plugin-sqlite',          // official
        '@tano/plugin-biometrics',      // official
        'tano-plugin-stripe',           // community
        './plugins/my-custom-plugin',   // local
    ]
})
```

### What happens at build time

1. CLI reads `tano.config.ts`
2. For each plugin, reads `tano-plugin.json`
3. Copies Swift/Kotlin source into the native project
4. Generates plugin registry:

```swift
// Auto-generated: TanoPluginRegistry.swift
import Foundation

class TanoPluginRegistry {
    static func createAll() -> [TanoPlugin] {
        return [
            SqlitePlugin(),
            BiometricsPlugin(),
            ClipboardPlugin(),
        ]
    }
}
```

5. Adds required frameworks/dependencies to Xcode/Gradle
6. Generates permission entries in Info.plist / AndroidManifest.xml

## Permissions

Plugins declare required permissions in their manifest. The CLI maps these to platform-specific entries:

| Tano Permission | iOS (Info.plist) | Android (Manifest) |
|----------------|-----------------|-------------------|
| `camera` | NSCameraUsageDescription | android.permission.CAMERA |
| `location` | NSLocationWhenInUseUsageDescription | ACCESS_FINE_LOCATION |
| `biometrics` | NSFaceIDUsageDescription | USE_BIOMETRIC |
| `notifications` | (runtime request) | POST_NOTIFICATIONS |
| `filesystem.app-data` | (no declaration needed) | (no declaration needed) |
| `filesystem.photos` | NSPhotoLibraryUsageDescription | READ_MEDIA_IMAGES |
| `microphone` | NSMicrophoneUsageDescription | RECORD_AUDIO |

## Creating a Plugin

```bash
tano plugin create my-plugin
```

Generates:

```
@tano/plugin-my-plugin/
├── src/
│   ├── index.ts
│   ├── ios/MyPlugin.swift
│   └── android/MyPlugin.kt
├── tano-plugin.json
└── package.json
```

## Official Plugins

| Plugin | Status | Description |
|--------|--------|------------|
| `@tano/plugin-sqlite` | **Done** | open, query, run, close (7 tests) |
| `@tano/plugin-clipboard` | **Done** | copy, read (4 tests) |
| `@tano/plugin-haptics` | **Done** | impact, notification, selection (6 tests) |
| `@tano/plugin-keychain` | **Done** | set, get, delete (5 tests) |
| `@tano/plugin-fs` | **Done** | read, write, exists, delete, list, mkdir (7 tests) |
| `@tano/plugin-biometrics` | Planned | Face ID / fingerprint |
| `@tano/plugin-crypto` | Planned | Encryption & hashing |
| `@tano/plugin-camera` | Planned | Camera & photo picker |
| `@tano/plugin-share` | Planned | Share sheet |
| `@tano/plugin-notifications` | Planned | Local notifications |
| `@tano/plugin-http` | Planned | Native HTTP client |
