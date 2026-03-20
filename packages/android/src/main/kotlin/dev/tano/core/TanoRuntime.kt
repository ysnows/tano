package dev.tano.core

import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.util.Log

/**
 * TanoJSC runtime for Android.
 *
 * Manages a JavaScriptCore context on a dedicated background thread.
 * Mirrors the iOS TanoRuntime but uses Android-specific APIs:
 * - [HandlerThread] + [Handler] instead of Thread + CFRunLoop
 * - [performOnJSCThread] posts work via [Handler.post]
 *
 * Note: The actual JSC embedding requires jsc-android or the JNI bridge
 * from the existing edge_embed library. This class provides the Kotlin API
 * that wraps the native layer.
 */
class TanoRuntime(val config: TanoConfig) {

    companion object {
        private const val TAG = "TanoRuntime"

        init {
            System.loadLibrary("edge_embed")
        }

        @Volatile
        private var processInitialized = false
    }

    // -- State --

    enum class State {
        IDLE, STARTING, RUNNING, STOPPING, STOPPED, ERROR;

        override fun toString(): String = name.lowercase()
    }

    @Volatile
    var state: State = State.IDLE
        private set

    var errorMessage: String? = null
        private set

    // -- Threading --

    private var runtimeThread: HandlerThread? = null
    private var handler: Handler? = null

    // -- Native JNI declarations --

    private external fun nativeInit(): Int
    private external fun nativeStart(scriptPath: String): Int
    private external fun nativeStop()
    private external fun nativeIsRunning(): Boolean

    // -- Lifecycle --

    /**
     * Spawn the dedicated background thread, initialize the native runtime
     * if needed, and evaluate the server entry script.
     */
    fun start() {
        if (state == State.RUNNING || state == State.STARTING) {
            Log.w(TAG, "Runtime already running or starting.")
            return
        }

        state = State.STARTING
        errorMessage = null

        val thread = HandlerThread("dev.tano.runtime").apply {
            start()
        }
        runtimeThread = thread
        handler = Handler(thread.looper)

        handler?.post {
            // One-time process init
            if (!processInitialized) {
                val status = nativeInit()
                if (status != 0) {
                    Log.e(TAG, "nativeInit failed: $status")
                    state = State.ERROR
                    errorMessage = "nativeInit failed with status $status"
                    return@post
                }
                processInitialized = true
            }

            // Start the JS runtime with the entry script
            if (config.serverEntry.isNotEmpty()) {
                val file = java.io.File(config.serverEntry)
                if (!file.exists()) {
                    state = State.ERROR
                    errorMessage = "Entry script not found: ${config.serverEntry}"
                    Log.e(TAG, errorMessage!!)
                    return@post
                }

                val status = nativeStart(config.serverEntry)
                if (status != 0) {
                    state = State.ERROR
                    errorMessage = "nativeStart failed with status $status"
                    Log.e(TAG, errorMessage!!)
                    return@post
                }
            }

            state = State.RUNNING
            Log.i(TAG, "Runtime started.")
        }
    }

    /**
     * Stop the runtime and clean up the background thread.
     * Safe to call from any thread.
     */
    fun stop() {
        if (state != State.RUNNING) {
            Log.w(TAG, "Runtime not running, ignoring stop.")
            return
        }

        state = State.STOPPING
        Log.i(TAG, "Requesting shutdown...")

        handler?.post {
            nativeStop()

            runtimeThread?.quitSafely()
            runtimeThread = null
            handler = null

            state = State.STOPPED
            Log.i(TAG, "Shutdown complete.")
        }
    }

    /**
     * Schedule a block to execute on the JSC runtime thread.
     *
     * This is the primary mechanism for other threads to interact
     * with the JSContext safely. JSC contexts are not thread-safe,
     * so all evaluation and value access must go through this method.
     */
    fun performOnJSCThread(block: Runnable) {
        val h = handler
        if (h == null) {
            Log.w(TAG, "performOnJSCThread called but handler not ready")
            return
        }
        h.post(block)
    }

    /**
     * Check if the native runtime is currently active.
     */
    fun isRunning(): Boolean {
        return state == State.RUNNING && nativeIsRunning()
    }
}

/**
 * Configuration for the Tano runtime.
 *
 * @param serverEntry Path to the JavaScript entry file.
 * @param env Environment variables exposed to the JS context.
 * @param dataPath Writable data path (e.g. for caches or databases).
 */
data class TanoConfig(
    val serverEntry: String,
    val env: Map<String, String> = emptyMap(),
    val dataPath: String = ""
)
