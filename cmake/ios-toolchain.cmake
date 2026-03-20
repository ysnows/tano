# iOS cross-compilation toolchain for Edge.js
set(CMAKE_SYSTEM_NAME iOS)
set(CMAKE_SYSTEM_PROCESSOR arm64)

if(NOT DEFINED IOS_PLATFORM)
    set(IOS_PLATFORM "OS" CACHE STRING "iOS platform: OS or SIMULATOR")
endif()

if(IOS_PLATFORM STREQUAL "SIMULATOR")
    set(CMAKE_OSX_SYSROOT iphonesimulator)
    set(CMAKE_OSX_ARCHITECTURES "arm64;x86_64")
else()
    set(CMAKE_OSX_SYSROOT iphoneos)
    set(CMAKE_OSX_ARCHITECTURES arm64)
endif()

set(CMAKE_OSX_DEPLOYMENT_TARGET "15.0" CACHE STRING "Minimum iOS version")
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Use JSC as the N-API provider on iOS (system JavaScriptCore framework)
set(EDGE_NAPI_PROVIDER "bundled-jsc" CACHE STRING "N-API provider" FORCE)

# Disable features not available on iOS
add_compile_definitions(EDGE_NO_FORK=1)
add_compile_definitions(EDGE_NO_CHILD_PROCESS=1)

# Opt out of const napi_env in finalize callbacks — edge_process.cc uses
# non-const napi_env matching V8 convention. Without this, the JSC N-API
# headers typedef node_api_nogc_env as `const napi_env__*` causing type errors.
add_compile_definitions(NODE_API_EXPERIMENTAL_NOGC_ENV_OPT_OUT=1)

# Static library output
set(EDGE_BUILD_CLI OFF CACHE BOOL "Don't build CLI for iOS" FORCE)
set(EDGE_BUILD_EMBED_LIB ON CACHE BOOL "Build embedding library" FORCE)
