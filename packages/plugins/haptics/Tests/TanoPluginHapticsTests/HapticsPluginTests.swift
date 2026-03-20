import XCTest
@testable import TanoPluginHaptics

final class HapticsPluginTests: XCTestCase {

    private var plugin: HapticsPlugin!

    override func setUp() {
        super.setUp()
        plugin = HapticsPlugin()
    }

    override func tearDown() {
        plugin = nil
        super.tearDown()
    }

    // MARK: - testPluginName

    func testPluginName() {
        XCTAssertEqual(HapticsPlugin.name, "haptics")
        XCTAssertEqual(HapticsPlugin.permissions, [])
    }

    // MARK: - testImpactLight

    func testImpactLight() async throws {
        let result = try await plugin.handle(method: "impact", params: ["style": "light"])
        let dict = try XCTUnwrap(result as? [String: Any])
        XCTAssertEqual(dict["success"] as? Bool, true)
    }

    // MARK: - testImpactMedium

    func testImpactMedium() async throws {
        let result = try await plugin.handle(method: "impact", params: ["style": "medium"])
        let dict = try XCTUnwrap(result as? [String: Any])
        XCTAssertEqual(dict["success"] as? Bool, true)
    }

    // MARK: - testNotificationSuccess

    func testNotificationSuccess() async throws {
        let result = try await plugin.handle(method: "notification", params: ["type": "success"])
        let dict = try XCTUnwrap(result as? [String: Any])
        XCTAssertEqual(dict["success"] as? Bool, true)
    }

    // MARK: - testSelection

    func testSelection() async throws {
        let result = try await plugin.handle(method: "selection", params: [:])
        let dict = try XCTUnwrap(result as? [String: Any])
        XCTAssertEqual(dict["success"] as? Bool, true)
    }

    // MARK: - testInvalidStyle

    func testInvalidStyle() async {
        do {
            _ = try await plugin.handle(method: "impact", params: ["style": "ultra"])
            XCTFail("Expected an error for invalid style")
        } catch {
            XCTAssertTrue(error is HapticsPluginError)
            if case .invalidParameter(let param, let value) = error as? HapticsPluginError {
                XCTAssertEqual(param, "style")
                XCTAssertEqual(value, "ultra")
            } else {
                XCTFail("Expected invalidParameter error, got \(error)")
            }
        }
    }
}
