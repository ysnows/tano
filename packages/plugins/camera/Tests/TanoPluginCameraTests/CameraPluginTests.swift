import XCTest
@testable import TanoPluginCamera

final class CameraPluginTests: XCTestCase {

    private var plugin: CameraPlugin!

    override func setUp() {
        super.setUp()
        plugin = CameraPlugin()
    }

    override func tearDown() {
        plugin = nil
        super.tearDown()
    }

    // MARK: - testPluginName

    func testPluginName() {
        XCTAssertEqual(CameraPlugin.name, "camera")
        XCTAssertEqual(CameraPlugin.permissions, ["camera", "photos"])
    }

    // MARK: - testTakePictureStub

    func testTakePictureStub() async {
        // On macOS test runner, camera is unavailable — should throw
        do {
            _ = try await plugin.handle(method: "takePicture", params: [
                "camera": "back"
            ])
            XCTFail("takePicture should throw on macOS test environment")
        } catch {
            XCTAssertTrue(
                error.localizedDescription.contains("not available"),
                "Error should indicate camera is not available, got: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - testPickImageStub

    func testPickImageStub() async {
        // On macOS test runner, photo library picker is unavailable — should throw
        do {
            _ = try await plugin.handle(method: "pickImage", params: [:])
            XCTFail("pickImage should throw on macOS test environment")
        } catch {
            XCTAssertTrue(
                error.localizedDescription.contains("not available"),
                "Error should indicate camera/picker is not available, got: \(error.localizedDescription)"
            )
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
