import XCTest
@testable import TanoPluginFS

final class FSPluginTests: XCTestCase {

    private var plugin: FSPlugin!
    private var tempDir: String!

    override func setUp() {
        super.setUp()
        tempDir = NSTemporaryDirectory() + "tano_fs_tests_\(UUID().uuidString)/"
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        plugin = FSPlugin(basePath: tempDir)
    }

    override func tearDown() {
        plugin = nil
        if let dir = tempDir {
            try? FileManager.default.removeItem(atPath: dir)
        }
        super.tearDown()
    }

    // MARK: - testPluginName

    func testPluginName() {
        XCTAssertEqual(FSPlugin.name, "fs")
        XCTAssertEqual(FSPlugin.permissions, ["filesystem.app-data"])
    }

    // MARK: - testWriteAndRead

    func testWriteAndRead() async throws {
        let writeResult = try await plugin.handle(method: "write", params: [
            "path": "hello.txt",
            "content": "Hello, Tano!",
        ])
        let writeDict = try XCTUnwrap(writeResult as? [String: Any])
        XCTAssertEqual(writeDict["success"] as? Bool, true)

        let readResult = try await plugin.handle(method: "read", params: ["path": "hello.txt"])
        let readDict = try XCTUnwrap(readResult as? [String: Any])
        XCTAssertEqual(readDict["content"] as? String, "Hello, Tano!")
    }

    // MARK: - testExists

    func testExists() async throws {
        // Should not exist yet
        let result1 = try await plugin.handle(method: "exists", params: ["path": "check.txt"])
        let dict1 = try XCTUnwrap(result1 as? [String: Any])
        XCTAssertEqual(dict1["exists"] as? Bool, false)

        // Create it
        _ = try await plugin.handle(method: "write", params: ["path": "check.txt", "content": "data"])

        // Should exist now
        let result2 = try await plugin.handle(method: "exists", params: ["path": "check.txt"])
        let dict2 = try XCTUnwrap(result2 as? [String: Any])
        XCTAssertEqual(dict2["exists"] as? Bool, true)
    }

    // MARK: - testDelete

    func testDelete() async throws {
        // Create a file
        _ = try await plugin.handle(method: "write", params: ["path": "temp.txt", "content": "temporary"])

        // Delete it
        let deleteResult = try await plugin.handle(method: "delete", params: ["path": "temp.txt"])
        let deleteDict = try XCTUnwrap(deleteResult as? [String: Any])
        XCTAssertEqual(deleteDict["success"] as? Bool, true)

        // Verify it's gone
        let existsResult = try await plugin.handle(method: "exists", params: ["path": "temp.txt"])
        let existsDict = try XCTUnwrap(existsResult as? [String: Any])
        XCTAssertEqual(existsDict["exists"] as? Bool, false)
    }

    // MARK: - testList

    func testList() async throws {
        // Create a few files
        _ = try await plugin.handle(method: "write", params: ["path": "a.txt", "content": "aaa"])
        _ = try await plugin.handle(method: "write", params: ["path": "b.txt", "content": "bbb"])
        _ = try await plugin.handle(method: "write", params: ["path": "c.txt", "content": "ccc"])

        let listResult = try await plugin.handle(method: "list", params: ["path": "."])
        let listDict = try XCTUnwrap(listResult as? [String: Any])
        let entries = try XCTUnwrap(listDict["entries"] as? [String])

        XCTAssertEqual(entries.count, 3)
        XCTAssertTrue(entries.contains("a.txt"))
        XCTAssertTrue(entries.contains("b.txt"))
        XCTAssertTrue(entries.contains("c.txt"))
    }

    // MARK: - testMkdir

    func testMkdir() async throws {
        let mkdirResult = try await plugin.handle(method: "mkdir", params: ["path": "subdir/nested"])
        let mkdirDict = try XCTUnwrap(mkdirResult as? [String: Any])
        XCTAssertEqual(mkdirDict["success"] as? Bool, true)

        // Write a file inside it
        _ = try await plugin.handle(method: "write", params: [
            "path": "subdir/nested/file.txt",
            "content": "nested content",
        ])

        let readResult = try await plugin.handle(method: "read", params: ["path": "subdir/nested/file.txt"])
        let readDict = try XCTUnwrap(readResult as? [String: Any])
        XCTAssertEqual(readDict["content"] as? String, "nested content")
    }

    // MARK: - testReadNonexistent

    func testReadNonexistent() async {
        do {
            _ = try await plugin.handle(method: "read", params: ["path": "does_not_exist.txt"])
            XCTFail("Expected an error for nonexistent file")
        } catch {
            XCTAssertTrue(error is FSPluginError)
            if case .fileNotFound = error as? FSPluginError {
                // Expected
            } else {
                XCTFail("Expected fileNotFound error, got \(error)")
            }
        }
    }
}
