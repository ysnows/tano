import XCTest
@testable import TanoCore

final class TanoDeepLinkTests: XCTestCase {

    // MARK: - Parse Tests

    func testParseSimplePath() {
        let url = URL(string: "myapp:///settings")!
        let (path, params) = TanoDeepLink.parse(url: url)

        XCTAssertEqual(path, "/settings")
        XCTAssertTrue(params.isEmpty, "Expected no query params")
    }

    func testParseWithQuery() {
        let url = URL(string: "myapp:///user?id=123&tab=profile")!
        let (path, params) = TanoDeepLink.parse(url: url)

        XCTAssertEqual(path, "/user")
        XCTAssertEqual(params["id"], "123")
        XCTAssertEqual(params["tab"], "profile")
        XCTAssertEqual(params.count, 2)
    }

    func testParseRootPath() {
        let url = URL(string: "myapp:///")!
        let (path, params) = TanoDeepLink.parse(url: url)

        XCTAssertEqual(path, "/")
        XCTAssertTrue(params.isEmpty)
    }

    func testParseHTTPSUniversalLink() {
        let url = URL(string: "https://example.com/products?category=shoes&sort=price")!
        let (path, params) = TanoDeepLink.parse(url: url)

        XCTAssertEqual(path, "/products")
        XCTAssertEqual(params["category"], "shoes")
        XCTAssertEqual(params["sort"], "price")
    }

    func testParseEmptyPath() {
        // URL with host but no path — path should default to "/"
        let url = URL(string: "myapp://host")!
        let (path, _) = TanoDeepLink.parse(url: url)

        // When there's no path component the parser returns "/"
        XCTAssertEqual(path, "/")
    }

    // MARK: - Navigation JS Tests

    func testNavigationJSContainsPushState() {
        let js = TanoDeepLink.navigationJS(path: "/settings", params: [:])

        XCTAssertTrue(js.contains("pushState"), "JS should use history.pushState")
        XCTAssertTrue(js.contains("popstate"), "JS should dispatch popstate event")
        XCTAssertTrue(js.contains("/settings"), "JS should contain the path")
    }

    func testNavigationJSContainsQueryParams() {
        let js = TanoDeepLink.navigationJS(path: "/user", params: ["id": "42"])

        XCTAssertTrue(js.contains("/user"), "JS should contain the path")
        XCTAssertTrue(js.contains("id=42"), "JS should contain query params")
    }

    func testNavigationJSEmitsDeepLinkEvent() {
        let js = TanoDeepLink.navigationJS(path: "/page", params: ["key": "value"])

        XCTAssertTrue(js.contains("Tano._emit"), "JS should emit deepLink event via Tano._emit")
        XCTAssertTrue(js.contains("deepLink"), "JS should emit 'deepLink' event name")
    }

    // MARK: - Params JSON Tests

    func testParamsJSONEmpty() {
        let json = TanoDeepLink.paramsJSON([:])
        XCTAssertEqual(json, "{}")
    }

    func testParamsJSONSinglePair() {
        let json = TanoDeepLink.paramsJSON(["key": "value"])
        XCTAssertTrue(json.contains("\"key\": \"value\""), "JSON should contain the key-value pair")
    }

    func testParamsJSONMultiplePairs() {
        let json = TanoDeepLink.paramsJSON(["a": "1", "b": "2"])
        // Keys are sorted alphabetically
        XCTAssertTrue(json.contains("\"a\": \"1\""), "JSON should contain a=1")
        XCTAssertTrue(json.contains("\"b\": \"2\""), "JSON should contain b=2")
    }

    func testParamsJSONEscapesSpecialChars() {
        let json = TanoDeepLink.paramsJSON(["msg": "hello'world"])
        XCTAssertTrue(json.contains("\\'"), "JSON should escape single quotes")
    }
}
