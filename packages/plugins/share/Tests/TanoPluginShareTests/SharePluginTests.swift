import XCTest
@testable import TanoPluginShare

final class SharePluginTests: XCTestCase {

    private var plugin: SharePlugin!

    override func setUp() {
        super.setUp()
        plugin = SharePlugin()
    }

    override func tearDown() {
        plugin = nil
        super.tearDown()
    }

    // MARK: - testPluginName

    func testPluginName() {
        XCTAssertEqual(SharePlugin.name, "share")
        XCTAssertEqual(SharePlugin.permissions, [])
    }

    // MARK: - testShareText (stub returns success on macOS)

    func testShareText() async throws {
        let result = try await plugin.handle(method: "share", params: [
            "text": "Check out Tano!"
        ])
        let dict = try XCTUnwrap(result as? [String: Any])
        let success = try XCTUnwrap(dict["success"] as? Bool)
        XCTAssertTrue(success)
    }

    // MARK: - testShareTextWithURL

    func testShareTextWithURL() async throws {
        let result = try await plugin.handle(method: "share", params: [
            "text": "Check out Tano!",
            "url": "https://github.com/example/tano"
        ])
        let dict = try XCTUnwrap(result as? [String: Any])
        let success = try XCTUnwrap(dict["success"] as? Bool)
        XCTAssertTrue(success)
    }

    // MARK: - testMissingText

    func testMissingText() async {
        do {
            _ = try await plugin.handle(method: "share", params: [:])
            XCTFail("Should have thrown for missing text parameter")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("text"),
                          "Error should mention the missing 'text' parameter")
        }
    }
}
