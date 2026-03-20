# Task 007: Existing App Integration

**Status**: Next Up
**Phase**: 7 — Existing App Integration
**Priority**: High (key differentiator — drop Tano into existing apps)

## Goal

Package Tano as a distributable library for both iOS (Swift Package / CocoaPod) and Android (Gradle dependency) so developers can add Tano to existing native projects with minimal code.

## Acceptance Criteria

- [ ] iOS: `TanoCore`, `TanoBridge`, `TanoWebView` as Swift Package with tag-based versioning
- [ ] iOS: Example integration in 3 lines of Swift
- [ ] Android: `dev.tano:core`, `dev.tano:webview` as AAR via Gradle
- [ ] Android: Example integration in 3 lines of Kotlin
- [ ] Documentation: "Add Tano to existing iOS project" guide
- [ ] Documentation: "Add Tano to existing Android project" guide
- [ ] Minimal example project for each platform

## iOS Distribution

Swift Package Manager is already set up — each package at `packages/core/`, `packages/bridge/`, `packages/webview/` has a `Package.swift`. For distribution:
1. Create a root `Package.swift` that exposes all products
2. Tag releases with semver (v0.1.0)
3. Developers add via Xcode: File → Add Packages → GitHub URL

## Android Distribution

1. Create `packages/android/build.gradle.kts` with library configuration
2. Publish AAR to Maven Central or GitHub Packages
3. Developers add: `implementation("dev.tano:core:0.1.0")`

## Integration Example

### iOS (3 lines)
```swift
import TanoCore; import TanoWebView
let runtime = TanoRuntime(config: TanoConfig(serverEntry: "server.js"))
runtime.start()
// Add TanoWebView(config: ..., pluginRouter: ...) to your SwiftUI hierarchy
```

### Android (3 lines)
```kotlin
import dev.tano.core.TanoRuntime
val runtime = TanoRuntime(TanoConfig(serverEntry = "server.js"))
runtime.start()
// Add TanoWebView to your Compose/XML layout
```
