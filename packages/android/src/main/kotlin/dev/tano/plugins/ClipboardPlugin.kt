package dev.tano.plugins

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import dev.tano.bridge.TanoPlugin

/**
 * Native clipboard plugin for Tano on Android.
 *
 * Provides copy/read operations via the [TanoPlugin] interface.
 * Uses [android.content.ClipboardManager] for clipboard access.
 *
 * Supported methods: `copy`, `read`.
 *
 * Mirrors the iOS ClipboardPlugin.
 *
 * @param context Android Context needed to access the ClipboardManager system service.
 */
class ClipboardPlugin(private val context: Context) : TanoPlugin {

    override val name: String = "clipboard"
    override val permissions: List<String> = emptyList()

    private val clipboardManager: ClipboardManager
        get() = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager

    // -- Routing --

    override suspend fun handle(method: String, params: Map<String, Any?>): Any? {
        return when (method) {
            "copy" -> copyText(params)
            "read" -> readText()
            else -> throw IllegalArgumentException("Unknown clipboard plugin method: $method")
        }
    }

    // -- copy --

    private fun copyText(params: Map<String, Any?>): Map<String, Any?> {
        val text = params["text"] as? String ?: ""
        val clip = ClipData.newPlainText("Tano", text)
        clipboardManager.setPrimaryClip(clip)
        return mapOf("success" to true)
    }

    // -- read --

    private fun readText(): Map<String, Any?> {
        val clip = clipboardManager.primaryClip
        val text = if (clip != null && clip.itemCount > 0) {
            clip.getItemAt(0).text?.toString()
        } else {
            null
        }

        return mapOf("text" to text)
    }
}
