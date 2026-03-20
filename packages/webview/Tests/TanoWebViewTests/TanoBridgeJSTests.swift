import XCTest
@testable import TanoWebView

final class TanoBridgeJSTests: XCTestCase {

    // MARK: - Script Validity

    func testScriptIsNotEmpty() {
        XCTAssertFalse(TanoBridgeJS.script.isEmpty, "Bridge JS script should not be empty")
    }

    func testScriptContainsWindowTano() {
        XCTAssertTrue(
            TanoBridgeJS.script.contains("window.Tano"),
            "Bridge JS should define window.Tano"
        )
    }

    // MARK: - Public API Methods

    func testScriptContainsInvoke() {
        XCTAssertTrue(
            TanoBridgeJS.script.contains("invoke: function(plugin, method, params)"),
            "Bridge JS should contain invoke function"
        )
    }

    func testScriptContainsOn() {
        XCTAssertTrue(
            TanoBridgeJS.script.contains("on: function(event, callback)"),
            "Bridge JS should contain on function"
        )
    }

    func testScriptContainsSend() {
        XCTAssertTrue(
            TanoBridgeJS.script.contains("send: function(event, data)"),
            "Bridge JS should contain send function"
        )
    }

    // MARK: - Internal Methods

    func testScriptContainsResolve() {
        XCTAssertTrue(
            TanoBridgeJS.script.contains("_resolve: function(callId, result)"),
            "Bridge JS should contain _resolve function"
        )
    }

    func testScriptContainsReject() {
        XCTAssertTrue(
            TanoBridgeJS.script.contains("_reject: function(callId, error)"),
            "Bridge JS should contain _reject function"
        )
    }

    func testScriptContainsEmit() {
        XCTAssertTrue(
            TanoBridgeJS.script.contains("_emit: function(event, data)"),
            "Bridge JS should contain _emit function"
        )
    }

    // MARK: - Internal State

    func testScriptContainsPendingCalls() {
        XCTAssertTrue(
            TanoBridgeJS.script.contains("_pendingCalls"),
            "Bridge JS should contain _pendingCalls store"
        )
    }

    func testScriptContainsEventListeners() {
        XCTAssertTrue(
            TanoBridgeJS.script.contains("_eventListeners"),
            "Bridge JS should contain _eventListeners store"
        )
    }

    func testScriptContainsCallId() {
        XCTAssertTrue(
            TanoBridgeJS.script.contains("_callId"),
            "Bridge JS should contain _callId counter"
        )
    }

    // MARK: - Message Posting

    func testScriptPostsToTanoHandler() {
        XCTAssertTrue(
            TanoBridgeJS.script.contains("window.webkit.messageHandlers.tano.postMessage"),
            "Bridge JS should post messages to the 'tano' message handler"
        )
    }

    // MARK: - Timeout

    func testScriptContainsTimeout() {
        XCTAssertTrue(
            TanoBridgeJS.script.contains("30000"),
            "Bridge JS should include 30-second timeout for invoke calls"
        )
    }

    // MARK: - IIFE Wrapper

    func testScriptIsIIFE() {
        let trimmed = TanoBridgeJS.script.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertTrue(
            trimmed.hasPrefix("(function()"),
            "Bridge JS should be wrapped in an IIFE"
        )
        XCTAssertTrue(
            trimmed.hasSuffix("})();"),
            "Bridge JS should end with IIFE invocation"
        )
    }
}
