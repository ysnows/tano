package dev.tano.plugins

import dev.tano.bridge.TanoPlugin
import java.io.File

/**
 * Native file system plugin for Tano on Android.
 *
 * All paths are relative to a sandboxed [basePath] (typically the app's data
 * directory). Attempting to escape via `..` is rejected.
 *
 * Supported methods: `read`, `write`, `exists`, `delete`, `list`, `mkdir`.
 *
 * Mirrors the iOS FSPlugin.
 *
 * @param basePath The root directory for all file operations.
 */
class FSPlugin(private val basePath: String) : TanoPlugin {

    override val name: String = "fs"
    override val permissions: List<String> = listOf("filesystem.app-data")

    // -- Routing --

    override suspend fun handle(method: String, params: Map<String, Any?>): Any? {
        return when (method) {
            "read" -> readFile(params)
            "write" -> writeFile(params)
            "exists" -> fileExists(params)
            "delete" -> deleteFile(params)
            "list" -> listDirectory(params)
            "mkdir" -> makeDirectory(params)
            else -> throw IllegalArgumentException("Unknown fs plugin method: $method")
        }
    }

    // -- read --

    private fun readFile(params: Map<String, Any?>): Map<String, Any?> {
        val fullPath = resolvePath(params)
        val file = File(fullPath)
        if (!file.exists()) {
            throw IllegalArgumentException("File not found: ${params["path"]}")
        }
        val content = file.readText(Charsets.UTF_8)
        return mapOf("content" to content)
    }

    // -- write --

    private fun writeFile(params: Map<String, Any?>): Map<String, Any?> {
        val fullPath = resolvePath(params)
        val content = params["content"] as? String ?: ""
        val file = File(fullPath)

        // Ensure parent directory exists
        file.parentFile?.let { dir ->
            if (!dir.exists()) {
                dir.mkdirs()
            }
        }

        file.writeText(content, Charsets.UTF_8)
        return mapOf("success" to true)
    }

    // -- exists --

    private fun fileExists(params: Map<String, Any?>): Map<String, Any?> {
        val fullPath = resolvePath(params)
        val exists = File(fullPath).exists()
        return mapOf("exists" to exists)
    }

    // -- delete --

    private fun deleteFile(params: Map<String, Any?>): Map<String, Any?> {
        val fullPath = resolvePath(params)
        val file = File(fullPath)
        if (!file.exists()) {
            throw IllegalArgumentException("File not found: ${params["path"]}")
        }
        file.delete()
        return mapOf("success" to true)
    }

    // -- list --

    private fun listDirectory(params: Map<String, Any?>): Map<String, Any?> {
        val fullPath = resolvePath(params)
        val dir = File(fullPath)
        if (!dir.exists() || !dir.isDirectory) {
            throw IllegalArgumentException("Not a directory: ${params["path"]}")
        }
        val entries = dir.list()?.sorted() ?: emptyList()
        return mapOf("entries" to entries)
    }

    // -- mkdir --

    private fun makeDirectory(params: Map<String, Any?>): Map<String, Any?> {
        val fullPath = resolvePath(params)
        File(fullPath).mkdirs()
        return mapOf("success" to true)
    }

    // -- Helpers --

    /**
     * Resolves a relative path against [basePath] and validates it stays within
     * the sandbox.
     */
    private fun resolvePath(params: Map<String, Any?>): String {
        val path = params["path"] as? String
        if (path.isNullOrEmpty()) {
            throw IllegalArgumentException("Missing required parameter: path")
        }

        val resolved = File(basePath, path)
        val canonical = resolved.canonicalPath
        val canonicalBase = File(basePath).canonicalPath

        // Ensure the resolved path is still within basePath
        if (!canonical.startsWith(canonicalBase)) {
            throw SecurityException("Path escapes sandbox: $path")
        }

        return canonical
    }
}
