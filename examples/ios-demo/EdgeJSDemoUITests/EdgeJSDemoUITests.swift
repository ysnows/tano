import XCTest

final class EdgeJSDemoUITests: XCTestCase {
    func testTapStart() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Wait for UI to load
        let startButton = app.buttons["Start"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5))
        
        // Tap Start
        startButton.tap()
        
        // Wait for output to change
        sleep(3)
        
        // Take screenshot for verification
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.lifetime = .keepAlways
        add(attachment)
        
        // Check that output changed from the initial state
        let output = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'EdgeJSManager'")).firstMatch
        XCTAssertTrue(output.exists)
        
        // Print the output text
        print("OUTPUT: \(output.label)")
    }
}
