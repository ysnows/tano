import XCTest
@testable import TanoBridge

// MARK: - Mock Plugin

private class MockPlugin: TanoPlugin {
    static var name: String = "mock"
    static var permissions: [String] = ["test"]

    var lastMethod: String?
    var lastParams: [String: Any]?
    var resultToReturn: Any? = ["success": true]
    var shouldThrow: Bool = false

    func handle(method: String, params: [String: Any]) async throws -> Any? {
        lastMethod = method
        lastParams = params
        if shouldThrow {
            throw NSError(domain: "MockPlugin", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Mock error"])
        }
        return resultToReturn
    }
}

private class AnotherPlugin: TanoPlugin {
    static var name: String = "another"
    static var permissions: [String] = []

    func handle(method: String, params: [String: Any]) async throws -> Any? {
        return ["plugin": "another", "method": method]
    }
}

// MARK: - PluginRouterTests

final class PluginRouterTests: XCTestCase {

    // MARK: - Register and Route

    func testRegisterAndRoute() {
        let router = PluginRouter()
        let plugin = MockPlugin()
        router.register(plugin: plugin)

        let expectation = XCTestExpectation(description: "Plugin receives message")

        let message: [String: Any] = [
            "type": "request",
            "plugin": "mock",
            "method": "doSomething",
            "params": ["key": "value"],
            "callId": "test-1",
        ]

        router.handle(message: message) { result in
            XCTAssertNotNil(result)
            if let dict = result as? [String: Any] {
                XCTAssertEqual(dict["success"] as? Bool, true)
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2.0)

        XCTAssertEqual(plugin.lastMethod, "doSomething")
        XCTAssertEqual(plugin.lastParams?["key"] as? String, "value")
    }

    // MARK: - Unknown Plugin

    func testUnknownPlugin() {
        let router = PluginRouter()

        let expectation = XCTestExpectation(description: "Returns nil for unknown plugin")

        let message: [String: Any] = [
            "type": "request",
            "plugin": "nonexistent",
            "method": "test",
            "callId": "test-2",
        ]

        router.handle(message: message) { result in
            XCTAssertNil(result)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2.0)
    }

    // MARK: - Plugin Throws Error

    func testPluginThrowsError() {
        let router = PluginRouter()
        let plugin = MockPlugin()
        plugin.shouldThrow = true
        router.register(plugin: plugin)

        let expectation = XCTestExpectation(description: "Returns nil on plugin error")

        let message: [String: Any] = [
            "type": "request",
            "plugin": "mock",
            "method": "failingMethod",
            "callId": "test-3",
        ]

        router.handle(message: message) { result in
            XCTAssertNil(result)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2.0)
    }

    // MARK: - Missing Plugin Field

    func testMissingPluginField() {
        let router = PluginRouter()

        let expectation = XCTestExpectation(description: "Returns nil for missing plugin field")

        let message: [String: Any] = [
            "type": "request",
            "method": "test",
            "callId": "test-4",
        ]

        router.handle(message: message) { result in
            XCTAssertNil(result)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2.0)
    }

    // MARK: - Missing Method Field

    func testMissingMethodField() {
        let router = PluginRouter()
        let plugin = MockPlugin()
        router.register(plugin: plugin)

        let expectation = XCTestExpectation(description: "Returns nil for missing method field")

        let message: [String: Any] = [
            "type": "request",
            "plugin": "mock",
            "callId": "test-5",
        ]

        router.handle(message: message) { result in
            XCTAssertNil(result)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2.0)
    }

    // MARK: - Multiple Plugins

    func testMultiplePlugins() {
        let router = PluginRouter()
        let mockPlugin = MockPlugin()
        let anotherPlugin = AnotherPlugin()

        router.register(plugin: mockPlugin)
        router.register(plugin: anotherPlugin)

        XCTAssertTrue(router.hasPlugin(named: "mock"))
        XCTAssertTrue(router.hasPlugin(named: "another"))
        XCTAssertFalse(router.hasPlugin(named: "unknown"))

        let expectation = XCTestExpectation(description: "Routes to correct plugin")

        let message: [String: Any] = [
            "type": "request",
            "plugin": "another",
            "method": "hello",
            "callId": "test-6",
        ]

        router.handle(message: message) { result in
            if let dict = result as? [String: Any] {
                XCTAssertEqual(dict["plugin"] as? String, "another")
                XCTAssertEqual(dict["method"] as? String, "hello")
            } else {
                XCTFail("Expected dictionary result")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2.0)
    }

    // MARK: - Unregister

    func testUnregister() {
        let router = PluginRouter()
        let plugin = MockPlugin()

        router.register(plugin: plugin)
        XCTAssertTrue(router.hasPlugin(named: "mock"))

        router.unregister(pluginName: "mock")
        XCTAssertFalse(router.hasPlugin(named: "mock"))
    }

    // MARK: - Default Params

    func testDefaultEmptyParams() {
        let router = PluginRouter()
        let plugin = MockPlugin()
        router.register(plugin: plugin)

        let expectation = XCTestExpectation(description: "Empty params default")

        // Message without explicit params field
        let message: [String: Any] = [
            "type": "request",
            "plugin": "mock",
            "method": "noParams",
            "callId": "test-7",
        ]

        router.handle(message: message) { _ in
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2.0)

        XCTAssertEqual(plugin.lastMethod, "noParams")
        XCTAssertNotNil(plugin.lastParams)
        XCTAssertTrue(plugin.lastParams?.isEmpty ?? false)
    }
}
