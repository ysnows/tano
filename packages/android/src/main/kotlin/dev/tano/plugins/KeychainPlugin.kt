package dev.tano.plugins

import android.content.Context
import android.content.SharedPreferences
import dev.tano.bridge.TanoPlugin

/**
 * Native key-value storage plugin for Tano on Android.
 *
 * Provides simple key-value persistence using a dedicated [SharedPreferences]
 * file (`dev.tano.keychain`). A future version may migrate to
 * `EncryptedSharedPreferences` for secure storage.
 *
 * Supported methods: `set`, `get`, `delete`.
 *
 * Mirrors the iOS KeychainPlugin.
 *
 * @param context Android Context needed to access SharedPreferences.
 */
class KeychainPlugin(private val context: Context) : TanoPlugin {

    override val name: String = "keychain"
    override val permissions: List<String> = listOf("storage")

    private val prefs: SharedPreferences
        get() = context.getSharedPreferences("dev.tano.keychain", Context.MODE_PRIVATE)

    // -- Routing --

    override suspend fun handle(method: String, params: Map<String, Any?>): Any? {
        return when (method) {
            "set" -> setValue(params)
            "get" -> getValue(params)
            "delete" -> deleteValue(params)
            else -> throw IllegalArgumentException("Unknown keychain plugin method: $method")
        }
    }

    // -- set --

    private fun setValue(params: Map<String, Any?>): Map<String, Any?> {
        val key = params["key"] as? String
        if (key.isNullOrEmpty()) {
            throw IllegalArgumentException("Missing required parameter: key")
        }
        val value = params["value"] as? String
            ?: throw IllegalArgumentException("Missing required parameter: value")

        prefs.edit().putString(key, value).apply()
        return mapOf("success" to true)
    }

    // -- get --

    private fun getValue(params: Map<String, Any?>): Map<String, Any?> {
        val key = params["key"] as? String
        if (key.isNullOrEmpty()) {
            throw IllegalArgumentException("Missing required parameter: key")
        }

        val value = prefs.getString(key, null)
        return mapOf("value" to value)
    }

    // -- delete --

    private fun deleteValue(params: Map<String, Any?>): Map<String, Any?> {
        val key = params["key"] as? String
        if (key.isNullOrEmpty()) {
            throw IllegalArgumentException("Missing required parameter: key")
        }

        prefs.edit().remove(key).apply()
        return mapOf("success" to true)
    }
}
