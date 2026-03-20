package dev.tano.plugins

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import dev.tano.bridge.TanoPlugin

/**
 * Native haptic feedback plugin for Tano on Android.
 *
 * Provides haptic feedback using [Vibrator] / [VibrationEffect] on Android.
 * On API 26+ uses VibrationEffect; on older devices falls back to the
 * deprecated `vibrate(long)` call.
 *
 * Supported methods: `impact`, `notification`, `selection`.
 *
 * Mirrors the iOS HapticsPlugin.
 *
 * @param context Android Context needed to access the Vibrator system service.
 */
class HapticsPlugin(private val context: Context) : TanoPlugin {

    override val name: String = "haptics"
    override val permissions: List<String> = emptyList()

    private val vibrator: Vibrator
        get() = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val manager = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
            manager.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }

    // -- Routing --

    override suspend fun handle(method: String, params: Map<String, Any?>): Any? {
        return when (method) {
            "impact" -> impact(params)
            "notification" -> notification(params)
            "selection" -> selection()
            else -> throw IllegalArgumentException("Unknown haptics plugin method: $method")
        }
    }

    // -- impact --

    private fun impact(params: Map<String, Any?>): Map<String, Any?> {
        val style = params["style"] as? String ?: "medium"

        val durationMs = when (style) {
            "light" -> 20L
            "medium" -> 40L
            "heavy" -> 60L
            else -> throw IllegalArgumentException("Invalid value '$style' for parameter 'style'")
        }

        vibrate(durationMs)
        return mapOf("success" to true)
    }

    // -- notification --

    private fun notification(params: Map<String, Any?>): Map<String, Any?> {
        val type = params["type"] as? String ?: "success"

        val durationMs = when (type) {
            "success" -> 30L
            "warning" -> 50L
            "error" -> 80L
            else -> throw IllegalArgumentException("Invalid value '$type' for parameter 'type'")
        }

        vibrate(durationMs)
        return mapOf("success" to true)
    }

    // -- selection --

    private fun selection(): Map<String, Any?> {
        vibrate(10L)
        return mapOf("success" to true)
    }

    // -- Helpers --

    private fun vibrate(durationMs: Long) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(
                VibrationEffect.createOneShot(durationMs, VibrationEffect.DEFAULT_AMPLITUDE)
            )
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(durationMs)
        }
    }
}
