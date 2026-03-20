#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_TYPE="${BUILD_TYPE:-Release}"
JOBS="${JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || nproc)}"
ANDROID_NDK="${ANDROID_NDK:-${ANDROID_NDK_HOME:-}}"

if [ -z "$ANDROID_NDK" ]; then
    echo "error: ANDROID_NDK or ANDROID_NDK_HOME must be set" >&2
    exit 1
fi

echo "=== Building Edge.js for Android arm64-v8a ==="
cmake -S "$PROJECT_ROOT" -B "$PROJECT_ROOT/build-android" \
    -DCMAKE_TOOLCHAIN_FILE="$PROJECT_ROOT/cmake/android-toolchain.cmake" \
    -DANDROID_NDK="$ANDROID_NDK" \
    -DCMAKE_BUILD_TYPE="$BUILD_TYPE"
cmake --build "$PROJECT_ROOT/build-android" -j"$JOBS"

echo "=== Done: build-android/libedge_embed.so ==="
