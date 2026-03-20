package dev.tano.plugins

import dev.tano.bridge.TanoPlugin

/**
 * Native camera & photo-picker plugin for Tano on Android.
 *
 * Currently a stub implementation. Real camera capture and image picking
 * require an Activity context with `registerForActivityResult` to handle
 * the camera/gallery intents and their results. A future version will
 * integrate with ActivityResultContracts.
 *
 * Supported methods: `takePicture`, `pickImage`.
 *
 * Mirrors the iOS CameraPlugin.
 */
class CameraPlugin : TanoPlugin {

    override val name: String = "camera"
    override val permissions: List<String> = listOf("camera", "photos")

    // -- Routing --

    override suspend fun handle(method: String, params: Map<String, Any?>): Any? {
        return when (method) {
            "takePicture" -> takePicture(params)
            "pickImage" -> pickImage()
            else -> throw IllegalArgumentException("Unknown camera plugin method: $method")
        }
    }

    // -- takePicture --

    private fun takePicture(params: Map<String, Any?>): Map<String, Any?> {
        // Validate the camera parameter even in stub mode
        val camera = params["camera"] as? String ?: "back"
        if (camera != "front" && camera != "back") {
            throw IllegalArgumentException("Invalid value '$camera' for parameter 'camera'")
        }

        throw UnsupportedOperationException(
            "Camera requires Activity context. Use an Activity-aware plugin registration."
        )
    }

    // -- pickImage --

    private fun pickImage(): Map<String, Any?> {
        throw UnsupportedOperationException(
            "Image picker requires Activity context. Use an Activity-aware plugin registration."
        )
    }
}
