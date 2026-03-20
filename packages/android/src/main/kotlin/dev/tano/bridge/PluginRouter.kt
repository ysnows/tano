package dev.tano.bridge

import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/**
 * Routes incoming bridge messages to registered [TanoPlugin] handlers.
 *
 * Messages are dispatched based on the `plugin` and `method` fields.
 * If no matching plugin is found, or the plugin does not handle the
 * given method, an error is returned through the respond callback.
 *
 * Thread-safe: plugin registration and lookup are synchronized.
 *
 * Mirrors the iOS PluginRouter.
 */
class PluginRouter {

    companion object {
        private const val TAG = "PluginRouter"
    }

    /** Registered plugins keyed by their name. */
    private val plugins = mutableMapOf<String, TanoPlugin>()

    /** Coroutine scope for dispatching plugin calls. */
    private val scope = CoroutineScope(Dispatchers.IO)

    // -- Registration --

    /**
     * Register a plugin for handling bridge messages.
     *
     * If a plugin with the same name is already registered, it will be replaced.
     */
    @Synchronized
    fun register(plugin: TanoPlugin) {
        plugins[plugin.name] = plugin
    }

    /**
     * Unregister a plugin by name.
     */
    @Synchronized
    fun unregister(name: String) {
        plugins.remove(name)
    }

    /**
     * Check whether a plugin is registered for the given name.
     */
    @Synchronized
    fun hasPlugin(name: String): Boolean {
        return plugins.containsKey(name)
    }

    // -- Routing --

    /**
     * Route an incoming message to the appropriate plugin.
     *
     * Extracts `plugin`, `method`, and `params` from the message,
     * looks up the registered plugin, and calls its [TanoPlugin.handle] method.
     *
     * @param message The decoded bridge message dictionary.
     * @param respond Callback to send a result (or null) back to the caller.
     *                On error, the callback receives null.
     */
    fun handle(message: Map<String, Any?>, respond: (Any?) -> Unit) {
        val pluginName = message[TanoBridgeMessage.Keys.PLUGIN] as? String
        if (pluginName.isNullOrEmpty()) {
            Log.w(TAG, "Message missing 'plugin' field")
            respond(null)
            return
        }

        val method = message[TanoBridgeMessage.Keys.METHOD] as? String
        if (method.isNullOrEmpty()) {
            Log.w(TAG, "Message missing 'method' field")
            respond(null)
            return
        }

        val plugin: TanoPlugin?
        synchronized(this) {
            plugin = plugins[pluginName]
        }

        if (plugin == null) {
            Log.w(TAG, "No plugin registered for '$pluginName'")
            respond(null)
            return
        }

        @Suppress("UNCHECKED_CAST")
        val params = message[TanoBridgeMessage.Keys.PARAMS] as? Map<String, Any?> ?: emptyMap()

        scope.launch {
            try {
                val result = plugin.handle(method, params)
                respond(result)
            } catch (e: Exception) {
                Log.e(TAG, "Plugin '$pluginName' method '$method' threw: ${e.message}", e)
                respond(null)
            }
        }
    }
}
