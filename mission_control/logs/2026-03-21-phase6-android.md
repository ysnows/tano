# 2026-03-21 — Phase 6: Android Kotlin Port

## What was built

Ported the entire Tano framework API to Kotlin at `packages/android/` (12 files, ~1600 lines).

### Ported components

| iOS (Swift) | Android (Kotlin) | Mechanism |
|-------------|-----------------|-----------|
| TanoRuntime (Thread + CFRunLoop) | TanoRuntime (HandlerThread + Handler) | Handler.post() for performOnJSCThread |
| FrameCodec (Data) | FrameCodec (ByteBuffer BIG_ENDIAN) | Same 4-byte length prefix |
| TanoBridgeMessage | TanoBridgeMessage | Identical protocol |
| TanoPlugin protocol | TanoPlugin interface | suspend fun handle() |
| PluginRouter (NSLock) | PluginRouter (@Synchronized) | Same routing logic |
| BridgeManager | BridgeManager | LocalSocket instead of UDS CFSocket |
| TanoWebView (WKWebView) | TanoWebView (android.webkit.WebView) | addJavascriptInterface replaces WKScriptMessageHandler |
| TanoBridgeJS | TanoBridgeJS | Same JS, TanoAndroid.invoke() adapter |
| SQLitePlugin (sqlite3) | SqlitePlugin (SQLiteDatabase) | Android native SQLite |
| ClipboardPlugin (UIPasteboard) | ClipboardPlugin (ClipboardManager) | Android ClipboardManager |
| FSPlugin (FileManager) | FSPlugin (java.io.File) | Canonical path sandbox check |

## Remaining for Phase 6
- Gradle build config (build.gradle.kts)
- JSC integration (jsc-android or edge_embed JNI)
- CLI `tano build android` / `tano run android`
- End-to-end test on emulator
- Port remaining 8 plugins (haptics, keychain, crypto, biometrics, share, notifications, http, camera)
