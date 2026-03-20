# Edge.js iOS Demo

Minimal iOS app demonstrating how to embed the Edge.js runtime using the C
embedding API (`edge_embed.h`).

## Project Structure

```
ios-demo/
  EdgeJS-Bridging-Header.h    -- Exposes edge_embed.h to Swift
  EdgeJSDemo/
    EdgeJSManager.swift        -- Runtime lifecycle manager (background thread)
    SocketBridge.swift         -- Unix domain socket client (JobTalk protocol)
    ContentView.swift          -- SwiftUI demo UI
  js/
    hello.js                   -- UDS echo server test script
```

## Prerequisites

- Xcode 15+ with iOS 16+ SDK
- EdgeJS.xcframework built from the Edge.js source tree (see `cmake/ios.toolchain.cmake`)

## Build Steps

1. Create a new Xcode project (iOS App, SwiftUI lifecycle).

2. Copy the files from this directory into the project.

3. Add `EdgeJS.xcframework` to your project:
   - Drag it into the Xcode project navigator.
   - In target Build Settings, add the framework's header directory to
     **Header Search Paths** (or place `edge_embed.h` where the bridging header
     can find it).

4. Set the **Objective-C Bridging Header** build setting to:
   ```
   $(SRCROOT)/EdgeJS-Bridging-Header.h
   ```

5. Copy `js/hello.js` into the app bundle:
   - Add it to the target's **Copy Bundle Resources** phase, preserving the
     `js/` folder reference.

6. Build and run on the iOS Simulator (or a physical device with the correct
   architecture slice in the xcframework).

## Usage

Tap **Start** to launch the Edge.js runtime with `hello.js`. The status
indicator turns green while the runtime is active. Tap **Stop** to trigger
a graceful shutdown via `EdgeRuntimeShutdown`.

The `SocketBridge` class shows how to connect to the UDS echo server started
by `hello.js` and exchange newline-delimited JSON messages.

## Limitations

- Only one runtime instance is supported at a time.
- App lifecycle hooks (`onBackground` / `onForeground`) are currently no-ops;
  future versions may pause/resume the event loop.
