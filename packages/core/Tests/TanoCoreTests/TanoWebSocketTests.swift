import XCTest
import JavaScriptCore
@testable import TanoCore

final class TanoWebSocketTests: XCTestCase {

    private var ctx: JSContext!

    override func setUp() {
        super.setUp()
        ctx = JSContext()!
        ctx.exceptionHandler = { _, exception in
            let msg = exception?.toString() ?? "unknown"
            print("JS exception: \(msg)")
        }

        // Inject WebSocket (which also needs JSCHelpers)
        TanoWebSocket.inject(into: ctx, jscPerform: { block in block() })
    }

    override func tearDown() {
        ctx = nil
        super.tearDown()
    }

    // MARK: - Tests

    func testWebSocketConstructorExists() {
        let result = ctx.evaluateScript("typeof WebSocket")
        XCTAssertEqual(result?.toString(), "function")
    }

    func testWebSocketReadyState() {
        // A newly created WebSocket should start in CONNECTING (0) state.
        // We use a dummy URL — the native task will fail, but readyState
        // is set synchronously before the connection attempt resolves.
        let result = ctx.evaluateScript("""
            var ws = new WebSocket('ws://localhost:1');
            ws.readyState;
        """)
        XCTAssertEqual(result?.toInt32(), 0)
    }

    func testWebSocketConstants() {
        let connecting = ctx.evaluateScript("WebSocket.CONNECTING")
        let open = ctx.evaluateScript("WebSocket.OPEN")
        let closing = ctx.evaluateScript("WebSocket.CLOSING")
        let closed = ctx.evaluateScript("WebSocket.CLOSED")

        XCTAssertEqual(connecting?.toInt32(), 0)
        XCTAssertEqual(open?.toInt32(), 1)
        XCTAssertEqual(closing?.toInt32(), 2)
        XCTAssertEqual(closed?.toInt32(), 3)
    }

    func testWebSocketInstanceConstants() {
        let result = ctx.evaluateScript("""
            var ws = new WebSocket('ws://localhost:1');
            [ws.CONNECTING, ws.OPEN, ws.CLOSING, ws.CLOSED].join(',');
        """)
        XCTAssertEqual(result?.toString(), "0,1,2,3")
    }

    func testWebSocketRequiresNewOperator() {
        // Calling without `new` should throw
        let result = ctx.evaluateScript("""
            var threw = false;
            try { WebSocket('ws://localhost:1'); } catch(e) { threw = true; }
            threw;
        """)
        XCTAssertEqual(result?.toBool(), true)
    }

    func testWebSocketSendThrowsWhenConnecting() {
        // send() while still CONNECTING should throw
        let result = ctx.evaluateScript("""
            var ws = new WebSocket('ws://localhost:1');
            var threw = false;
            try { ws.send('hello'); } catch(e) { threw = true; }
            threw;
        """)
        XCTAssertEqual(result?.toBool(), true)
    }

    func testWebSocketCloseChangesReadyState() {
        let result = ctx.evaluateScript("""
            var ws = new WebSocket('ws://localhost:1');
            ws.close();
            ws.readyState;
        """)
        // After close(), readyState should be CLOSING (2)
        XCTAssertEqual(result?.toInt32(), 2)
    }

    func testNativeBridgeFunctionsExist() {
        let create = ctx.evaluateScript("typeof _nativeWebSocketCreate")
        let send = ctx.evaluateScript("typeof _nativeWebSocketSend")
        let close = ctx.evaluateScript("typeof _nativeWebSocketClose")

        XCTAssertEqual(create?.toString(), "function")
        XCTAssertEqual(send?.toString(), "function")
        XCTAssertEqual(close?.toString(), "function")
    }
}
