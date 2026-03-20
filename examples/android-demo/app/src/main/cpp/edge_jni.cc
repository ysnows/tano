/**
 * @file edge_jni.cc
 * @brief JNI bridge between Android/Kotlin and the Edge.js C embedding API.
 *
 * Exposes a thin native interface for EdgeJSManager.kt to call. Uses global
 * state to manage a single runtime instance -- only one Edge.js runtime can
 * be active at a time in this demo.
 *
 * Limitation: This JNI bridge maintains a single global runtime pointer. If
 * you need multiple concurrent runtimes, refactor to pass opaque handles
 * through JNI (e.g., via a jlong pointer).
 */

#include <jni.h>
#include <pthread.h>
#include <cstring>
#include <cstdlib>
#include <android/log.h>

#include "edge_embed.h"

#define LOG_TAG "EdgeJNI"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO,  LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// ---------------------------------------------------------------------------
// Global state (single runtime instance)
// ---------------------------------------------------------------------------

static EdgeRuntime* g_runtime    = nullptr;
static pthread_t    g_thread     = 0;
static bool         g_thread_active = false;
static int          g_exit_code  = 0;

// ---------------------------------------------------------------------------
// Background thread entry point
// ---------------------------------------------------------------------------

static void* runtime_thread_fn(void* arg) {
    EdgeRuntime* rt = static_cast<EdgeRuntime*>(arg);
    LOGI("Runtime thread started.");

    g_exit_code = EdgeRuntimeRun(rt);

    LOGI("Runtime thread exited with code %d.", g_exit_code);
    g_thread_active = false;
    return nullptr;
}

// ---------------------------------------------------------------------------
// Fatal error callback
// ---------------------------------------------------------------------------

static void on_fatal(const char* message, void* /* user_data */) {
    LOGE("FATAL: %s", message ? message : "(null)");
}

// ---------------------------------------------------------------------------
// JNI exports
// ---------------------------------------------------------------------------

extern "C" {

/**
 * One-time process initialization. Safe to call multiple times (internally
 * uses std::call_once).
 */
JNIEXPORT jint JNICALL
Java_com_edgejs_demo_EdgeJSManager_nativeInit(JNIEnv* /* env */,
                                               jobject /* thiz */) {
    EdgeStatus status = EdgeProcessInit();
    if (status != EDGE_OK) {
        LOGE("EdgeProcessInit failed: %d", static_cast<int>(status));
    } else {
        LOGI("EdgeProcessInit succeeded.");
    }
    return static_cast<jint>(status);
}

/**
 * Create a runtime and start it on a background thread.
 *
 * @param scriptPath  Absolute path to the JavaScript entry file.
 * @return 0 on success, non-zero EdgeStatus on failure.
 */
JNIEXPORT jint JNICALL
Java_com_edgejs_demo_EdgeJSManager_nativeStart(JNIEnv* env,
                                                jobject /* thiz */,
                                                jstring scriptPath) {
    if (g_runtime != nullptr && g_thread_active) {
        LOGE("Runtime already running.");
        return static_cast<jint>(EDGE_ERROR_ALREADY_RUNNING);
    }

    const char* path = env->GetStringUTFChars(scriptPath, nullptr);
    if (path == nullptr) {
        LOGE("Failed to get script path string.");
        return static_cast<jint>(EDGE_ERROR_SCRIPT_LOAD);
    }

    // Build config. EdgeRuntimeCreate copies all strings, so locals are fine.
    EdgeRuntimeConfig config;
    memset(&config, 0, sizeof(config));
    config.script_path    = path;
    config.extension_path = nullptr;
    config.socket_path    = nullptr;
    config.argc           = 0;
    config.argv           = nullptr;
    config.on_fatal       = on_fatal;
    config.user_data      = nullptr;

    g_runtime = EdgeRuntimeCreate(&config);

    env->ReleaseStringUTFChars(scriptPath, path);

    if (g_runtime == nullptr) {
        LOGE("EdgeRuntimeCreate returned NULL.");
        return static_cast<jint>(EDGE_ERROR_ENV_CREATE);
    }

    // Spawn a background thread to run the blocking event loop.
    g_thread_active = true;
    int rc = pthread_create(&g_thread, nullptr, runtime_thread_fn, g_runtime);
    if (rc != 0) {
        LOGE("pthread_create failed: %d", rc);
        EdgeRuntimeDestroy(g_runtime);
        g_runtime = nullptr;
        g_thread_active = false;
        return static_cast<jint>(EDGE_ERROR_INIT_FAILED);
    }

    LOGI("Runtime started on background thread.");
    return static_cast<jint>(EDGE_OK);
}

/**
 * Request graceful shutdown, wait for the background thread to finish,
 * and destroy the runtime.
 */
JNIEXPORT void JNICALL
Java_com_edgejs_demo_EdgeJSManager_nativeStop(JNIEnv* /* env */,
                                               jobject /* thiz */) {
    if (g_runtime == nullptr) {
        LOGI("No runtime to stop.");
        return;
    }

    LOGI("Requesting shutdown...");
    EdgeRuntimeShutdown(g_runtime);

    if (g_thread_active) {
        LOGI("Joining runtime thread...");
        pthread_join(g_thread, nullptr);
        g_thread_active = false;
    }

    EdgeRuntimeDestroy(g_runtime);
    g_runtime = nullptr;

    LOGI("Runtime destroyed. Exit code was %d.", g_exit_code);
}

/**
 * Query whether the runtime's event loop is currently active.
 */
JNIEXPORT jboolean JNICALL
Java_com_edgejs_demo_EdgeJSManager_nativeIsRunning(JNIEnv* /* env */,
                                                    jobject /* thiz */) {
    if (g_runtime == nullptr) {
        return JNI_FALSE;
    }
    return EdgeRuntimeIsRunning(g_runtime) != 0 ? JNI_TRUE : JNI_FALSE;
}

} // extern "C"
