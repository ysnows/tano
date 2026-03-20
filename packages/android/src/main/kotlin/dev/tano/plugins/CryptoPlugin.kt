package dev.tano.plugins

import android.util.Base64
import dev.tano.bridge.TanoPlugin
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.UUID
import javax.crypto.Cipher
import javax.crypto.Mac
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Native cryptography plugin for Tano on Android.
 *
 * Provides hashing, HMAC, AES-GCM encryption/decryption, and random data
 * generation via standard Java crypto APIs.
 *
 * Supported methods: `hash`, `hmac`, `randomUUID`, `randomBytes`, `encrypt`, `decrypt`.
 *
 * Mirrors the iOS CryptoPlugin.
 */
class CryptoPlugin : TanoPlugin {

    override val name: String = "crypto"
    override val permissions: List<String> = emptyList()

    // -- Routing --

    override suspend fun handle(method: String, params: Map<String, Any?>): Any? {
        return when (method) {
            "hash" -> hash(params)
            "hmac" -> hmac(params)
            "randomUUID" -> randomUUID()
            "randomBytes" -> randomBytes(params)
            "encrypt" -> encrypt(params)
            "decrypt" -> decrypt(params)
            else -> throw IllegalArgumentException("Unknown crypto plugin method: $method")
        }
    }

    // -- hash --

    private fun hash(params: Map<String, Any?>): Map<String, Any?> {
        val algorithm = params["algorithm"] as? String
            ?: throw IllegalArgumentException("Missing required parameter: algorithm")
        val data = params["data"] as? String
            ?: throw IllegalArgumentException("Missing required parameter: data")

        val digestAlgorithm = when (algorithm.lowercase()) {
            "sha256" -> "SHA-256"
            "sha384" -> "SHA-384"
            "sha512" -> "SHA-512"
            else -> throw IllegalArgumentException(
                "Unsupported algorithm: $algorithm. Use sha256, sha384, or sha512."
            )
        }

        val digest = MessageDigest.getInstance(digestAlgorithm)
        val hashBytes = digest.digest(data.toByteArray(Charsets.UTF_8))
        return mapOf("hash" to hashBytes.toHexString())
    }

    // -- hmac --

    private fun hmac(params: Map<String, Any?>): Map<String, Any?> {
        val algorithm = params["algorithm"] as? String
            ?: throw IllegalArgumentException("Missing required parameter: algorithm")
        val keyString = params["key"] as? String
            ?: throw IllegalArgumentException("Missing required parameter: key")
        val data = params["data"] as? String
            ?: throw IllegalArgumentException("Missing required parameter: data")

        val macAlgorithm = when (algorithm.lowercase()) {
            "sha256" -> "HmacSHA256"
            "sha384" -> "HmacSHA384"
            "sha512" -> "HmacSHA512"
            else -> throw IllegalArgumentException(
                "Unsupported algorithm: $algorithm. Use sha256, sha384, or sha512."
            )
        }

        val mac = Mac.getInstance(macAlgorithm)
        val keySpec = SecretKeySpec(keyString.toByteArray(Charsets.UTF_8), macAlgorithm)
        mac.init(keySpec)
        val hmacBytes = mac.doFinal(data.toByteArray(Charsets.UTF_8))
        return mapOf("hmac" to hmacBytes.toHexString())
    }

    // -- randomUUID --

    private fun randomUUID(): Map<String, Any?> {
        return mapOf("uuid" to UUID.randomUUID().toString().uppercase())
    }

    // -- randomBytes --

    private fun randomBytes(params: Map<String, Any?>): Map<String, Any?> {
        val length = when (val l = params["length"]) {
            is Int -> l
            is Long -> l.toInt()
            is Double -> l.toInt()
            else -> 16
        }

        if (length < 1 || length > 1024) {
            throw IllegalArgumentException("Invalid parameter: length must be between 1 and 1024")
        }

        val bytes = ByteArray(length)
        SecureRandom().nextBytes(bytes)
        val base64 = Base64.encodeToString(bytes, Base64.NO_WRAP)
        return mapOf("bytes" to base64)
    }

    // -- encrypt (AES-GCM) --

    private fun encrypt(params: Map<String, Any?>): Map<String, Any?> {
        val keyBase64 = params["key"] as? String
            ?: throw IllegalArgumentException("Missing required parameter: key (base64-encoded 32 bytes)")
        val keyData = Base64.decode(keyBase64, Base64.DEFAULT)
        if (keyData.size != 32) {
            throw IllegalArgumentException("Invalid parameter: key must be 32 bytes (256-bit) base64-encoded")
        }

        val plaintext = params["data"] as? String
            ?: throw IllegalArgumentException("Missing required parameter: data")

        val iv: ByteArray
        if (params["iv"] is String) {
            iv = Base64.decode(params["iv"] as String, Base64.DEFAULT)
        } else {
            // Generate a random 12-byte IV
            iv = ByteArray(12)
            SecureRandom().nextBytes(iv)
        }

        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        val keySpec = SecretKeySpec(keyData, "AES")
        val gcmSpec = GCMParameterSpec(128, iv) // 128-bit auth tag
        cipher.init(Cipher.ENCRYPT_MODE, keySpec, gcmSpec)

        val plaintextBytes = plaintext.toByteArray(Charsets.UTF_8)
        val cipherOutput = cipher.doFinal(plaintextBytes)

        // Java AES/GCM appends the tag to the ciphertext
        val tagLength = 16 // 128 bits / 8
        val ciphertextBytes = cipherOutput.copyOfRange(0, cipherOutput.size - tagLength)
        val tagBytes = cipherOutput.copyOfRange(cipherOutput.size - tagLength, cipherOutput.size)

        return mapOf(
            "ciphertext" to Base64.encodeToString(ciphertextBytes, Base64.NO_WRAP),
            "iv" to Base64.encodeToString(iv, Base64.NO_WRAP),
            "tag" to Base64.encodeToString(tagBytes, Base64.NO_WRAP)
        )
    }

    // -- decrypt (AES-GCM) --

    private fun decrypt(params: Map<String, Any?>): Map<String, Any?> {
        val keyBase64 = params["key"] as? String
            ?: throw IllegalArgumentException("Missing required parameter: key (base64-encoded)")
        val keyData = Base64.decode(keyBase64, Base64.DEFAULT)

        val ciphertextBase64 = params["ciphertext"] as? String
            ?: throw IllegalArgumentException("Missing required parameter: ciphertext (base64-encoded)")
        val ciphertextData = Base64.decode(ciphertextBase64, Base64.DEFAULT)

        val ivBase64 = params["iv"] as? String
            ?: throw IllegalArgumentException("Missing required parameter: iv (base64-encoded)")
        val ivData = Base64.decode(ivBase64, Base64.DEFAULT)

        val tagBase64 = params["tag"] as? String
            ?: throw IllegalArgumentException("Missing required parameter: tag (base64-encoded)")
        val tagData = Base64.decode(tagBase64, Base64.DEFAULT)

        // Java AES/GCM expects ciphertext + tag concatenated
        val combined = ciphertextData + tagData

        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        val keySpec = SecretKeySpec(keyData, "AES")
        val gcmSpec = GCMParameterSpec(128, ivData)
        cipher.init(Cipher.DECRYPT_MODE, keySpec, gcmSpec)

        val decryptedBytes = cipher.doFinal(combined)
        val plaintext = String(decryptedBytes, Charsets.UTF_8)

        return mapOf("plaintext" to plaintext)
    }

    // -- Helpers --

    private fun ByteArray.toHexString(): String =
        joinToString("") { "%02x".format(it) }
}
