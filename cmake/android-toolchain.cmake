# Android NDK cross-compilation toolchain
if(NOT DEFINED ANDROID_NDK AND DEFINED ENV{ANDROID_NDK_HOME})
    set(ANDROID_NDK "$ENV{ANDROID_NDK_HOME}")
endif()

if(NOT DEFINED ANDROID_NDK)
    message(FATAL_ERROR "ANDROID_NDK or ANDROID_NDK_HOME must be set")
endif()

# Must be set BEFORE including NDK toolchain
set(ANDROID_ABI "arm64-v8a" CACHE STRING "Android ABI")
set(ANDROID_PLATFORM "android-26" CACHE STRING "Minimum Android API level")
set(ANDROID_STL "c++_shared" CACHE STRING "Android STL")

include("${ANDROID_NDK}/build/cmake/android.toolchain.cmake")

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(EDGE_NAPI_PROVIDER "bundled-v8" CACHE STRING "N-API provider")
add_compile_definitions(EDGE_NO_FORK=1)

set(EDGE_BUILD_CLI OFF CACHE BOOL "" FORCE)
set(EDGE_BUILD_EMBED_LIB ON CACHE BOOL "" FORCE)
set(EDGE_EMBED_SHARED ON CACHE BOOL "" FORCE)
