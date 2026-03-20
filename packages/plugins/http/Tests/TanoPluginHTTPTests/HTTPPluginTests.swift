import XCTest
@testable import TanoPluginHTTP

final class HTTPPluginTests: XCTestCase {

    private var plugin: HTTPPlugin!

    override func setUp() {
        super.setUp()
        plugin = HTTPPlugin()
    }

    override func tearDown() {
        plugin = nil
        super.tearDown()
    }

    // MARK: - testPluginName

    func testPluginName() {
        XCTAssertEqual(HTTPPlugin.name, "http")
        XCTAssertEqual(HTTPPlugin.permissions, ["network"])
    }

    // MARK: - testRequestFunctionExists

    func testRequestFunctionExists() async throws {
        // Verify the plugin can route the "request" method without crashing.
        // We use a known-good URL so we get a real response.
        let result = try await plugin.handle(method: "request", params: [
            "url": "https://httpbin.org/get",
            "method": "GET"
        ])
        let dict = try XCTUnwrap(result as? [String: Any])
        let status = try XCTUnwrap(dict["status"] as? Int)
        XCTAssertEqual(status, 200)
        XCTAssertNotNil(dict["headers"])
        XCTAssertNotNil(dict["body"])
    }

    // MARK: - testMissingURL

    func testMissingURL() async {
        do {
            _ = try await plugin.handle(method: "request", params: [
                "method": "GET"
            ])
            XCTFail("Should have thrown for missing url parameter")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("url"),
                          "Error should mention the missing 'url' parameter")
        }
    }

    // MARK: - testUnknownMethod

    func testUnknownMethod() async {
        do {
            _ = try await plugin.handle(method: "nonexistent", params: [:])
            XCTFail("Should have thrown for unknown method")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("nonexistent"))
        }
    }
}
