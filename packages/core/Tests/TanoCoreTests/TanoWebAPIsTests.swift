import XCTest
import JavaScriptCore
@testable import TanoCore

final class TanoWebAPIsTests: XCTestCase {

    private var ctx: JSContext!

    override func setUp() {
        super.setUp()
        ctx = JSContext()!
        ctx.exceptionHandler = { _, exception in
            let msg = exception?.toString() ?? "unknown"
            XCTFail("JS exception: \(msg)")
        }
        TanoWebAPIs.inject(into: ctx)
    }

    override func tearDown() {
        ctx = nil
        super.tearDown()
    }

    // MARK: - Headers

    func testHeadersBasic() {
        let result = ctx.evaluateScript("""
            var h = new Headers({ 'Content-Type': 'text/html' });
            [h.get('Content-Type'), h.has('Content-Type'), h.has('X-Missing')].join(',');
        """)
        XCTAssertEqual(result?.toString(), "text/html,true,false")
    }

    func testHeadersCaseInsensitive() {
        let result = ctx.evaluateScript("""
            var h = new Headers();
            h.set('Content-Type', 'application/json');
            h.get('content-type');
        """)
        XCTAssertEqual(result?.toString(), "application/json")
    }

    // MARK: - Response

    func testResponseBasic() {
        let status = ctx.evaluateScript("""
            var r = new Response('hello', { status: 201, statusText: 'Created' });
            [r.status, r.statusText, r.ok].join(',');
        """)
        XCTAssertEqual(status?.toString(), "201,Created,true")
    }

    func testResponseJson() {
        let result = ctx.evaluateScript("""
            var r = Response.json({ name: 'tano' });
            var out = '';
            r.text().then(function(t) { out = t; });
            out;
        """)
        XCTAssertEqual(result?.toString(), "{\"name\":\"tano\"}")
    }

    func testResponseText() {
        let result = ctx.evaluateScript("""
            var r = new Response('body content');
            var out = '';
            r.text().then(function(t) { out = t; });
            out;
        """)
        XCTAssertEqual(result?.toString(), "body content")
    }

    // MARK: - Request

    func testRequestBasic() {
        let result = ctx.evaluateScript("""
            var req = new Request('https://example.com/api', { method: 'POST' });
            [req.url, req.method].join(',');
        """)
        XCTAssertEqual(result?.toString(), "https://example.com/api,POST")
    }

    // MARK: - URL

    func testURLExists() {
        let result = ctx.evaluateScript("""
            var u = new URL('https://example.com/path?q=1');
            u.pathname;
        """)
        XCTAssertEqual(result?.toString(), "/path")
    }
}
