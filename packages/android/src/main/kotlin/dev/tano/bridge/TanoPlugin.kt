package dev.tano.bridge

/**
 * Interface for native plugins that handle bridge calls from JavaScript.
 *
 * Each plugin has a unique [name] used for routing. When JS sends a
 * message with `{ plugin: "myPlugin", method: "doThing", params: {...} }`,
 * the [PluginRouter] looks up the plugin by name and calls [handle].
 *
 * Plugins declare their required [permissions] (evaluated at registration time).
 *
 * Mirrors the iOS TanoPlugin protocol.
 */
interface TanoPlugin {

    /**
     * Unique plugin identifier used for message routing.
     */
    val name: String

    /**
     * Permissions this plugin requires (e.g., "clipboard", "network",
     * "filesystem.app-data").
     */
    val permissions: List<String>

    /**
     * Handle an incoming method call from JavaScript.
     *
     * @param method The method name to invoke.
     * @param params Arbitrary parameters from the JS caller.
     * @return An optional result that will be serialized back to JS.
     * @throws Exception Any error, which will be sent back as an error message.
     */
    suspend fun handle(method: String, params: Map<String, Any?>): Any?
}
