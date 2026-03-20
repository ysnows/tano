import XCTest
@testable import TanoPluginNotifications

final class NotificationsPluginTests: XCTestCase {

    private var plugin: NotificationsPlugin!

    override func setUp() {
        super.setUp()
        plugin = NotificationsPlugin()
    }

    override func tearDown() {
        plugin = nil
        super.tearDown()
    }

    // MARK: - testPluginName

    func testPluginName() {
        XCTAssertEqual(NotificationsPlugin.name, "notifications")
        XCTAssertEqual(NotificationsPlugin.permissions, ["notifications"])
    }

    // MARK: - testRequestPermission (stub)

    func testRequestPermission() async throws {
        let result = try await plugin.handle(method: "requestPermission", params: [:])
        let dict = try XCTUnwrap(result as? [String: Any])
        // On macOS test runner this uses the real UNUserNotificationCenter,
        // which may or may not grant. We just verify the shape.
        XCTAssertNotNil(dict["granted"])
    }

    // MARK: - testSchedule (stub returns id)

    func testSchedule() async throws {
        let result = try await plugin.handle(method: "schedule", params: [
            "title": "Reminder",
            "body": "Don't forget!",
            "delay": 5
        ])
        let dict = try XCTUnwrap(result as? [String: Any])
        let id = try XCTUnwrap(dict["id"] as? String)
        XCTAssertFalse(id.isEmpty, "Schedule should return a non-empty notification id")
    }

    // MARK: - testCancel (stub)

    func testCancel() async throws {
        let result = try await plugin.handle(method: "cancel", params: [
            "id": "some-notification-id"
        ])
        let dict = try XCTUnwrap(result as? [String: Any])
        let success = try XCTUnwrap(dict["success"] as? Bool)
        XCTAssertTrue(success)
    }

    // MARK: - testScheduleMissingTitle

    func testScheduleMissingTitle() async {
        do {
            _ = try await plugin.handle(method: "schedule", params: [
                "body": "No title provided"
            ])
            XCTFail("Should have thrown for missing title parameter")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("title"),
                          "Error should mention the missing 'title' parameter")
        }
    }
}
