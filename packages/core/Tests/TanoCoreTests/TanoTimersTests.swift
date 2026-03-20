import XCTest
import JavaScriptCore
@testable import TanoCore

final class TanoTimersTests: XCTestCase {

    // MARK: - Helpers

    private func makeTempEntry(script: String) throws -> (dir: URL, entry: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let entry = dir.appendingPathComponent("entry.js")
        try script.write(to: entry, atomically: true, encoding: .utf8)
        return (dir, entry)
    }

    private func waitForRunning(_ runtime: TanoRuntime) async throws {
        for _ in 0..<20 {
            try await Task.sleep(nanoseconds: 100_000_000)
            if case .running = runtime.state { return }
        }
        XCTFail("Runtime did not reach .running state (current: \(runtime.state))")
    }

    private func waitForStopped(_ runtime: TanoRuntime) async throws {
        for _ in 0..<20 {
            try await Task.sleep(nanoseconds: 100_000_000)
            if case .stopped = runtime.state { return }
        }
        XCTFail("Runtime did not reach .stopped state (current: \(runtime.state))")
    }

    // MARK: - Tests

    func testSetTimeout() async throws {
        let script = """
        globalThis.fired = false;
        setTimeout(function() { globalThis.fired = true; }, 50);
        """
        let (dir, entry) = try makeTempEntry(script: script)
        defer { try? FileManager.default.removeItem(at: dir) }

        let config = TanoConfig(serverEntry: entry.path, dataPath: dir.path)
        let runtime = TanoRuntime(config: config)
        runtime.start()
        try await waitForRunning(runtime)

        // Wait long enough for the 50ms timer to fire.
        try await Task.sleep(nanoseconds: 400_000_000)

        let expectation = XCTestExpectation(description: "Read fired flag")
        var fired = false

        runtime.performOnJSCThread { [weak runtime] in
            guard let ctx = runtime?.jsContext else {
                XCTFail("JSContext is nil")
                expectation.fulfill()
                return
            }
            fired = ctx.globalObject.forProperty("fired")?.toBool() ?? false
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertTrue(fired, "setTimeout callback should have fired")

        runtime.stop()
        try await waitForStopped(runtime)
    }

    func testClearTimeout() async throws {
        let script = """
        globalThis.fired = false;
        var id = setTimeout(function() { globalThis.fired = true; }, 50);
        clearTimeout(id);
        """
        let (dir, entry) = try makeTempEntry(script: script)
        defer { try? FileManager.default.removeItem(at: dir) }

        let config = TanoConfig(serverEntry: entry.path, dataPath: dir.path)
        let runtime = TanoRuntime(config: config)
        runtime.start()
        try await waitForRunning(runtime)

        // Wait long enough for the timer to have fired (if it wasn't cleared).
        try await Task.sleep(nanoseconds: 300_000_000)

        let expectation = XCTestExpectation(description: "Read fired flag")
        var fired = false

        runtime.performOnJSCThread { [weak runtime] in
            guard let ctx = runtime?.jsContext else {
                XCTFail("JSContext is nil")
                expectation.fulfill()
                return
            }
            fired = ctx.globalObject.forProperty("fired")?.toBool() ?? false
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertFalse(fired, "Cleared timeout should not fire")

        runtime.stop()
        try await waitForStopped(runtime)
    }

    func testSetInterval() async throws {
        let script = """
        globalThis.count = 0;
        setInterval(function() { globalThis.count += 1; }, 80);
        """
        let (dir, entry) = try makeTempEntry(script: script)
        defer { try? FileManager.default.removeItem(at: dir) }

        let config = TanoConfig(serverEntry: entry.path, dataPath: dir.path)
        let runtime = TanoRuntime(config: config)
        runtime.start()
        try await waitForRunning(runtime)

        // Wait ~400ms so the 80ms interval fires several times.
        try await Task.sleep(nanoseconds: 500_000_000)

        let expectation = XCTestExpectation(description: "Read count")
        var count: Int32 = 0

        runtime.performOnJSCThread { [weak runtime] in
            guard let ctx = runtime?.jsContext else {
                XCTFail("JSContext is nil")
                expectation.fulfill()
                return
            }
            count = ctx.globalObject.forProperty("count")?.toInt32() ?? 0
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertGreaterThanOrEqual(count, 2, "setInterval should have fired at least twice, got \(count)")

        runtime.stop()
        try await waitForStopped(runtime)
    }

    func testSetTimeoutReturnsId() async throws {
        let script = """
        globalThis.timerId = setTimeout(function() {}, 10000);
        """
        let (dir, entry) = try makeTempEntry(script: script)
        defer { try? FileManager.default.removeItem(at: dir) }

        let config = TanoConfig(serverEntry: entry.path, dataPath: dir.path)
        let runtime = TanoRuntime(config: config)
        runtime.start()
        try await waitForRunning(runtime)

        let expectation = XCTestExpectation(description: "Read timerId")
        var timerId: Int32 = 0

        runtime.performOnJSCThread { [weak runtime] in
            guard let ctx = runtime?.jsContext else {
                XCTFail("JSContext is nil")
                expectation.fulfill()
                return
            }
            timerId = ctx.globalObject.forProperty("timerId")?.toInt32() ?? 0
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertGreaterThan(timerId, 0, "setTimeout should return a positive ID")

        runtime.stop()
        try await waitForStopped(runtime)
    }
}
