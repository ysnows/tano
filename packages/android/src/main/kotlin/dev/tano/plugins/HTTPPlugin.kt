package dev.tano.plugins

import dev.tano.bridge.TanoPlugin
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL

/**
 * Native HTTP client plugin for Tano on Android.
 *
 * Uses [HttpURLConnection] to make HTTP requests directly from the native
 * layer, bypassing WebView CORS restrictions. No external dependencies
 * (e.g. OkHttp) required.
 *
 * All network I/O runs on [Dispatchers.IO].
 *
 * Supported methods: `request`.
 *
 * Mirrors the iOS HTTPPlugin.
 */
class HTTPPlugin : TanoPlugin {

    override val name: String = "http"
    override val permissions: List<String> = listOf("network")

    // -- Routing --

    override suspend fun handle(method: String, params: Map<String, Any?>): Any? {
        return when (method) {
            "request" -> request(params)
            else -> throw IllegalArgumentException("Unknown HTTP plugin method: $method")
        }
    }

    // -- request --

    @Suppress("UNCHECKED_CAST")
    private suspend fun request(params: Map<String, Any?>): Map<String, Any?> =
        withContext(Dispatchers.IO) {
            val urlString = params["url"] as? String
                ?: throw IllegalArgumentException("Missing required parameter: url")

            val url = try {
                URL(urlString)
            } catch (e: Exception) {
                throw IllegalArgumentException("Invalid parameter: url is not a valid URL: $urlString")
            }

            val httpMethod = (params["method"] as? String)?.uppercase() ?: "GET"
            val headers = params["headers"] as? Map<String, String> ?: emptyMap()
            val bodyString = params["body"] as? String

            val connection = url.openConnection() as HttpURLConnection
            try {
                connection.requestMethod = httpMethod
                connection.connectTimeout = 30_000
                connection.readTimeout = 30_000

                for ((key, value) in headers) {
                    connection.setRequestProperty(key, value)
                }

                if (bodyString != null) {
                    connection.doOutput = true
                    connection.outputStream.use { output ->
                        output.write(bodyString.toByteArray(Charsets.UTF_8))
                    }
                }

                val statusCode = connection.responseCode

                // Read response headers
                val responseHeaders = mutableMapOf<String, String>()
                for (i in 0 until connection.headerFields.size) {
                    val key = connection.getHeaderFieldKey(i) ?: continue
                    val value = connection.getHeaderField(i) ?: continue
                    responseHeaders[key] = value
                }

                // Read response body
                val inputStream = try {
                    connection.inputStream
                } catch (_: Exception) {
                    connection.errorStream
                }

                val bodyText = if (inputStream != null) {
                    BufferedReader(InputStreamReader(inputStream, Charsets.UTF_8)).use { reader ->
                        reader.readText()
                    }
                } else {
                    ""
                }

                mapOf(
                    "status" to statusCode,
                    "headers" to responseHeaders,
                    "body" to bodyText
                )
            } finally {
                connection.disconnect()
            }
        }
}
