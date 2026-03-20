import Foundation
import SQLite3
import TanoBridge

/// Native SQLite plugin for Tano.
///
/// Provides database CRUD operations via the ``TanoPlugin`` protocol.
/// Databases are identified by opaque UUID handles returned from ``open``.
///
/// Supported methods: `open`, `query`, `run`, `close`.
public final class SQLitePlugin: TanoPlugin {

    // MARK: - TanoPlugin conformance

    public static let name = "sqlite"
    public static let permissions: [String] = ["filesystem.app-data"]

    public init() {}

    // MARK: - State

    /// Open database handles keyed by UUID string.
    private var databases: [String: OpaquePointer] = [:]

    /// Serialises access to the `databases` dictionary.
    private let lock = NSLock()

    // MARK: - Routing

    public func handle(method: String, params: [String: Any]) async throws -> Any? {
        switch method {
        case "open":
            return try openDatabase(params: params)
        case "query":
            return try query(params: params)
        case "run":
            return try run(params: params)
        case "close":
            return try closeDatabase(params: params)
        default:
            throw SQLitePluginError.unknownMethod(method)
        }
    }

    // MARK: - open

    private func openDatabase(params: [String: Any]) throws -> [String: Any] {
        guard let path = params["path"] as? String, !path.isEmpty else {
            throw SQLitePluginError.missingParameter("path")
        }

        // Ensure parent directory exists
        let dir = (path as NSString).deletingLastPathComponent
        if !dir.isEmpty && !FileManager.default.fileExists(atPath: dir) {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }

        var db: OpaquePointer?
        let rc = sqlite3_open(path, &db)
        guard rc == SQLITE_OK, let db = db else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            if let db = db { sqlite3_close(db) }
            throw SQLitePluginError.openFailed(path, msg)
        }

        // Enable WAL and foreign keys
        sqlite3_exec(db, "PRAGMA journal_mode=WAL", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA foreign_keys=ON", nil, nil, nil)

        let handle = UUID().uuidString
        lock.lock()
        databases[handle] = db
        lock.unlock()

        return ["handle": handle]
    }

    // MARK: - query

    private func query(params: [String: Any]) throws -> [String: Any] {
        let db = try resolveHandle(params)
        guard let sql = params["sql"] as? String, !sql.isEmpty else {
            throw SQLitePluginError.missingParameter("sql")
        }
        let bindParams = params["params"] as? [Any] ?? []

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLitePluginError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        try bindParameters(stmt: stmt!, params: bindParams)

        var rows: [[String: Any]] = []
        let colCount = sqlite3_column_count(stmt)

        while sqlite3_step(stmt) == SQLITE_ROW {
            var row: [String: Any] = [:]
            for i in 0..<colCount {
                let name = String(cString: sqlite3_column_name(stmt, i))
                row[name] = readColumn(stmt: stmt!, index: i)
            }
            rows.append(row)
        }

        return ["rows": rows]
    }

    // MARK: - run

    private func run(params: [String: Any]) throws -> [String: Any] {
        let db = try resolveHandle(params)
        guard let sql = params["sql"] as? String, !sql.isEmpty else {
            throw SQLitePluginError.missingParameter("sql")
        }
        let bindParams = params["params"] as? [Any] ?? []

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLitePluginError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        try bindParameters(stmt: stmt!, params: bindParams)

        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else {
            throw SQLitePluginError.executionFailed(String(cString: sqlite3_errmsg(db)))
        }

        return [
            "changes": Int(sqlite3_changes(db)),
            "lastInsertRowId": Int(sqlite3_last_insert_rowid(db)),
        ]
    }

    // MARK: - close

    private func closeDatabase(params: [String: Any]) throws -> [String: Any] {
        guard let handle = params["handle"] as? String, !handle.isEmpty else {
            throw SQLitePluginError.missingParameter("handle")
        }

        lock.lock()
        let db = databases.removeValue(forKey: handle)
        lock.unlock()

        if let db = db {
            sqlite3_close(db)
        }
        // Closing an unknown handle is a no-op (no crash).
        return ["success": true]
    }

    // MARK: - Helpers

    private func resolveHandle(_ params: [String: Any]) throws -> OpaquePointer {
        guard let handle = params["handle"] as? String, !handle.isEmpty else {
            throw SQLitePluginError.missingParameter("handle")
        }
        lock.lock()
        let db = databases[handle]
        lock.unlock()
        guard let db = db else {
            throw SQLitePluginError.invalidHandle(handle)
        }
        return db
    }

    private func bindParameters(stmt: OpaquePointer, params: [Any]) throws {
        for (i, param) in params.enumerated() {
            let idx = Int32(i + 1)
            switch param {
            case let v as String:
                sqlite3_bind_text(stmt, idx, (v as NSString).utf8String, -1,
                                  unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            case let v as Int:
                sqlite3_bind_int64(stmt, idx, Int64(v))
            case let v as Int64:
                sqlite3_bind_int64(stmt, idx, v)
            case let v as Double:
                sqlite3_bind_double(stmt, idx, v)
            case is NSNull:
                sqlite3_bind_null(stmt, idx)
            default:
                // Fall back to text representation or null
                if let v = param as? String {
                    sqlite3_bind_text(stmt, idx, (v as NSString).utf8String, -1,
                                      unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                } else {
                    sqlite3_bind_null(stmt, idx)
                }
            }
        }
    }

    private func readColumn(stmt: OpaquePointer, index: Int32) -> Any {
        switch sqlite3_column_type(stmt, index) {
        case SQLITE_INTEGER:
            return Int(sqlite3_column_int64(stmt, index))
        case SQLITE_FLOAT:
            return sqlite3_column_double(stmt, index)
        case SQLITE_TEXT:
            return String(cString: sqlite3_column_text(stmt, index))
        case SQLITE_BLOB:
            let bytes = sqlite3_column_blob(stmt, index)
            let count = sqlite3_column_bytes(stmt, index)
            if let bytes = bytes {
                return Data(bytes: bytes, count: Int(count)).base64EncodedString()
            }
            return NSNull()
        case SQLITE_NULL:
            return NSNull()
        default:
            return NSNull()
        }
    }

    // MARK: - Cleanup

    deinit {
        lock.lock()
        for (_, db) in databases {
            sqlite3_close(db)
        }
        databases.removeAll()
        lock.unlock()
    }
}

// MARK: - Errors

public enum SQLitePluginError: Error, LocalizedError {
    case unknownMethod(String)
    case missingParameter(String)
    case openFailed(String, String)
    case prepareFailed(String)
    case executionFailed(String)
    case invalidHandle(String)

    public var errorDescription: String? {
        switch self {
        case .unknownMethod(let m):
            return "Unknown SQLite plugin method: \(m)"
        case .missingParameter(let p):
            return "Missing required parameter: \(p)"
        case .openFailed(let path, let msg):
            return "Failed to open database '\(path)': \(msg)"
        case .prepareFailed(let msg):
            return "SQL prepare failed: \(msg)"
        case .executionFailed(let msg):
            return "SQL execution failed: \(msg)"
        case .invalidHandle(let h):
            return "Invalid database handle: \(h)"
        }
    }
}
