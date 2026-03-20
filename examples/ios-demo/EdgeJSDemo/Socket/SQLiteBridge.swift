import Foundation
import SQLite3

/// Swift-side SQLite bridge — exposes SQLite to Node.js via ProducerTasks/UDS.
///
/// Since node:sqlite uses V8 C++ API (incompatible with JSC), this bridge
/// provides SQLite access through the native iOS libsqlite3 framework.
///
/// JS calls: Commander.sendRequest({ method: "sqlite", payloads: { action, db, sql, params } })
/// Swift handles: open, exec, query, run, close
class SQLiteBridge {
    static let shared = SQLiteBridge()

    private var databases: [String: OpaquePointer] = [:]
    private let queue = DispatchQueue(label: "com.enconvo.sqlite", attributes: .concurrent)

    /// Handle a sqlite request from JS.
    func handle(context: TaskContext) {
        let action = context.payloads["action"] as? String ?? ""
        let dbPath = context.payloads["db"] as? String ?? context.payloads["path"] as? String ?? ""

        switch action {
        case "open":
            open(path: dbPath, context: context)
        case "close":
            close(path: dbPath, context: context)
        case "exec":
            let sql = context.payloads["sql"] as? String ?? ""
            exec(path: dbPath, sql: sql, context: context)
        case "run":
            let sql = context.payloads["sql"] as? String ?? ""
            let params = context.payloads["params"] as? [Any] ?? []
            run(path: dbPath, sql: sql, params: params, context: context)
        case "query":
            let sql = context.payloads["sql"] as? String ?? ""
            let params = context.payloads["params"] as? [Any] ?? []
            query(path: dbPath, sql: sql, params: params, context: context)
        default:
            context.completion(["error": "Unknown sqlite action: \(action)"])
        }
    }

    // MARK: - Database Operations

    private func getOrOpen(path: String) -> OpaquePointer? {
        if let db = databases[path] { return db }
        var db: OpaquePointer?

        // Ensure directory exists
        let dir = (path as NSString).deletingLastPathComponent
        if !FileManager.default.fileExists(atPath: dir) {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }

        let rc = sqlite3_open(path, &db)
        if rc == SQLITE_OK, let db = db {
            // Enable WAL mode for better concurrency
            sqlite3_exec(db, "PRAGMA journal_mode=WAL", nil, nil, nil)
            sqlite3_exec(db, "PRAGMA foreign_keys=ON", nil, nil, nil)
            databases[path] = db
            return db
        }
        return nil
    }

    private func open(path: String, context: TaskContext) {
        queue.async(flags: .barrier) { [self] in
            if let _ = getOrOpen(path: path) {
                context.completion(["success": true])
            } else {
                context.completion(["error": "Failed to open database: \(path)"])
            }
        }
    }

    private func close(path: String, context: TaskContext) {
        queue.async(flags: .barrier) { [self] in
            if let db = databases.removeValue(forKey: path) {
                sqlite3_close(db)
            }
            context.completion(["success": true])
        }
    }

    private func exec(path: String, sql: String, context: TaskContext) {
        queue.async(flags: .barrier) { [self] in
            guard let db = getOrOpen(path: path) else {
                context.completion(["error": "Database not open"])
                return
            }

            var errMsg: UnsafeMutablePointer<CChar>?
            let rc = sqlite3_exec(db, sql, nil, nil, &errMsg)
            if rc != SQLITE_OK {
                let error = errMsg.map { String(cString: $0) } ?? "Unknown error"
                sqlite3_free(errMsg)
                context.completion(["error": error])
            } else {
                context.completion(["success": true, "changes": sqlite3_changes(db)])
            }
        }
    }

    private func run(path: String, sql: String, params: [Any], context: TaskContext) {
        queue.async(flags: .barrier) { [self] in
            guard let db = getOrOpen(path: path) else {
                context.completion(["error": "Database not open"])
                return
            }

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                context.completion(["error": String(cString: sqlite3_errmsg(db))])
                return
            }
            defer { sqlite3_finalize(stmt) }

            bindParams(stmt: stmt!, params: params)

            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE || rc == SQLITE_ROW {
                context.completion([
                    "success": true,
                    "changes": sqlite3_changes(db),
                    "lastInsertRowid": sqlite3_last_insert_rowid(db)
                ])
            } else {
                context.completion(["error": String(cString: sqlite3_errmsg(db))])
            }
        }
    }

    private func query(path: String, sql: String, params: [Any], context: TaskContext) {
        queue.sync { [self] in
            guard let db = getOrOpen(path: path) else {
                context.completion(["error": "Database not open"])
                return
            }

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                context.completion(["error": String(cString: sqlite3_errmsg(db))])
                return
            }
            defer { sqlite3_finalize(stmt) }

            bindParams(stmt: stmt!, params: params)

            var rows: [[String: Any]] = []
            let colCount = sqlite3_column_count(stmt)

            while sqlite3_step(stmt) == SQLITE_ROW {
                var row: [String: Any] = [:]
                for i in 0..<colCount {
                    let name = String(cString: sqlite3_column_name(stmt, i))
                    switch sqlite3_column_type(stmt, i) {
                    case SQLITE_INTEGER:
                        row[name] = sqlite3_column_int64(stmt, i)
                    case SQLITE_FLOAT:
                        row[name] = sqlite3_column_double(stmt, i)
                    case SQLITE_TEXT:
                        row[name] = String(cString: sqlite3_column_text(stmt, i))
                    case SQLITE_BLOB:
                        let bytes = sqlite3_column_blob(stmt, i)
                        let count = sqlite3_column_bytes(stmt, i)
                        if let bytes = bytes {
                            row[name] = Data(bytes: bytes, count: Int(count)).base64EncodedString()
                        }
                    case SQLITE_NULL:
                        row[name] = NSNull()
                    default:
                        break
                    }
                }
                rows.append(row)
            }

            context.completion(["rows": rows])
        }
    }

    // MARK: - Parameter Binding

    private func bindParams(stmt: OpaquePointer, params: [Any]) {
        for (i, param) in params.enumerated() {
            let idx = Int32(i + 1)
            switch param {
            case let v as String:
                sqlite3_bind_text(stmt, idx, (v as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            case let v as Int:
                sqlite3_bind_int64(stmt, idx, Int64(v))
            case let v as Int64:
                sqlite3_bind_int64(stmt, idx, v)
            case let v as Double:
                sqlite3_bind_double(stmt, idx, v)
            case is NSNull:
                sqlite3_bind_null(stmt, idx)
            default:
                if let v = param as? String {
                    sqlite3_bind_text(stmt, idx, (v as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                } else {
                    sqlite3_bind_null(stmt, idx)
                }
            }
        }
    }
}
