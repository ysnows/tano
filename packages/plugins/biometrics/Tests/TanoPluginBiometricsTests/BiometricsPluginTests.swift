import XCTest
@testable import TanoPluginBiometrics

final class BiometricsPluginTests: XCTestCase {

    private var plugin: BiometricsPlugin!

    override func setUp() {
        super.setUp()
        plugin = BiometricsPlugin()
    }

    override func tearDown() {
        plugin = nil
        super.tearDown()
    }

    // MARK: - testPluginName

    func testPluginName() {
        XCTAssertEqual(BiometricsPlugin.name, "biometrics")
        XCTAssertEqual(BiometricsPlugin.permissions, ["biometrics"])
    }

    // MARK: - testAuthenticateReturnsSuccess (stub on macOS)

    func testAuthenticateReturnsSuccess() async throws {
        let result = try await plugin.handle(method: "authenticate", params: [
            "reason": "Confirm action"
        ])
        let dict = try XCTUnwrap(result as? [String: Any])
        let success = try XCTUnwrap(dict["success"] as? Bool)
        XCTAssertTrue(success)
    }

    // MARK: - testMissingReason

    func testMissingReason() async {
        do {
            _ = try await plugin.handle(method: "authenticate", params: [:])
            XCTFail("Should have thrown for missing reason parameter")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("reason"),
                          "Error should mention the missing 'reason' parameter")
        }
    }
}
