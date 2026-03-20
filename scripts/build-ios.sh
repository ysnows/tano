#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_TYPE="${BUILD_TYPE:-Release}"
JOBS="${JOBS:-$(sysctl -n hw.ncpu)}"

echo "=== Building Edge.js for iOS device (arm64) ==="
cmake -S "$PROJECT_ROOT" -B "$PROJECT_ROOT/build-ios-device" \
    -DCMAKE_TOOLCHAIN_FILE="$PROJECT_ROOT/cmake/ios-toolchain.cmake" \
    -DIOS_PLATFORM=OS \
    -DCMAKE_BUILD_TYPE="$BUILD_TYPE"
cmake --build "$PROJECT_ROOT/build-ios-device" -j"$JOBS"

echo "=== Building Edge.js for iOS simulator (arm64 + x86_64) ==="
cmake -S "$PROJECT_ROOT" -B "$PROJECT_ROOT/build-ios-sim" \
    -DCMAKE_TOOLCHAIN_FILE="$PROJECT_ROOT/cmake/ios-toolchain.cmake" \
    -DIOS_PLATFORM=SIMULATOR \
    -DCMAKE_BUILD_TYPE="$BUILD_TYPE"
cmake --build "$PROJECT_ROOT/build-ios-sim" -j"$JOBS"

echo "=== Creating XCFramework ==="
xcodebuild -create-xcframework \
    -library "$PROJECT_ROOT/build-ios-device/libedge_embed.a" \
    -headers "$PROJECT_ROOT/src/edge_embed.h" \
    -library "$PROJECT_ROOT/build-ios-sim/libedge_embed.a" \
    -headers "$PROJECT_ROOT/src/edge_embed.h" \
    -output "$PROJECT_ROOT/build-ios/EdgeJS.xcframework"

echo "=== Done: build-ios/EdgeJS.xcframework ==="
