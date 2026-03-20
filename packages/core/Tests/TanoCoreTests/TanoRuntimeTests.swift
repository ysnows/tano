import XCTest
import JavaScriptCore
@testable import TanoCore

final class TanoRuntimeTests: XCTestCase {

    // MARK: - Helpers

    /// Create a temporary directory and JS entry file, returning both paths.
    private func makeTempEntry(script: String) throws -> (dir: URL, entry: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let entry = dir.appendingPathComponent("entry.js")
        try script.write(to: entry, atomically: true, encoding: .utf8)
        return (dir, entry)
    }

    /// Wait until the runtime reaches `.running` (up to ~2 s).
    private func waitForRunning(_ runtime: TanoRuntime) async throws {
        for _ in 0..<20 {
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            if case .running = runtime.state { return }
        }
        XCTFail("Runtime did not reach .running state (current: \(runtime.state))")
    }

    /// Wait until the runtime reaches `.stopped` (up to ~2 s).
    private func waitForStopped(_ runtime: TanoRuntime) async throws {
        for _ in 0..<20 {
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            if case .stopped = runtime.state { return }
        }
        XCTFail("Runtime did not reach .stopped state (current: \(runtime.state))")
    }

    // MARK: - testRuntimeStartsAndStops

    func testRuntimeStartsAndStops() async throws {
        let (dir, entry) = try makeTempEntry(script: "// no-op")
        defer { try? FileManager.default.removeItem(at: dir) }

        let config = TanoConfig(serverEntry: entry.path, dataPath: dir.path)
        let runtime = TanoRuntime(config: config)

        // Initially idle
        if case .idle = runtime.state { /* ok */ }
        else { XCTFail("Expected idle, got \(runtime.state)") }

        runtime.start()
        try await waitForRunning(runtime)

        if case .running = runtime.state { /* ok */ }
        else { XCTFail("Expected running, got \(runtime.state)") }

        runtime.stop()
        try await waitForStopped(runtime)

        if case .stopped = runtime.state { /* ok */ }
        else { XCTFail("Expected stopped, got \(runtime.state)") }
    }

    // MARK: - testRuntimeEvaluatesJS

    func testRuntimeEvaluatesJS() async throws {
        let (dir, entry) = try makeTempEntry(script: "globalThis.testResult = 1 + 2;")
        defer { try? FileManager.default.removeItem(at: dir) }

        let config = TanoConfig(serverEntry: entry.path, dataPath: dir.path)
        let runtime = TanoRuntime(config: config)

        runtime.start()
        try await waitForRunning(runtime)

        // The entry script set globalThis.testResult = 3.
        // Verify by reading the value on the JSC thread.
        let expectation = XCTestExpectation(description: "Read testResult from JS context")
        var jsResult: Int32 = 0

        runtime.performOnJSCThread { [weak runtime] in
            guard let ctx = runtime?.jsContext else {
                XCTFail("JSContext is nil")
                expectation.fulfill()
                return
            }
            let value = ctx.globalObject.forProperty("testResult")
            jsResult = value?.toInt32() ?? -1
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertEqual(jsResult, 3, "Expected globalThis.testResult to be 3")

        runtime.stop()
        try await waitForStopped(runtime)
    }

    // MARK: - testPerformOnJSCThread

    func testPerformOnJSCThread() async throws {
        let (dir, entry) = try makeTempEntry(script: "globalThis.counter = 10;")
        defer { try? FileManager.default.removeItem(at: dir) }

        let config = TanoConfig(serverEntry: entry.path, dataPath: dir.path)
        let runtime = TanoRuntime(config: config)

        runtime.start()
        try await waitForRunning(runtime)

        // Use performOnJSCThread to mutate JS state and read it back.
        let expectation = XCTestExpectation(description: "Mutate and read counter")
        var finalValue: Int32 = 0

        runtime.performOnJSCThread { [weak runtime] in
            guard let ctx = runtime?.jsContext else {
                XCTFail("JSContext is nil")
                expectation.fulfill()
                return
            }
            // Increment counter via JS evaluation
            ctx.evaluateScript("globalThis.counter += 5;")
            finalValue = ctx.globalObject.forProperty("counter")?.toInt32() ?? -1
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertEqual(finalValue, 15, "Expected counter to be 15 after incrementing by 5")

        runtime.stop()
        try await waitForStopped(runtime)
    }
}
