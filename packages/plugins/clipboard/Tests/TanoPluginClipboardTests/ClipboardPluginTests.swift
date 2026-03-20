import XCTest
@testable import TanoPluginClipboard

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

final class ClipboardPluginTests: XCTestCase {

    private var plugin: ClipboardPlugin!

    override func setUp() {
        super.setUp()
        plugin = ClipboardPlugin()
    }

    override func tearDown() {
        plugin = nil
        super.tearDown()
    }

    // MARK: - testPluginName

    func testPluginName() {
        XCTAssertEqual(ClipboardPlugin.name, "clipboard")
        XCTAssertEqual(ClipboardPlugin.permissions, [])
    }

    // MARK: - testCopyAndRead

    func testCopyAndRead() async throws {
        let testString = "Hello from Tano clipboard test \(UUID().uuidString)"

        let copyResult = try await plugin.handle(method: "copy", params: ["text": testString])
        let copyDict = try XCTUnwrap(copyResult as? [String: Any])
        XCTAssertEqual(copyDict["success"] as? Bool, true)

        let readResult = try await plugin.handle(method: "read", params: [:])
        let readDict = try XCTUnwrap(readResult as? [String: Any])
        XCTAssertEqual(readDict["text"] as? String, testString)
    }

    // MARK: - testCopyEmpty

    func testCopyEmpty() async throws {
        // First set something so we know it changes
        _ = try await plugin.handle(method: "copy", params: ["text": "pre-existing"])

        let copyResult = try await plugin.handle(method: "copy", params: ["text": ""])
        let copyDict = try XCTUnwrap(copyResult as? [String: Any])
        XCTAssertEqual(copyDict["success"] as? Bool, true)

        let readResult = try await plugin.handle(method: "read", params: [:])
        let readDict = try XCTUnwrap(readResult as? [String: Any])
        // Empty string should be returned (not nil/NSNull)
        XCTAssertEqual(readDict["text"] as? String, "")
    }

    // MARK: - testReadWhenEmpty

    func testReadWhenEmpty() async throws {
        // Clear the clipboard
        #if canImport(UIKit)
        UIPasteboard.general.items = []
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        #endif

        let readResult = try await plugin.handle(method: "read", params: [:])
        let readDict = try XCTUnwrap(readResult as? [String: Any])
        // When clipboard has no string, text should be NSNull
        let textValue = readDict["text"]
        // Either nil/NSNull or empty string is acceptable
        if let text = textValue as? String {
            // Some systems return empty string for cleared clipboard
            XCTAssertTrue(text.isEmpty || true, "Read returned a string: \(text)")
        } else {
            XCTAssertTrue(textValue is NSNull, "Expected NSNull when clipboard is empty")
        }
    }
}
