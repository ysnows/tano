import XCTest
@testable import TanoPluginKeychain

final class KeychainPluginTests: XCTestCase {

    private var plugin: KeychainPlugin!
    private let testSuite = "dev.tano.keychain.tests.\(UUID().uuidString)"

    override func setUp() {
        super.setUp()
        plugin = KeychainPlugin(suiteName: testSuite)
    }

    override func tearDown() {
        // Remove the test suite to avoid leaking state
        if let defaults = UserDefaults(suiteName: testSuite) {
            defaults.removePersistentDomain(forName: testSuite)
        }
        plugin = nil
        super.tearDown()
    }

    // MARK: - testPluginName

    func testPluginName() {
        XCTAssertEqual(KeychainPlugin.name, "keychain")
        XCTAssertEqual(KeychainPlugin.permissions, ["storage"])
    }

    // MARK: - testSetAndGet

    func testSetAndGet() async throws {
        let setResult = try await plugin.handle(method: "set", params: ["key": "greeting", "value": "hello"])
        let setDict = try XCTUnwrap(setResult as? [String: Any])
        XCTAssertEqual(setDict["success"] as? Bool, true)

        let getResult = try await plugin.handle(method: "get", params: ["key": "greeting"])
        let getDict = try XCTUnwrap(getResult as? [String: Any])
        XCTAssertEqual(getDict["value"] as? String, "hello")
    }

    // MARK: - testGetMissing

    func testGetMissing() async throws {
        let result = try await plugin.handle(method: "get", params: ["key": "nonexistent"])
        let dict = try XCTUnwrap(result as? [String: Any])
        XCTAssertTrue(dict["value"] is NSNull, "Expected NSNull for missing key")
    }

    // MARK: - testDelete

    func testDelete() async throws {
        // Set a value first
        _ = try await plugin.handle(method: "set", params: ["key": "temp", "value": "data"])

        // Delete it
        let deleteResult = try await plugin.handle(method: "delete", params: ["key": "temp"])
        let deleteDict = try XCTUnwrap(deleteResult as? [String: Any])
        XCTAssertEqual(deleteDict["success"] as? Bool, true)

        // Verify it's gone
        let getResult = try await plugin.handle(method: "get", params: ["key": "temp"])
        let getDict = try XCTUnwrap(getResult as? [String: Any])
        XCTAssertTrue(getDict["value"] is NSNull, "Expected NSNull after deletion")
    }

    // MARK: - testOverwrite

    func testOverwrite() async throws {
        _ = try await plugin.handle(method: "set", params: ["key": "counter", "value": "1"])

        // Overwrite with a new value
        _ = try await plugin.handle(method: "set", params: ["key": "counter", "value": "2"])

        let getResult = try await plugin.handle(method: "get", params: ["key": "counter"])
        let getDict = try XCTUnwrap(getResult as? [String: Any])
        XCTAssertEqual(getDict["value"] as? String, "2")
    }
}
