import XCTest
import JavaScriptCore
@testable import TanoCore

final class TanoFetchTests: XCTestCase {

    private var ctx: JSContext!

    override func setUp() {
        super.setUp()
        ctx = JSContext()!
        ctx.exceptionHandler = { _, exception in
            let msg = exception?.toString() ?? "unknown"
            print("JS exception: \(msg)")
        }

        // Inject prerequisites: Web APIs (Headers, Response, Request) and fetch
        TanoWebAPIs.inject(into: ctx)
        TanoFetch.inject(into: ctx, jscPerform: { block in block() })
    }

    override func tearDown() {
        ctx = nil
        super.tearDown()
    }

    // MARK: - Tests

    func testFetchFunctionExists() {
        let result = ctx.evaluateScript("typeof fetch")
        XCTAssertEqual(result?.toString(), "function")
    }

    func testFetchReturnsPromise() {
        // fetch returns a Promise, which should have a .then method
        let result = ctx.evaluateScript("""
            var p = fetch('http://localhost:99999/nonexistent');
            typeof p.then;
        """)
        XCTAssertEqual(result?.toString(), "function")
    }

    func testNativeFetchExists() {
        let result = ctx.evaluateScript("typeof _nativeFetch")
        XCTAssertEqual(result?.toString(), "function")
    }
}
