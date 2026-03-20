import XCTest
@testable import TanoPluginSQLite

final class SQLitePluginTests: XCTestCase {

    private var plugin: SQLitePlugin!
    private var tempDir: String!

    override func setUp() {
        super.setUp()
        plugin = SQLitePlugin()
        tempDir = NSTemporaryDirectory() + "tano_sqlite_tests_\(UUID().uuidString)/"
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        plugin = nil
        if let dir = tempDir {
            try? FileManager.default.removeItem(atPath: dir)
        }
        super.tearDown()
    }

    private func dbPath(_ name: String = "test.db") -> String {
        return tempDir + name
    }

    // MARK: - testPluginName

    func testPluginName() {
        XCTAssertEqual(SQLitePlugin.name, "sqlite")
        XCTAssertEqual(SQLitePlugin.permissions, ["filesystem.app-data"])
    }

    // MARK: - testOpenAndClose

    func testOpenAndClose() async throws {
        let openResult = try await plugin.handle(method: "open", params: ["path": dbPath()])
        let openDict = try XCTUnwrap(openResult as? [String: Any])
        let handle = try XCTUnwrap(openDict["handle"] as? String)
        XCTAssertFalse(handle.isEmpty)

        let closeResult = try await plugin.handle(method: "close", params: ["handle": handle])
        let closeDict = try XCTUnwrap(closeResult as? [String: Any])
        XCTAssertEqual(closeDict["success"] as? Bool, true)
    }

    // MARK: - testCreateTableAndInsert

    func testCreateTableAndInsert() async throws {
        // Open
        let openResult = try await plugin.handle(method: "open", params: ["path": dbPath()])
        let handle = try XCTUnwrap((openResult as? [String: Any])?["handle"] as? String)

        // CREATE TABLE
        _ = try await plugin.handle(method: "run", params: [
            "handle": handle,
            "sql": "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, age INTEGER)",
        ])

        // INSERT
        _ = try await plugin.handle(method: "run", params: [
            "handle": handle,
            "sql": "INSERT INTO users (name, age) VALUES (?, ?)",
            "params": ["Alice", 30] as [Any],
        ])

        _ = try await plugin.handle(method: "run", params: [
            "handle": handle,
            "sql": "INSERT INTO users (name, age) VALUES (?, ?)",
            "params": ["Bob", 25] as [Any],
        ])

        // SELECT
        let queryResult = try await plugin.handle(method: "query", params: [
            "handle": handle,
            "sql": "SELECT * FROM users ORDER BY id",
        ])
        let queryDict = try XCTUnwrap(queryResult as? [String: Any])
        let rows = try XCTUnwrap(queryDict["rows"] as? [[String: Any]])

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0]["name"] as? String, "Alice")
        XCTAssertEqual(rows[0]["age"] as? Int, 30)
        XCTAssertEqual(rows[1]["name"] as? String, "Bob")
        XCTAssertEqual(rows[1]["age"] as? Int, 25)

        // Cleanup
        _ = try await plugin.handle(method: "close", params: ["handle": handle])
    }

    // MARK: - testQueryWithParams

    func testQueryWithParams() async throws {
        let openResult = try await plugin.handle(method: "open", params: ["path": dbPath()])
        let handle = try XCTUnwrap((openResult as? [String: Any])?["handle"] as? String)

        _ = try await plugin.handle(method: "run", params: [
            "handle": handle,
            "sql": "CREATE TABLE items (id INTEGER PRIMARY KEY, label TEXT, price REAL)",
        ])

        _ = try await plugin.handle(method: "run", params: [
            "handle": handle,
            "sql": "INSERT INTO items (label, price) VALUES (?, ?)",
            "params": ["Widget", 9.99] as [Any],
        ])

        _ = try await plugin.handle(method: "run", params: [
            "handle": handle,
            "sql": "INSERT INTO items (label, price) VALUES (?, ?)",
            "params": ["Gadget", 19.99] as [Any],
        ])

        _ = try await plugin.handle(method: "run", params: [
            "handle": handle,
            "sql": "INSERT INTO items (label, price) VALUES (?, ?)",
            "params": ["Doohickey", 4.50] as [Any],
        ])

        // Parameterised query
        let queryResult = try await plugin.handle(method: "query", params: [
            "handle": handle,
            "sql": "SELECT label, price FROM items WHERE price > ? ORDER BY price",
            "params": [5.0] as [Any],
        ])
        let rows = try XCTUnwrap((queryResult as? [String: Any])?["rows"] as? [[String: Any]])

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0]["label"] as? String, "Widget")
        XCTAssertEqual(rows[1]["label"] as? String, "Gadget")

        _ = try await plugin.handle(method: "close", params: ["handle": handle])
    }

    // MARK: - testRunReturnsChanges

    func testRunReturnsChanges() async throws {
        let openResult = try await plugin.handle(method: "open", params: ["path": dbPath()])
        let handle = try XCTUnwrap((openResult as? [String: Any])?["handle"] as? String)

        _ = try await plugin.handle(method: "run", params: [
            "handle": handle,
            "sql": "CREATE TABLE counter (id INTEGER PRIMARY KEY, val TEXT)",
        ])

        let insertResult = try await plugin.handle(method: "run", params: [
            "handle": handle,
            "sql": "INSERT INTO counter (val) VALUES (?)",
            "params": ["first"] as [Any],
        ])
        let insertDict = try XCTUnwrap(insertResult as? [String: Any])
        XCTAssertEqual(insertDict["changes"] as? Int, 1)
        XCTAssertEqual(insertDict["lastInsertRowId"] as? Int, 1)

        let insertResult2 = try await plugin.handle(method: "run", params: [
            "handle": handle,
            "sql": "INSERT INTO counter (val) VALUES (?)",
            "params": ["second"] as [Any],
        ])
        let insertDict2 = try XCTUnwrap(insertResult2 as? [String: Any])
        XCTAssertEqual(insertDict2["changes"] as? Int, 1)
        XCTAssertEqual(insertDict2["lastInsertRowId"] as? Int, 2)

        _ = try await plugin.handle(method: "close", params: ["handle": handle])
    }

    // MARK: - testCloseInvalidHandle

    func testCloseInvalidHandle() async throws {
        // Closing an unknown handle should not crash; it returns success.
        let result = try await plugin.handle(method: "close", params: ["handle": "nonexistent-handle"])
        let dict = try XCTUnwrap(result as? [String: Any])
        XCTAssertEqual(dict["success"] as? Bool, true)
    }

    // MARK: - testQueryInvalidHandle

    func testQueryInvalidHandle() async {
        do {
            _ = try await plugin.handle(method: "query", params: [
                "handle": "nonexistent-handle",
                "sql": "SELECT 1",
            ])
            XCTFail("Expected an error for invalid handle")
        } catch {
            XCTAssertTrue(error is SQLitePluginError)
            let pluginError = error as! SQLitePluginError
            if case .invalidHandle = pluginError {
                // Expected
            } else {
                XCTFail("Expected invalidHandle error, got \(pluginError)")
            }
        }
    }
}
