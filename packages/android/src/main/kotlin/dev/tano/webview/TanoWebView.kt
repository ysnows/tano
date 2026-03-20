package dev.tano.webview

import android.annotation.SuppressLint
import android.content.Context
import android.util.AttributeSet
import android.util.Log
import android.webkit.JavascriptInterface
import android.webkit.WebView
import android.webkit.WebViewClient
import dev.tano.bridge.PluginRouter
import dev.tano.bridge.TanoBridgeMessage
import org.json.JSONObject

/**
 * Android WebView with Tano bridge injection.
 *
 * Automatically injects the `window.Tano` JavaScript bridge at page start
 * and routes `invoke()` calls to the native [PluginRouter].
 *
 * Uses [addJavascriptInterface] to expose `TanoAndroid.invoke()` to JavaScript,
 * and [evaluateJavascript] to call back into the WebView for resolving/rejecting
 * promises and emitting events.
 *
 * Mirrors the iOS TanoWebView + TanoMessageHandler.
 */
@SuppressLint("SetJavaScriptEnabled")
class TanoWebView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : WebView(context, attrs, defStyleAttr) {

    companion object {
        private const val TAG = "TanoWebView"
    }

    /**
     * The plugin router for dispatching invoke calls to registered plugins.
     * Set this before loading a URL to ensure plugins are available.
     */
    var pluginRouter: PluginRouter? = null

    /**
     * Callback for fire-and-forget events sent via `window.Tano.send()`.
     */
    var onEvent: ((event: String, data: Map<String, Any?>) -> Unit)? = null

    init {
        settings.javaScriptEnabled = true
        settings.domStorageEnabled = true
        settings.allowFileAccess = true

        // Expose the TanoAndroid JavaScript interface
        addJavascriptInterface(TanoBridge(), "TanoAndroid")

        // Inject the bridge JS at page start
        webViewClient = object : WebViewClient() {
            override fun onPageStarted(
                view: WebView?,
                url: String?,
                favicon: android.graphics.Bitmap?
            ) {
                super.onPageStarted(view, url, favicon)
                view?.evaluateJavascript(TanoBridgeJS.script, null)
            }
        }
    }

    // -- Public API --

    /**
     * Resolve a pending invoke in the WebView with a successful result.
     *
     * Must be called on the main thread.
     */
    fun resolveInWebView(callId: String, result: Any?) {
        val jsonResult: String = when {
            result == null -> "null"
            result is Map<*, *> || result is List<*> -> {
                try {
                    if (result is Map<*, *>) {
                        JSONObject(result as Map<*, *>).toString()
                    } else {
                        org.json.JSONArray(result as List<*>).toString()
                    }
                } catch (e: Exception) {
                    val escaped = result.toString()
                        .replace("\\", "\\\\")
                        .replace("\"", "\\\"")
                    "\"$escaped\""
                }
            }
            result is Number || result is Boolean -> result.toString()
            else -> {
                val escaped = result.toString()
                    .replace("\\", "\\\\")
                    .replace("\"", "\\\"")
                "\"$escaped\""
            }
        }

        val escapedCallId = callId.replace("'", "\\'")
        val js = "window.Tano._resolve('$escapedCallId', $jsonResult)"
        post { evaluateJavascript(js, null) }
    }

    /**
     * Reject a pending invoke in the WebView with an error message.
     *
     * Must be called on the main thread.
     */
    fun rejectInWebView(callId: String, error: String) {
        val escapedCallId = callId.replace("'", "\\'")
        val escapedError = error
            .replace("\\", "\\\\")
            .replace("'", "\\'")
            .replace("\n", "\\n")
            .replace("\r", "\\r")
        val js = "window.Tano._reject('$escapedCallId', '$escapedError')"
        post { evaluateJavascript(js, null) }
    }

    /**
     * Emit an event to the WebView's event listeners.
     *
     * Must be called on the main thread.
     */
    fun emitEventInWebView(event: String, data: Map<String, Any?>) {
        val jsonString: String
        try {
            jsonString = JSONObject(data).toString()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to serialize event data for '$event'")
            return
        }

        val escapedEvent = event
            .replace("\\", "\\\\")
            .replace("'", "\\'")
        val js = "window.Tano._emit('$escapedEvent', $jsonString)"
        post { evaluateJavascript(js, null) }
    }

    // -- JavaScript Interface --

    /**
     * Inner class exposed to JavaScript via addJavascriptInterface.
     *
     * JavaScript calls `TanoAndroid.invoke(jsonString)` which is routed
     * to the appropriate plugin handler.
     */
    private inner class TanoBridge {

        @JavascriptInterface
        fun invoke(jsonString: String) {
            try {
                val json = JSONObject(jsonString)
                val type = json.optString("type", "")

                when (type) {
                    "invoke" -> handleInvoke(json)
                    "event" -> handleEvent(json)
                    else -> Log.w(TAG, "Unknown message type from JS: $type")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to parse JS message: ${e.message}", e)
            }
        }

        private fun handleInvoke(json: JSONObject) {
            val callId = json.optString("callId", "")
            val plugin = json.optString("plugin", "")
            val method = json.optString("method", "")
            val params = jsonObjectToMap(json.optJSONObject("params") ?: JSONObject())

            val router = pluginRouter
            if (router == null) {
                rejectInWebView(callId, "No plugin router configured")
                return
            }

            val message = TanoBridgeMessage.request(
                callId = callId,
                plugin = plugin,
                method = method,
                params = params
            )

            router.handle(message) { result ->
                if (result != null) {
                    resolveInWebView(callId, result)
                } else {
                    rejectInWebView(callId, "Plugin '$plugin' failed to handle '$method'")
                }
            }
        }

        private fun handleEvent(json: JSONObject) {
            val event = json.optString("event", "")
            val data = jsonObjectToMap(json.optJSONObject("data") ?: JSONObject())
            onEvent?.invoke(event, data)
        }

        private fun jsonObjectToMap(json: JSONObject): Map<String, Any?> {
            val map = mutableMapOf<String, Any?>()
            val keys = json.keys()
            while (keys.hasNext()) {
                val key = keys.next()
                val value = json.get(key)
                map[key] = when (value) {
                    is JSONObject -> jsonObjectToMap(value)
                    is org.json.JSONArray -> jsonArrayToList(value)
                    JSONObject.NULL -> null
                    else -> value
                }
            }
            return map
        }

        private fun jsonArrayToList(array: org.json.JSONArray): List<Any?> {
            val list = mutableListOf<Any?>()
            for (i in 0 until array.length()) {
                val value = array.get(i)
                list.add(
                    when (value) {
                        is JSONObject -> jsonObjectToMap(value)
                        is org.json.JSONArray -> jsonArrayToList(value)
                        JSONObject.NULL -> null
                        else -> value
                    }
                )
            }
            return list
        }
    }
}
