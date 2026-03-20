package dev.tano.bridge

import android.util.Log
import org.json.JSONObject
import java.io.InputStream
import java.io.OutputStream
import java.net.Socket

/**
 * Coordinates the Unix Domain Socket connection and plugin routing
 * for the Tano bridge on Android.
 *
 * Reads length-prefixed frames from the UDS, decodes them as JSON
 * messages, routes them through the [PluginRouter], and sends
 * responses back over the socket.
 *
 * This is the Android equivalent of the iOS bridge coordinator.
 */
class BridgeManager(
    val pluginRouter: PluginRouter = PluginRouter()
) {

    companion object {
        private const val TAG = "BridgeManager"
    }

    private val frameDecoder = FrameDecoder()

    @Volatile
    private var connected = false

    private var outputStream: OutputStream? = null

    /**
     * Register a plugin with the underlying router.
     */
    fun registerPlugin(plugin: TanoPlugin) {
        pluginRouter.register(plugin)
    }

    /**
     * Unregister a plugin by name.
     */
    fun unregisterPlugin(name: String) {
        pluginRouter.unregister(name)
    }

    /**
     * Start listening on the given socket's input stream.
     *
     * This method blocks the calling thread and reads frames continuously
     * until the socket is closed or an error occurs. Call from a background
     * thread (e.g., via [Thread] or coroutine on [Dispatchers.IO]).
     *
     * @param socket The connected UDS socket.
     */
    fun startListening(socket: Socket) {
        outputStream = socket.getOutputStream()
        connected = true
        frameDecoder.reset()

        val input: InputStream = socket.getInputStream()
        val readBuffer = ByteArray(8192)

        try {
            while (connected) {
                val bytesRead = input.read(readBuffer)
                if (bytesRead == -1) {
                    Log.i(TAG, "Socket closed by remote end.")
                    break
                }

                val chunk = readBuffer.copyOfRange(0, bytesRead)
                val frames = frameDecoder.feed(chunk)

                for (frame in frames) {
                    handleFrame(frame)
                }
            }
        } catch (e: Exception) {
            if (connected) {
                Log.e(TAG, "Error reading from socket: ${e.message}", e)
            }
        } finally {
            connected = false
            outputStream = null
        }
    }

    /**
     * Disconnect and stop listening.
     */
    fun disconnect() {
        connected = false
    }

    /**
     * Send a raw message dictionary over the socket.
     * The message is JSON-encoded and length-prefixed.
     */
    @Synchronized
    fun send(message: Map<String, Any?>) {
        val os = outputStream ?: run {
            Log.w(TAG, "Cannot send: not connected")
            return
        }

        try {
            val json = JSONObject(message).toString()
            val frame = FrameEncoder.encode(json)
            os.write(frame)
            os.flush()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to send message: ${e.message}", e)
        }
    }

    // -- Internal --

    private fun handleFrame(frame: ByteArray) {
        val json = String(frame, Charsets.UTF_8)

        val message: Map<String, Any?>
        try {
            message = jsonToMap(JSONObject(json))
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse frame as JSON: ${e.message}")
            return
        }

        val type = message[TanoBridgeMessage.Keys.TYPE] as? String
        if (type != TanoBridgeMessage.Keys.TYPE && type == TanoBridgeMessage.Types.REQUEST) {
            routeRequest(message)
        } else if (type == TanoBridgeMessage.Types.EVENT) {
            routeRequest(message)
        } else {
            Log.d(TAG, "Received message of type: $type")
        }
    }

    private fun routeRequest(message: Map<String, Any?>) {
        val callId = message[TanoBridgeMessage.Keys.CALL_ID] as? String ?: ""
        val pluginName = message[TanoBridgeMessage.Keys.PLUGIN] as? String ?: ""
        val method = message[TanoBridgeMessage.Keys.METHOD] as? String ?: ""

        pluginRouter.handle(message) { result ->
            if (callId.isNotEmpty()) {
                val response = if (result != null) {
                    TanoBridgeMessage.response(
                        callId = callId,
                        plugin = pluginName,
                        method = method,
                        params = when (result) {
                            is Map<*, *> -> {
                                @Suppress("UNCHECKED_CAST")
                                result as Map<String, Any?>
                            }
                            else -> mapOf("result" to result)
                        }
                    )
                } else {
                    TanoBridgeMessage.error(
                        callId = callId,
                        plugin = pluginName,
                        method = method,
                        errorMessage = "Plugin '$pluginName' failed to handle '$method'"
                    )
                }
                send(response)
            }
        }
    }

    /**
     * Convert a [JSONObject] to a [Map].
     */
    private fun jsonToMap(json: JSONObject): Map<String, Any?> {
        val map = mutableMapOf<String, Any?>()
        val keys = json.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            val value = json.get(key)
            map[key] = when (value) {
                is JSONObject -> jsonToMap(value)
                is org.json.JSONArray -> jsonArrayToList(value)
                JSONObject.NULL -> null
                else -> value
            }
        }
        return map
    }

    /**
     * Convert a [JSONArray] to a [List].
     */
    private fun jsonArrayToList(array: org.json.JSONArray): List<Any?> {
        val list = mutableListOf<Any?>()
        for (i in 0 until array.length()) {
            val value = array.get(i)
            list.add(
                when (value) {
                    is JSONObject -> jsonToMap(value)
                    is org.json.JSONArray -> jsonArrayToList(value)
                    JSONObject.NULL -> null
                    else -> value
                }
            )
        }
        return list
    }
}
