package com.edgejs.demo

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * Kotlin wrapper around the Edge.js JNI bridge.
 *
 * Provides reactive [StateFlow] properties for observing runtime state from
 * Compose UI. All JNI calls are dispatched on [Dispatchers.IO].
 *
 * **Limitation:** Only one runtime instance is supported at a time (the JNI
 * layer uses global state).
 */
class EdgeJSManager {

    companion object {
        init {
            System.loadLibrary("edge_embed")
        }

        /** Has [nativeInit] been called successfully? */
        @Volatile
        private var processInitialized = false
    }

    // -- Reactive state --

    private val _isRunning = MutableStateFlow(false)
    val isRunning: StateFlow<Boolean> = _isRunning.asStateFlow()

    private val _lastOutput = MutableStateFlow("")
    val lastOutput: StateFlow<String> = _lastOutput.asStateFlow()

    private val scope = CoroutineScope(Dispatchers.IO)

    // -- Public API --

    /**
     * Initialize the Edge.js process (once per app) and start the runtime
     * with the given JavaScript entry script.
     *
     * @param scriptPath Absolute filesystem path to the `.js` file.
     */
    fun start(scriptPath: String) {
        scope.launch {
            if (_isRunning.value) {
                appendOutput("[EdgeJSManager] Already running.")
                return@launch
            }

            // One-time process init.
            if (!processInitialized) {
                val status = nativeInit()
                if (status != 0) {
                    appendOutput("[EdgeJSManager] nativeInit failed: $status")
                    return@launch
                }
                processInitialized = true
            }

            val status = nativeStart(scriptPath)
            if (status != 0) {
                appendOutput("[EdgeJSManager] nativeStart failed: $status")
                return@launch
            }

            _isRunning.value = true
            appendOutput("[EdgeJSManager] Runtime started.")

            // Poll until the runtime stops (simple approach for demo).
            while (nativeIsRunning()) {
                delay(250)
            }

            _isRunning.value = false
            appendOutput("[EdgeJSManager] Runtime stopped.")
        }
    }

    /**
     * Request graceful shutdown. Safe to call from any thread.
     */
    fun stop() {
        scope.launch {
            appendOutput("[EdgeJSManager] Requesting shutdown...")
            nativeStop()
            _isRunning.value = false
            appendOutput("[EdgeJSManager] Shutdown complete.")
        }
    }

    // -- JNI declarations --

    private external fun nativeInit(): Int
    private external fun nativeStart(scriptPath: String): Int
    private external fun nativeStop()
    private external fun nativeIsRunning(): Boolean

    // -- Helpers --

    private fun appendOutput(text: String) {
        _lastOutput.value = text
    }
}
