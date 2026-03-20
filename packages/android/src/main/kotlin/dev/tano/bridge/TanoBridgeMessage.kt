package dev.tano.bridge

/**
 * Constants and builders for the Tano bridge messaging protocol.
 *
 * Messages are JSON dictionaries sent over the UDS bridge. Each message
 * has a `type` that describes its role in the request/response lifecycle,
 * along with routing fields (`plugin`, `method`) and a unique `callId`.
 *
 * Mirrors the iOS TanoBridgeMessage.
 */
object TanoBridgeMessage {

    // -- Keys --

    /** Dictionary keys used in bridge messages. */
    object Keys {
        /** The message type (see [Types]). */
        const val TYPE = "type"
        /** The method to invoke on the target plugin. */
        const val METHOD = "method"
        /** Unique identifier for matching request/response pairs. */
        const val CALL_ID = "callId"
        /** The target plugin name for routing. */
        const val PLUGIN = "plugin"
        /** Arbitrary parameters for the method call. */
        const val PARAMS = "params"
    }

    // -- Types --

    /** Message type constants. */
    object Types {
        /** JS to Native method call. */
        const val REQUEST = "request"
        /** Native to JS single response. */
        const val RESPONSE = "response"
        /** Native to JS streaming chunk. */
        const val RESPONSE_STREAM = "responseStream"
        /** Native to JS final stream chunk (signals completion). */
        const val RESPONSE_END = "responseEnd"
        /** Native to JS error response. */
        const val ERROR = "error"
        /** Bidirectional event (fire-and-forget). */
        const val EVENT = "event"
    }

    // -- Builders --

    /**
     * Build a request message dictionary.
     *
     * JS to Native method call.
     */
    fun request(
        callId: String,
        plugin: String,
        method: String,
        params: Map<String, Any?> = emptyMap()
    ): Map<String, Any?> = mapOf(
        Keys.TYPE to Types.REQUEST,
        Keys.CALL_ID to callId,
        Keys.PLUGIN to plugin,
        Keys.METHOD to method,
        Keys.PARAMS to params
    )

    /**
     * Build a response message dictionary.
     *
     * Native to JS single response.
     */
    fun response(
        callId: String,
        plugin: String,
        method: String,
        params: Map<String, Any?> = emptyMap()
    ): Map<String, Any?> = mapOf(
        Keys.TYPE to Types.RESPONSE,
        Keys.CALL_ID to callId,
        Keys.PLUGIN to plugin,
        Keys.METHOD to method,
        Keys.PARAMS to params
    )

    /**
     * Build a streaming response chunk.
     */
    fun responseStream(
        callId: String,
        plugin: String,
        method: String,
        params: Map<String, Any?> = emptyMap()
    ): Map<String, Any?> = mapOf(
        Keys.TYPE to Types.RESPONSE_STREAM,
        Keys.CALL_ID to callId,
        Keys.PLUGIN to plugin,
        Keys.METHOD to method,
        Keys.PARAMS to params
    )

    /**
     * Build a stream-end message.
     */
    fun responseEnd(
        callId: String,
        plugin: String,
        method: String,
        params: Map<String, Any?> = emptyMap()
    ): Map<String, Any?> = mapOf(
        Keys.TYPE to Types.RESPONSE_END,
        Keys.CALL_ID to callId,
        Keys.PLUGIN to plugin,
        Keys.METHOD to method,
        Keys.PARAMS to params
    )

    /**
     * Build an error message.
     */
    fun error(
        callId: String,
        plugin: String,
        method: String,
        errorMessage: String
    ): Map<String, Any?> = mapOf(
        Keys.TYPE to Types.ERROR,
        Keys.CALL_ID to callId,
        Keys.PLUGIN to plugin,
        Keys.METHOD to method,
        Keys.PARAMS to mapOf("error" to errorMessage)
    )

    /**
     * Build an event message (fire-and-forget).
     */
    fun event(
        plugin: String,
        method: String,
        params: Map<String, Any?> = emptyMap()
    ): Map<String, Any?> = mapOf(
        Keys.TYPE to Types.EVENT,
        Keys.CALL_ID to "",
        Keys.PLUGIN to plugin,
        Keys.METHOD to method,
        Keys.PARAMS to params
    )
}
