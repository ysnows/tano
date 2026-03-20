import XCTest
@testable import TanoBridge

final class TanoBridgeMessageTests: XCTestCase {

    // MARK: - Request

    func testCreateRequest() {
        let msg = TanoBridgeMessage.request(
            callId: "call-1",
            plugin: "clipboard",
            method: "read",
            params: ["format": "text"]
        )

        XCTAssertEqual(msg[TanoBridgeMessage.Keys.type] as? String, "request")
        XCTAssertEqual(msg[TanoBridgeMessage.Keys.callId] as? String, "call-1")
        XCTAssertEqual(msg[TanoBridgeMessage.Keys.plugin] as? String, "clipboard")
        XCTAssertEqual(msg[TanoBridgeMessage.Keys.method] as? String, "read")

        let params = msg[TanoBridgeMessage.Keys.params] as? [String: Any]
        XCTAssertNotNil(params)
        XCTAssertEqual(params?["format"] as? String, "text")
    }

    func testCreateRequestDefaultParams() {
        let msg = TanoBridgeMessage.request(
            callId: "call-2",
            plugin: "test",
            method: "ping"
        )

        let params = msg[TanoBridgeMessage.Keys.params] as? [String: Any]
        XCTAssertNotNil(params)
        XCTAssertTrue(params?.isEmpty ?? false)
    }

    // MARK: - Response

    func testCreateResponse() {
        let msg = TanoBridgeMessage.response(
            callId: "call-1",
            plugin: "clipboard",
            method: "read",
            params: ["data": "Hello World"]
        )

        XCTAssertEqual(msg[TanoBridgeMessage.Keys.type] as? String, "response")
        XCTAssertEqual(msg[TanoBridgeMessage.Keys.callId] as? String, "call-1")
        XCTAssertEqual(msg[TanoBridgeMessage.Keys.plugin] as? String, "clipboard")
        XCTAssertEqual(msg[TanoBridgeMessage.Keys.method] as? String, "read")

        let params = msg[TanoBridgeMessage.Keys.params] as? [String: Any]
        XCTAssertEqual(params?["data"] as? String, "Hello World")
    }

    // MARK: - Response Stream

    func testCreateResponseStream() {
        let msg = TanoBridgeMessage.responseStream(
            callId: "call-3",
            plugin: "ai",
            method: "generate",
            params: ["chunk": "partial data"]
        )

        XCTAssertEqual(msg[TanoBridgeMessage.Keys.type] as? String, "responseStream")
        XCTAssertEqual(msg[TanoBridgeMessage.Keys.callId] as? String, "call-3")
        XCTAssertEqual(msg[TanoBridgeMessage.Keys.plugin] as? String, "ai")
    }

    // MARK: - Response End

    func testCreateResponseEnd() {
        let msg = TanoBridgeMessage.responseEnd(
            callId: "call-3",
            plugin: "ai",
            method: "generate"
        )

        XCTAssertEqual(msg[TanoBridgeMessage.Keys.type] as? String, "responseEnd")
        XCTAssertEqual(msg[TanoBridgeMessage.Keys.callId] as? String, "call-3")
    }

    // MARK: - Error

    func testCreateError() {
        let msg = TanoBridgeMessage.error(
            callId: "call-4",
            plugin: "network",
            method: "fetch",
            errorMessage: "Connection refused"
        )

        XCTAssertEqual(msg[TanoBridgeMessage.Keys.type] as? String, "error")
        XCTAssertEqual(msg[TanoBridgeMessage.Keys.callId] as? String, "call-4")
        XCTAssertEqual(msg[TanoBridgeMessage.Keys.plugin] as? String, "network")
        XCTAssertEqual(msg[TanoBridgeMessage.Keys.method] as? String, "fetch")

        let params = msg[TanoBridgeMessage.Keys.params] as? [String: Any]
        XCTAssertEqual(params?["error"] as? String, "Connection refused")
    }

    // MARK: - Event

    func testCreateEvent() {
        let msg = TanoBridgeMessage.event(
            plugin: "lifecycle",
            method: "appDidBecomeActive",
            params: ["timestamp": 12345]
        )

        XCTAssertEqual(msg[TanoBridgeMessage.Keys.type] as? String, "event")
        XCTAssertEqual(msg[TanoBridgeMessage.Keys.callId] as? String, "")
        XCTAssertEqual(msg[TanoBridgeMessage.Keys.plugin] as? String, "lifecycle")
        XCTAssertEqual(msg[TanoBridgeMessage.Keys.method] as? String, "appDidBecomeActive")

        let params = msg[TanoBridgeMessage.Keys.params] as? [String: Any]
        XCTAssertEqual(params?["timestamp"] as? Int, 12345)
    }

    // MARK: - JSON Serialization Round-Trip

    func testRequestJSONRoundTrip() {
        let msg = TanoBridgeMessage.request(
            callId: "roundtrip-1",
            plugin: "test",
            method: "echo",
            params: ["text": "hello", "count": 42]
        )

        // Should be valid JSON
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: msg))

        let data = try! JSONSerialization.data(withJSONObject: msg)
        let decoded = try! JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(decoded[TanoBridgeMessage.Keys.type] as? String, "request")
        XCTAssertEqual(decoded[TanoBridgeMessage.Keys.callId] as? String, "roundtrip-1")
        XCTAssertEqual(decoded[TanoBridgeMessage.Keys.plugin] as? String, "test")
        XCTAssertEqual(decoded[TanoBridgeMessage.Keys.method] as? String, "echo")

        let params = decoded[TanoBridgeMessage.Keys.params] as? [String: Any]
        XCTAssertEqual(params?["text"] as? String, "hello")
        XCTAssertEqual(params?["count"] as? Int, 42)
    }

    // MARK: - Keys Constants

    func testKeysConstants() {
        XCTAssertEqual(TanoBridgeMessage.Keys.type, "type")
        XCTAssertEqual(TanoBridgeMessage.Keys.method, "method")
        XCTAssertEqual(TanoBridgeMessage.Keys.callId, "callId")
        XCTAssertEqual(TanoBridgeMessage.Keys.plugin, "plugin")
        XCTAssertEqual(TanoBridgeMessage.Keys.params, "params")
    }

    // MARK: - Types Constants

    func testTypesConstants() {
        XCTAssertEqual(TanoBridgeMessage.Types.request, "request")
        XCTAssertEqual(TanoBridgeMessage.Types.response, "response")
        XCTAssertEqual(TanoBridgeMessage.Types.responseStream, "responseStream")
        XCTAssertEqual(TanoBridgeMessage.Types.responseEnd, "responseEnd")
        XCTAssertEqual(TanoBridgeMessage.Types.error, "error")
        XCTAssertEqual(TanoBridgeMessage.Types.event, "event")
    }
}
