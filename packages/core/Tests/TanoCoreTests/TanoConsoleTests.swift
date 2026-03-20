import XCTest
import JavaScriptCore
@testable import TanoCore

final class TanoConsoleTests: XCTestCase {

    override func setUp() {
        super.setUp()
        TanoConsole.captureEnabled = true
        TanoConsole.clearCapturedLogs()
    }

    override func tearDown() {
        TanoConsole.captureEnabled = false
        TanoConsole.clearCapturedLogs()
        super.tearDown()
    }

    // MARK: - Tests

    func testConsoleLog() {
        let ctx = JSContext()!
        TanoConsole.inject(into: ctx)

        ctx.evaluateScript("console.log('hello', 'world');")

        XCTAssertEqual(TanoConsole.capturedLogs.count, 1)
        XCTAssertEqual(TanoConsole.capturedLogs[0].level, "log")
        XCTAssertEqual(TanoConsole.capturedLogs[0].message, "hello world")
    }

    func testConsoleWarn() {
        let ctx = JSContext()!
        TanoConsole.inject(into: ctx)

        ctx.evaluateScript("console.warn('be careful');")

        XCTAssertEqual(TanoConsole.capturedLogs.count, 1)
        XCTAssertEqual(TanoConsole.capturedLogs[0].level, "warn")
        XCTAssertEqual(TanoConsole.capturedLogs[0].message, "be careful")
    }

    func testConsoleError() {
        let ctx = JSContext()!
        TanoConsole.inject(into: ctx)

        ctx.evaluateScript("console.error('something broke');")

        XCTAssertEqual(TanoConsole.capturedLogs.count, 1)
        XCTAssertEqual(TanoConsole.capturedLogs[0].level, "error")
        XCTAssertEqual(TanoConsole.capturedLogs[0].message, "something broke")
    }

    func testConsoleMultipleCalls() {
        let ctx = JSContext()!
        TanoConsole.inject(into: ctx)

        ctx.evaluateScript("""
            console.log('one');
            console.info('two');
            console.debug('three');
            console.warn('four');
            console.error('five');
        """)

        XCTAssertEqual(TanoConsole.capturedLogs.count, 5)
        XCTAssertEqual(TanoConsole.capturedLogs[0].level, "log")
        XCTAssertEqual(TanoConsole.capturedLogs[1].level, "info")
        XCTAssertEqual(TanoConsole.capturedLogs[2].level, "debug")
        XCTAssertEqual(TanoConsole.capturedLogs[3].level, "warn")
        XCTAssertEqual(TanoConsole.capturedLogs[4].level, "error")
    }
}
