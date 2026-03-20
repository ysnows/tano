package dev.tano.plugins

import android.content.Context
import android.content.Intent
import android.net.Uri
import dev.tano.bridge.TanoPlugin

/**
 * Native share-sheet plugin for Tano on Android.
 *
 * Presents the system share chooser via [Intent.ACTION_SEND].
 *
 * Supported methods: `share`.
 *
 * Mirrors the iOS SharePlugin.
 *
 * @param context Android Context needed to start the share Intent.
 */
class SharePlugin(private val context: Context) : TanoPlugin {

    override val name: String = "share"
    override val permissions: List<String> = emptyList()

    // -- Routing --

    override suspend fun handle(method: String, params: Map<String, Any?>): Any? {
        return when (method) {
            "share" -> share(params)
            else -> throw IllegalArgumentException("Unknown share plugin method: $method")
        }
    }

    // -- share --

    private fun share(params: Map<String, Any?>): Map<String, Any?> {
        val text = params["text"] as? String
            ?: throw IllegalArgumentException("Missing required parameter: text")
        val urlString = params["url"] as? String

        val shareText = if (urlString != null) "$text\n$urlString" else text

        val sendIntent = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, shareText)
        }

        val chooser = Intent.createChooser(sendIntent, null).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

        context.startActivity(chooser)

        return mapOf("success" to true)
    }
}
