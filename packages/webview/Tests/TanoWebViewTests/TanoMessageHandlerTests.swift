#if canImport(WebKit)
import XCTest
import WebKit
@testable import TanoWebView
@testable import TanoBridge

// MARK: - Mock Plugin

private class MockPlugin: TanoPlugin {
    static var name: String = "mock"
    static var permissions: [String] = []

    var lastMethod: String?
    var lastParams: [String: Any]?
    var resultToReturn: Any?
    var errorToThrow: Error?

    func handle(method: String, params: [String: Any]) async throws -> Any? {
        lastMethod = method
        lastParams = params
        if let error = errorToThrow {
            throw error
        }
        return resultToReturn
    }
}

// MARK: - TanoMessageHandlerTests

final class TanoMessageHandlerTests: XCTestCase {

    private var handler: TanoMessageHandler!
    private var router: PluginRouter!
    private var mockPlugin: MockPlugin!

    override func setUp() {
        super.setUp()
        handler = TanoMessageHandler()
        router = PluginRouter()
        mockPlugin = MockPlugin()
        router.register(plugin: mockPlugin)
        handler.pluginRouter = router
    }

    override func tearDown() {
        handler = nil
        router = nil
        mockPlugin = nil
        super.tearDown()
    }

    // MARK: - Event Handling

    func testEventHandlerReceivesEvents() {
        let expectation = expectation(description: "Event received")
        var receivedEvent: String?
        var receivedData: [String: Any]?

        handler.onEvent = { event, data in
            receivedEvent = event
            receivedData = data
            expectation.fulfill()
        }

        // Simulate what WKScriptMessageHandler receives
        // We can't easily create a WKScriptMessage, so we test the internal methods
        // by directly calling the private handleEvent logic through the public interface.
        // Instead, we test the event callback setup.
        handler.onEvent?("testEvent", ["key": "value"])

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedEvent, "testEvent")
        XCTAssertEqual(receivedData?["key"] as? String, "value")
    }

    // MARK: - Resolve / Reject JS Generation

    func testResolveInWebViewWithDictionary() {
        // Test that resolveInWebView generates correct JS when called
        // Since we don't have a real WKWebView, we verify the handler doesn't crash
        // with valid input (integration test verifies actual WebView behavior).
        handler.resolveInWebView(callId: "1", result: ["name": "test"])
        // No crash = pass (real integration test needed for JS execution)
    }

    func testResolveInWebViewWithNull() {
        handler.resolveInWebView(callId: "2", result: nil)
        // No crash = pass
    }

    func testRejectInWebView() {
        handler.rejectInWebView(callId: "3", error: "Something went wrong")
        // No crash = pass
    }

    func testRejectInWebViewWithSpecialCharacters() {
        handler.rejectInWebView(callId: "4", error: "Error with 'quotes' and\nnewlines")
        // No crash = pass (special characters should be escaped)
    }

    // MARK: - Emit Events

    func testEmitEventInWebView() {
        handler.emitEventInWebView(event: "update", data: ["status": "ok"])
        // No crash = pass
    }

    func testEmitEventWithEmptyData() {
        handler.emitEventInWebView(event: "ping", data: [:])
        // No crash = pass
    }

    // MARK: - Plugin Router Integration

    func testPluginIsRegistered() {
        XCTAssertTrue(router.hasPlugin(named: "mock"))
    }

    func testPluginRoutingViaHandle() {
        let expectation = expectation(description: "Plugin handles message")

        mockPlugin.resultToReturn = ["greeting": "hello"]

        let message = TanoBridgeMessage.request(
            callId: "test-1",
            plugin: "mock",
            method: "greet",
            params: ["name": "world"]
        )

        router.handle(message: message) { result in
            XCTAssertNotNil(result)
            if let dict = result as? [String: String] {
                XCTAssertEqual(dict["greeting"], "hello")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2.0)
        XCTAssertEqual(mockPlugin.lastMethod, "greet")
        XCTAssertEqual(mockPlugin.lastParams?["name"] as? String, "world")
    }

    func testPluginRoutingUnknownPlugin() {
        let expectation = expectation(description: "Unknown plugin returns nil")

        let message = TanoBridgeMessage.request(
            callId: "test-2",
            plugin: "nonexistent",
            method: "doSomething",
            params: [:]
        )

        router.handle(message: message) { result in
            XCTAssertNil(result)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2.0)
    }

    func testPluginRoutingWithError() {
        let expectation = expectation(description: "Plugin error returns nil")

        mockPlugin.errorToThrow = NSError(
            domain: "test",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Test error"]
        )

        let message = TanoBridgeMessage.request(
            callId: "test-3",
            plugin: "mock",
            method: "fail",
            params: [:]
        )

        router.handle(message: message) { result in
            XCTAssertNil(result, "Plugin error should result in nil response")
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2.0)
    }

    // MARK: - Handler Without Router

    func testHandlerWithoutRouterDoesNotCrash() {
        let noRouterHandler = TanoMessageHandler()
        noRouterHandler.pluginRouter = nil
        // Calling reject without a webView should not crash
        noRouterHandler.rejectInWebView(callId: "x", error: "no router")
    }
}
#endif
