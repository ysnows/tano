# Edge.js Android Demo

Minimal Android app demonstrating how to embed the Edge.js runtime using the
C embedding API (`edge_embed.h`) via JNI.

## Project Structure

```
android-demo/
  app/src/main/
    cpp/
      edge_jni.cc              -- JNI bridge to edge_embed.h
    java/com/edgejs/demo/
      EdgeJSManager.kt         -- Kotlin wrapper with StateFlow
      MainActivity.kt          -- Jetpack Compose UI
    assets/js/
      hello.js                 -- UDS echo server test script
```

## Prerequisites

- Android Studio Hedgehog (2023.1) or later
- Android NDK r25+ (install via SDK Manager)
- `libedge_embed.so` built for target ABIs (arm64-v8a, armeabi-v7a, x86_64)

## Build Steps

1. Create a new Android Studio project (Empty Compose Activity, min SDK 26).

2. Copy the source files from this directory into the project, preserving the
   package structure.

3. Place the prebuilt `libedge_embed.so` files in the jniLibs directory:
   ```
   app/src/main/jniLibs/
     arm64-v8a/libedge_embed.so
     armeabi-v7a/libedge_embed.so
     x86_64/libedge_embed.so
   ```

4. Add `edge_embed.h` to `app/src/main/cpp/` alongside `edge_jni.cc`.

5. Configure CMake in `app/build.gradle.kts`:
   ```kotlin
   android {
       // ...
       externalNativeBuild {
           cmake {
               path = file("src/main/cpp/CMakeLists.txt")
           }
       }
   }
   ```

6. Create `app/src/main/cpp/CMakeLists.txt`:
   ```cmake
   cmake_minimum_required(VERSION 3.22)
   project(edge_jni)

   add_library(edge_jni SHARED edge_jni.cc)

   # Link against the prebuilt libedge_embed.so
   add_library(edge_embed SHARED IMPORTED)
   set_target_properties(edge_embed PROPERTIES
       IMPORTED_LOCATION ${CMAKE_SOURCE_DIR}/../../../../jniLibs/${ANDROID_ABI}/libedge_embed.so
   )

   target_link_libraries(edge_jni edge_embed log)
   ```

7. Build and run on an emulator or device.

## Usage

Tap **Start** to launch the Edge.js runtime with `hello.js`. The status
indicator turns green while the runtime is active. Tap **Stop** to trigger
a graceful shutdown.

## Limitations

- Only one runtime instance is supported at a time (the JNI bridge uses
  global state). See the comment in `edge_jni.cc` for details.
- The `hello.js` script path is copied from assets to internal storage at
  first launch since the native runtime requires a filesystem path.
