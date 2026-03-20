package dev.tano.plugins

import android.content.Context
import dev.tano.bridge.TanoPlugin

/**
 * Native biometrics plugin for Tano on Android.
 *
 * Provides biometric authentication (fingerprint / face). Currently
 * implemented as a stub that always returns success, because real biometric
 * authentication requires a `FragmentActivity` context and UI interaction
 * via `androidx.biometric.BiometricPrompt`.
 *
 * A future version will integrate BiometricPrompt when an Activity reference
 * is available.
 *
 * Supported methods: `authenticate`.
 *
 * Mirrors the iOS BiometricsPlugin.
 *
 * @param context Android Context (FragmentActivity needed for real biometric prompts).
 */
class BiometricsPlugin(private val context: Context) : TanoPlugin {

    override val name: String = "biometrics"
    override val permissions: List<String> = listOf("biometrics")

    // -- Routing --

    override suspend fun handle(method: String, params: Map<String, Any?>): Any? {
        return when (method) {
            "authenticate" -> authenticate(params)
            else -> throw IllegalArgumentException("Unknown biometrics plugin method: $method")
        }
    }

    // -- authenticate --

    /**
     * Authenticates the user via biometrics.
     *
     * Currently a stub that always succeeds. Real implementation requires
     * a FragmentActivity to display the BiometricPrompt dialog.
     */
    private fun authenticate(params: Map<String, Any?>): Map<String, Any?> {
        val reason = params["reason"] as? String
            ?: throw IllegalArgumentException("Missing required parameter: reason")

        // TODO: Integrate BiometricPrompt when Activity reference is available.
        // val executor = ContextCompat.getMainExecutor(context)
        // val prompt = BiometricPrompt(activity, executor, callback)
        // val promptInfo = BiometricPrompt.PromptInfo.Builder()
        //     .setTitle("Authentication")
        //     .setSubtitle(reason)
        //     .setNegativeButtonText("Cancel")
        //     .build()
        // prompt.authenticate(promptInfo)

        // Stub: always return success
        return mapOf("success" to true)
    }
}
