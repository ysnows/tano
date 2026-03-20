package dev.tano.plugins

import android.database.sqlite.SQLiteDatabase
import android.util.Log
import dev.tano.bridge.TanoPlugin
import java.io.File
import java.util.UUID

/**
 * Native SQLite plugin for Tano on Android.
 *
 * Provides database CRUD operations via the [TanoPlugin] interface.
 * Uses [android.database.sqlite.SQLiteDatabase] for database access.
 * Databases are identified by opaque UUID handles returned from `open`.
 *
 * Supported methods: `open`, `query`, `run`, `close`.
 *
 * Mirrors the iOS SQLitePlugin.
 */
class SqlitePlugin(private val dbDir: String) : TanoPlugin {

    companion object {
        private const val TAG = "SqlitePlugin"
    }

    override val name: String = "sqlite"
    override val permissions: List<String> = listOf("filesystem.app-data")

    /** Open database handles keyed by UUID string. */
    private val databases = mutableMapOf<String, SQLiteDatabase>()

    // -- Routing --

    override suspend fun handle(method: String, params: Map<String, Any?>): Any? {
        return when (method) {
            "open" -> openDatabase(params)
            "query" -> query(params)
            "run" -> run(params)
            "close" -> closeDatabase(params)
            else -> throw IllegalArgumentException("Unknown SQLite plugin method: $method")
        }
    }

    // -- open --

    private fun openDatabase(params: Map<String, Any?>): Map<String, Any?> {
        val path = params["path"] as? String
        if (path.isNullOrEmpty()) {
            throw IllegalArgumentException("Missing required parameter: path")
        }

        val fullPath = if (path.startsWith("/")) path else "$dbDir/$path"

        // Ensure parent directory exists
        val dir = File(fullPath).parentFile
        if (dir != null && !dir.exists()) {
            dir.mkdirs()
        }

        val db = SQLiteDatabase.openOrCreateDatabase(fullPath, null)

        // Enable WAL and foreign keys
        db.rawQuery("PRAGMA journal_mode=WAL", null).use { it.moveToFirst() }
        db.execSQL("PRAGMA foreign_keys=ON")

        val handle = UUID.randomUUID().toString()
        synchronized(databases) {
            databases[handle] = db
        }

        return mapOf("handle" to handle)
    }

    // -- query --

    private fun query(params: Map<String, Any?>): Map<String, Any?> {
        val db = resolveHandle(params)
        val sql = params["sql"] as? String
        if (sql.isNullOrEmpty()) {
            throw IllegalArgumentException("Missing required parameter: sql")
        }

        val bindParams = toStringArray(params["params"])

        val rows = mutableListOf<Map<String, Any?>>()
        db.rawQuery(sql, bindParams).use { cursor ->
            val columnNames = cursor.columnNames
            while (cursor.moveToNext()) {
                val row = mutableMapOf<String, Any?>()
                for (i in columnNames.indices) {
                    row[columnNames[i]] = when (cursor.getType(i)) {
                        android.database.Cursor.FIELD_TYPE_NULL -> null
                        android.database.Cursor.FIELD_TYPE_INTEGER -> cursor.getLong(i)
                        android.database.Cursor.FIELD_TYPE_FLOAT -> cursor.getDouble(i)
                        android.database.Cursor.FIELD_TYPE_STRING -> cursor.getString(i)
                        android.database.Cursor.FIELD_TYPE_BLOB -> {
                            android.util.Base64.encodeToString(
                                cursor.getBlob(i),
                                android.util.Base64.NO_WRAP
                            )
                        }
                        else -> null
                    }
                }
                rows.add(row)
            }
        }

        return mapOf("rows" to rows)
    }

    // -- run --

    private fun run(params: Map<String, Any?>): Map<String, Any?> {
        val db = resolveHandle(params)
        val sql = params["sql"] as? String
        if (sql.isNullOrEmpty()) {
            throw IllegalArgumentException("Missing required parameter: sql")
        }

        val bindParams = toObjectArray(params["params"])

        db.execSQL(sql, bindParams)

        // Retrieve changes and last insert row ID
        var changes = 0L
        db.rawQuery("SELECT changes()", null).use { cursor ->
            if (cursor.moveToFirst()) {
                changes = cursor.getLong(0)
            }
        }

        var lastInsertRowId = 0L
        db.rawQuery("SELECT last_insert_rowid()", null).use { cursor ->
            if (cursor.moveToFirst()) {
                lastInsertRowId = cursor.getLong(0)
            }
        }

        return mapOf(
            "changes" to changes,
            "lastInsertRowId" to lastInsertRowId
        )
    }

    // -- close --

    private fun closeDatabase(params: Map<String, Any?>): Map<String, Any?> {
        val handle = params["handle"] as? String
        if (handle.isNullOrEmpty()) {
            throw IllegalArgumentException("Missing required parameter: handle")
        }

        val db: SQLiteDatabase?
        synchronized(databases) {
            db = databases.remove(handle)
        }

        db?.close()
        // Closing an unknown handle is a no-op
        return mapOf("success" to true)
    }

    // -- Helpers --

    private fun resolveHandle(params: Map<String, Any?>): SQLiteDatabase {
        val handle = params["handle"] as? String
        if (handle.isNullOrEmpty()) {
            throw IllegalArgumentException("Missing required parameter: handle")
        }

        val db: SQLiteDatabase?
        synchronized(databases) {
            db = databases[handle]
        }

        return db ?: throw IllegalArgumentException("Invalid database handle: $handle")
    }

    /**
     * Convert params list to String array for rawQuery (which expects String?[]).
     */
    private fun toStringArray(params: Any?): Array<String>? {
        if (params == null) return null
        if (params !is List<*>) return null
        if (params.isEmpty()) return null
        return params.map { it?.toString() ?: "" }.toTypedArray()
    }

    /**
     * Convert params list to Object array for execSQL.
     */
    private fun toObjectArray(params: Any?): Array<Any> {
        if (params == null) return emptyArray()
        if (params !is List<*>) return emptyArray()
        return params.map { it ?: "" }.toTypedArray()
    }

    /**
     * Close all open database handles.
     */
    fun closeAll() {
        synchronized(databases) {
            for ((_, db) in databases) {
                try {
                    db.close()
                } catch (e: Exception) {
                    Log.w(TAG, "Error closing database: ${e.message}")
                }
            }
            databases.clear()
        }
    }
}
