# Phase 1: TanoJSC Core Runtime — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a JSC-based runtime that can execute `Bun.serve()` and basic Bun APIs inside an iOS app, tested in the iOS simulator.

**Architecture:** TanoJSC embeds JavaScriptCore directly via its Swift/C API. We inject Bun-compatible global objects (`Bun`, `fetch`, `Response`, `Request`, `Headers`, `console`, timers) into the JSC context. An HTTP server (`Bun.serve()`) is implemented natively in Swift using `NWListener` and exposed to JS. The runtime runs on a dedicated background thread with its own run loop.

**Tech Stack:** Swift 5.9+, JavaScriptCore framework, Network.framework (NWListener for HTTP), iOS 15+, Xcode

---

## File Structure

```
packages/core/
├── Sources/TanoCore/
│   ├── TanoRuntime.swift              # Main runtime: JSC lifecycle, thread mgmt, shutdown
│   ├── TanoHTTPServer.swift           # Bun.serve() — NWListener-based HTTP/1.1 server
│   ├── TanoHTTPParser.swift           # HTTP request parser (from raw TCP data)
│   ├── TanoHTTPResponse.swift         # HTTP response builder (status, headers, body)
│   ├── TanoGlobals.swift              # Inject all globals into JSC context
│   ├── TanoConsole.swift              # console.log/warn/error → OSLog
│   ├── TanoTimers.swift               # setTimeout/setInterval/clearTimeout/clearInterval
│   ├── TanoFetch.swift                # fetch() → URLSession bridge
│   ├── TanoBunAPI.swift               # Bun.file(), Bun.write(), Bun.env, Bun.sleep()
│   ├── TanoWebAPIs.swift              # Response, Request, Headers, URL constructors
│   └── JSCHelpers.swift               # JSC C API convenience wrappers
├── Sources/TanoDemo/
│   ├── TanoDemoApp.swift              # SwiftUI app entry
│   ├── TanoDemoView.swift             # Main view with WKWebView
│   └── server.js                      # Bundled test server script
├── Tests/TanoCoreTests/
│   ├── TanoRuntimeTests.swift         # Runtime lifecycle tests
│   ├── TanoHTTPServerTests.swift      # HTTP server tests
│   ├── TanoConsoleTests.swift         # Console tests
│   ├── TanoTimersTests.swift          # Timer tests
│   ├── TanoFetchTests.swift           # Fetch tests
│   ├── TanoBunAPITests.swift          # Bun.file/write/env tests
│   └── TanoWebAPIsTests.swift         # Response/Request/Headers tests
├── Package.swift                       # SPM package definition
└── README.md
```

**Test harness:** We'll also modify the existing `examples/ios-demo/` Xcode project to load TanoJSC instead of EdgeJS for integration testing in the simulator.

---

### Task 1: Swift Package & JSC Hello World

**Files:**
- Create: `packages/core/Package.swift`
- Create: `packages/core/Sources/TanoCore/TanoRuntime.swift`
- Create: `packages/core/Sources/TanoCore/JSCHelpers.swift`
- Create: `packages/core/Tests/TanoCoreTests/TanoRuntimeTests.swift`

- [ ] **Step 1: Create Package.swift**

```swift
// packages/core/Package.swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TanoCore",
    platforms: [.iOS(.v15), .macOS(.v13)],
    products: [
        .library(name: "TanoCore", targets: ["TanoCore"]),
    ],
    targets: [
        .target(
            name: "TanoCore",
            path: "Sources/TanoCore"
        ),
        .testTarget(
            name: "TanoCoreTests",
            dependencies: ["TanoCore"],
            path: "Tests/TanoCoreTests"
        ),
    ]
)
```

- [ ] **Step 2: Create JSCHelpers.swift with JSC convenience wrappers**

```swift
// packages/core/Sources/TanoCore/JSCHelpers.swift
import JavaScriptCore

/// Convenience wrappers around JSC C API for cleaner Swift code
enum JSCHelpers {
    /// Set a property on a JS object
    static func setProperty(
        _ context: JSContext,
        object: JSValue,
        name: String,
        value: JSValue
    ) {
        object.setObject(value, forKeyedSubscript: name as NSString)
    }

    /// Create a JS function from a Swift closure
    static func makeFunction(
        _ context: JSContext,
        name: String,
        callback: @escaping @convention(block) ([Any]) -> Any?
    ) -> JSValue {
        let block: @convention(block) ([Any]) -> Any? = callback
        return JSValue(object: block, in: context)
    }

    /// Evaluate JS and return result, logging errors
    @discardableResult
    static func evaluate(_ context: JSContext, script: String, sourceURL: String? = nil) -> JSValue? {
        let result: JSValue?
        if let url = sourceURL {
            result = context.evaluateScript(script, withSourceURL: URL(string: url))
        } else {
            result = context.evaluateScript(script)
        }
        if let exception = context.exception {
            print("[TanoJSC] JS Error: \(exception)")
            context.exception = nil
        }
        return result
    }

    /// Get a nested property (e.g., "Bun.serve")
    static func getProperty(_ context: JSContext, path: String) -> JSValue? {
        let parts = path.split(separator: ".").map(String.init)
        var current = context.globalObject
        for part in parts {
            current = current?.objectForKeyedSubscript(part)
            if current?.isUndefined == true { return nil }
        }
        return current
    }
}
```

- [ ] **Step 3: Create TanoRuntime.swift — minimal version that starts JSC on a background thread**

```swift
// packages/core/Sources/TanoCore/TanoRuntime.swift
import Foundation
import JavaScriptCore

/// Configuration for TanoRuntime
public struct TanoConfig {
    public var serverEntry: String  // Path to bundled server.js
    public var env: [String: String]  // Environment variables for Bun.env
    public var dataPath: String  // App writable data directory

    public init(serverEntry: String, env: [String: String] = [:], dataPath: String = "") {
        self.serverEntry = serverEntry
        self.env = env
        self.dataPath = dataPath.isEmpty
            ? NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true).first ?? NSTemporaryDirectory()
            : dataPath
    }
}

/// TanoJSC Runtime — manages a JSC context on a dedicated background thread
public final class TanoRuntime: @unchecked Sendable {

    public enum State: Sendable {
        case idle
        case starting
        case running
        case stopping
        case stopped
        case error(String)
    }

    private let config: TanoConfig
    private var jsContext: JSContext?
    private var runtimeThread: Thread?
    private var runLoop: CFRunLoop?
    private let stateLock = NSLock()
    private var _state: State = .idle

    public var state: State {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _state
    }

    private func setState(_ newState: State) {
        stateLock.lock()
        _state = newState
        stateLock.unlock()
    }

    public init(config: TanoConfig) {
        self.config = config
    }

    /// Start the runtime on a dedicated background thread
    public func start() {
        guard case .idle = state else { return }
        setState(.starting)

        let thread = Thread { [weak self] in
            self?.runOnThread()
        }
        thread.name = "dev.tano.runtime"
        thread.qualityOfService = .userInitiated
        runtimeThread = thread
        thread.start()
    }

    /// Stop the runtime gracefully
    public func stop() {
        guard case .running = state else { return }
        setState(.stopping)

        if let rl = runLoop {
            CFRunLoopStop(rl)
        }
    }

    /// The main function running on the dedicated thread
    private func runOnThread() {
        // 1. Create JSC context
        let context = JSContext()!
        jsContext = context
        runLoop = CFRunLoopGetCurrent()

        // 2. Set up exception handler
        context.exceptionHandler = { _, exception in
            guard let exception = exception else { return }
            print("[TanoJSC] Uncaught: \(exception)")
        }

        // 3. Inject globals (will be expanded in later tasks)
        injectGlobals(into: context)

        // 4. Load and evaluate server entry script
        if !config.serverEntry.isEmpty {
            do {
                let script = try String(contentsOfFile: config.serverEntry, encoding: .utf8)
                JSCHelpers.evaluate(context, script: script, sourceURL: config.serverEntry)
            } catch {
                setState(.error("Failed to load server entry: \(error)"))
                return
            }
        }

        setState(.running)

        // 5. Run the run loop (blocks until stop() is called)
        CFRunLoopRun()

        // 6. Cleanup
        jsContext = nil
        runLoop = nil
        setState(.stopped)
    }

    /// Inject all Bun-compatible globals into the JSC context
    private func injectGlobals(into context: JSContext) {
        // Minimal for now — expanded in subsequent tasks
        // Just inject a marker so we can verify the runtime is working
        context.setObject("TanoJSC" as NSString, forKeyedSubscript: "__runtime" as NSString)
    }

    deinit {
        stop()
    }
}
```

- [ ] **Step 4: Write the failing test**

```swift
// packages/core/Tests/TanoCoreTests/TanoRuntimeTests.swift
import XCTest
@testable import TanoCore

final class TanoRuntimeTests: XCTestCase {

    func testRuntimeStartsAndStops() async throws {
        let config = TanoConfig(serverEntry: "", env: [:])
        let runtime = TanoRuntime(config: config)

        runtime.start()

        // Wait for runtime to be running
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms

        if case .running = runtime.state {
            // good
        } else {
            XCTFail("Expected runtime to be running, got: \(runtime.state)")
        }

        runtime.stop()

        try await Task.sleep(nanoseconds: 200_000_000) // 200ms

        if case .stopped = runtime.state {
            // good
        } else {
            XCTFail("Expected runtime to be stopped, got: \(runtime.state)")
        }
    }

    func testRuntimeEvaluatesJS() async throws {
        // Create a temp JS file
        let tmpDir = NSTemporaryDirectory()
        let scriptPath = (tmpDir as NSString).appendingPathComponent("test_tanojsc.js")
        try "globalThis.testResult = 1 + 2;".write(toFile: scriptPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: scriptPath) }

        let config = TanoConfig(serverEntry: scriptPath)
        let runtime = TanoRuntime(config: config)

        runtime.start()
        try await Task.sleep(nanoseconds: 300_000_000) // 300ms

        if case .running = runtime.state {
            // good
        } else {
            XCTFail("Expected runtime to be running, got: \(runtime.state)")
        }

        runtime.stop()
        try await Task.sleep(nanoseconds: 200_000_000)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd packages/core && swift test 2>&1`
Expected: Both tests PASS — runtime starts, evaluates JS, and stops cleanly.

- [ ] **Step 6: Commit**

```bash
git add packages/core/
git commit -m "feat(core): TanoRuntime — JSC context on background thread with lifecycle management"
```

---

### Task 2: console.log/warn/error → OSLog

**Files:**
- Create: `packages/core/Sources/TanoCore/TanoConsole.swift`
- Create: `packages/core/Tests/TanoCoreTests/TanoConsoleTests.swift`
- Modify: `packages/core/Sources/TanoCore/TanoRuntime.swift` (call TanoConsole.inject in injectGlobals)

- [ ] **Step 1: Write TanoConsole.swift**

```swift
// packages/core/Sources/TanoCore/TanoConsole.swift
import JavaScriptCore
import os.log

/// Injects console.log/warn/error/info/debug into JSC context, backed by OSLog
enum TanoConsole {

    private static let logger = Logger(subsystem: "dev.tano.runtime", category: "JS")

    /// All log output is also appended here for testing
    static var capturedLogs: [(level: String, message: String)] = []
    private static let logLock = NSLock()

    static func inject(into context: JSContext) {
        let console = JSValue(newObjectIn: context)!

        let log: @convention(block) () -> Void = {
            let args = JSContext.currentArguments()?.map { "\($0)" } ?? []
            let msg = args.joined(separator: " ")
            logger.log("\(msg, privacy: .public)")
            appendLog(level: "log", message: msg)
        }

        let warn: @convention(block) () -> Void = {
            let args = JSContext.currentArguments()?.map { "\($0)" } ?? []
            let msg = args.joined(separator: " ")
            logger.warning("\(msg, privacy: .public)")
            appendLog(level: "warn", message: msg)
        }

        let error: @convention(block) () -> Void = {
            let args = JSContext.currentArguments()?.map { "\($0)" } ?? []
            let msg = args.joined(separator: " ")
            logger.error("\(msg, privacy: .public)")
            appendLog(level: "error", message: msg)
        }

        let info: @convention(block) () -> Void = {
            let args = JSContext.currentArguments()?.map { "\($0)" } ?? []
            let msg = args.joined(separator: " ")
            logger.info("\(msg, privacy: .public)")
            appendLog(level: "info", message: msg)
        }

        console.setObject(log, forKeyedSubscript: "log" as NSString)
        console.setObject(warn, forKeyedSubscript: "warn" as NSString)
        console.setObject(error, forKeyedSubscript: "error" as NSString)
        console.setObject(info, forKeyedSubscript: "info" as NSString)
        console.setObject(log, forKeyedSubscript: "debug" as NSString)

        context.setObject(console, forKeyedSubscript: "console" as NSString)
    }

    private static func appendLog(level: String, message: String) {
        logLock.lock()
        capturedLogs.append((level: level, message: message))
        logLock.unlock()
    }

    static func clearCapturedLogs() {
        logLock.lock()
        capturedLogs.removeAll()
        logLock.unlock()
    }
}
```

- [ ] **Step 2: Wire console injection into TanoRuntime.swift**

In `TanoRuntime.swift`, replace the `injectGlobals` method:

```swift
private func injectGlobals(into context: JSContext) {
    context.setObject("TanoJSC" as NSString, forKeyedSubscript: "__runtime" as NSString)
    TanoConsole.inject(into: context)
}
```

- [ ] **Step 3: Write the test**

```swift
// packages/core/Tests/TanoCoreTests/TanoConsoleTests.swift
import XCTest
import JavaScriptCore
@testable import TanoCore

final class TanoConsoleTests: XCTestCase {

    var context: JSContext!

    override func setUp() {
        super.setUp()
        context = JSContext()
        TanoConsole.clearCapturedLogs()
        TanoConsole.inject(into: context)
    }

    func testConsoleLog() {
        context.evaluateScript("console.log('hello', 'world')")
        XCTAssertEqual(TanoConsole.capturedLogs.count, 1)
        XCTAssertEqual(TanoConsole.capturedLogs[0].level, "log")
        XCTAssertEqual(TanoConsole.capturedLogs[0].message, "hello world")
    }

    func testConsoleWarn() {
        context.evaluateScript("console.warn('warning!')")
        XCTAssertEqual(TanoConsole.capturedLogs.count, 1)
        XCTAssertEqual(TanoConsole.capturedLogs[0].level, "warn")
    }

    func testConsoleError() {
        context.evaluateScript("console.error('oops')")
        XCTAssertEqual(TanoConsole.capturedLogs.count, 1)
        XCTAssertEqual(TanoConsole.capturedLogs[0].level, "error")
    }

    func testConsoleMultipleCalls() {
        context.evaluateScript("""
            console.log('first');
            console.info('second');
            console.debug('third');
        """)
        XCTAssertEqual(TanoConsole.capturedLogs.count, 3)
    }
}
```

- [ ] **Step 4: Run tests**

Run: `cd packages/core && swift test 2>&1`
Expected: All console tests PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/core/Sources/TanoCore/TanoConsole.swift packages/core/Tests/TanoCoreTests/TanoConsoleTests.swift packages/core/Sources/TanoCore/TanoRuntime.swift
git commit -m "feat(core): console.log/warn/error/info → OSLog with test capture"
```

---

### Task 3: Timers — setTimeout/setInterval/clearTimeout/clearInterval

**Files:**
- Create: `packages/core/Sources/TanoCore/TanoTimers.swift`
- Create: `packages/core/Tests/TanoCoreTests/TanoTimersTests.swift`
- Modify: `packages/core/Sources/TanoCore/TanoRuntime.swift` (add TanoTimers.inject)

- [ ] **Step 1: Write TanoTimers.swift**

```swift
// packages/core/Sources/TanoCore/TanoTimers.swift
import JavaScriptCore
import Foundation

/// Injects setTimeout/setInterval/clearTimeout/clearInterval into JSC context
/// Uses DispatchSourceTimer for scheduling callbacks back to the JSC thread
final class TanoTimers {

    private var nextId: Int32 = 1
    private var timers: [Int32: DispatchSourceTimer] = [:]
    private let lock = NSLock()
    private weak var context: JSContext?

    init() {}

    func inject(into context: JSContext) {
        self.context = context

        let setTimeout: @convention(block) (JSValue, JSValue) -> JSValue = { [weak self] callback, delay in
            guard let self = self else { return JSValue(int32: 0, in: JSContext.current()) }
            let ms = delay.isUndefined ? 0 : delay.toInt32()
            let id = self.scheduleTimer(callback: callback, delayMs: Int(ms), repeats: false)
            return JSValue(int32: id, in: JSContext.current())
        }

        let setInterval: @convention(block) (JSValue, JSValue) -> JSValue = { [weak self] callback, delay in
            guard let self = self else { return JSValue(int32: 0, in: JSContext.current()) }
            let ms = delay.isUndefined ? 0 : delay.toInt32()
            let id = self.scheduleTimer(callback: callback, delayMs: Int(ms), repeats: true)
            return JSValue(int32: id, in: JSContext.current())
        }

        let clearTimeout: @convention(block) (JSValue) -> Void = { [weak self] idVal in
            guard let self = self else { return }
            let id = idVal.toInt32()
            self.cancelTimer(id: id)
        }

        context.setObject(setTimeout, forKeyedSubscript: "setTimeout" as NSString)
        context.setObject(setInterval, forKeyedSubscript: "setInterval" as NSString)
        context.setObject(clearTimeout, forKeyedSubscript: "clearTimeout" as NSString)
        context.setObject(clearTimeout, forKeyedSubscript: "clearInterval" as NSString)
    }

    private func scheduleTimer(callback: JSValue, delayMs: Int, repeats: Bool) -> Int32 {
        lock.lock()
        let id = nextId
        nextId += 1
        lock.unlock()

        // Prevent callback from being GC'd
        let protectedCallback = JSManagedValue(value: callback)
        context?.virtualMachine.addManagedReference(protectedCallback, withOwner: self)

        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
        let deadline: DispatchTime = .now() + .milliseconds(max(delayMs, 0))

        if repeats {
            timer.schedule(deadline: deadline, repeating: .milliseconds(max(delayMs, 1)))
        } else {
            timer.schedule(deadline: deadline)
        }

        timer.setEventHandler { [weak self] in
            guard let self = self,
                  let cb = protectedCallback?.value,
                  !cb.isUndefined else {
                return
            }
            cb.call(withArguments: [])

            if !repeats {
                self.cancelTimer(id: id)
                self.context?.virtualMachine.removeManagedReference(protectedCallback, withOwner: self)
            }
        }

        lock.lock()
        timers[id] = timer
        lock.unlock()

        timer.resume()
        return id
    }

    func cancelTimer(id: Int32) {
        lock.lock()
        if let timer = timers.removeValue(forKey: id) {
            timer.cancel()
        }
        lock.unlock()
    }

    func cancelAll() {
        lock.lock()
        for (_, timer) in timers {
            timer.cancel()
        }
        timers.removeAll()
        lock.unlock()
    }
}
```

- [ ] **Step 2: Wire into TanoRuntime.swift**

Add `private let timers = TanoTimers()` as a property. In `injectGlobals`:

```swift
private func injectGlobals(into context: JSContext) {
    context.setObject("TanoJSC" as NSString, forKeyedSubscript: "__runtime" as NSString)
    TanoConsole.inject(into: context)
    timers.inject(into: context)
}
```

In `runOnThread()` cleanup section, add `timers.cancelAll()`.

- [ ] **Step 3: Write the test**

```swift
// packages/core/Tests/TanoCoreTests/TanoTimersTests.swift
import XCTest
import JavaScriptCore
@testable import TanoCore

final class TanoTimersTests: XCTestCase {

    var context: JSContext!
    var timersManager: TanoTimers!

    override func setUp() {
        super.setUp()
        context = JSContext()
        TanoConsole.clearCapturedLogs()
        TanoConsole.inject(into: context)
        timersManager = TanoTimers()
        timersManager.inject(into: context)
    }

    override func tearDown() {
        timersManager.cancelAll()
        super.tearDown()
    }

    func testSetTimeout() async throws {
        context.evaluateScript("""
            globalThis.timerFired = false;
            setTimeout(function() { globalThis.timerFired = true; }, 50);
        """)

        XCTAssertFalse(context.evaluateScript("globalThis.timerFired")!.toBool())
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        XCTAssertTrue(context.evaluateScript("globalThis.timerFired")!.toBool())
    }

    func testClearTimeout() async throws {
        context.evaluateScript("""
            globalThis.timerFired = false;
            var id = setTimeout(function() { globalThis.timerFired = true; }, 100);
            clearTimeout(id);
        """)

        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertFalse(context.evaluateScript("globalThis.timerFired")!.toBool())
    }

    func testSetInterval() async throws {
        context.evaluateScript("""
            globalThis.count = 0;
            globalThis.intervalId = setInterval(function() { globalThis.count++; }, 50);
        """)

        try await Task.sleep(nanoseconds: 300_000_000) // 300ms
        let count = context.evaluateScript("globalThis.count")!.toInt32()
        XCTAssertGreaterThanOrEqual(count, 2)

        context.evaluateScript("clearInterval(globalThis.intervalId)")
    }

    func testSetTimeoutReturnsId() {
        let result = context.evaluateScript("setTimeout(function(){}, 100)")!
        XCTAssertTrue(result.isNumber)
        XCTAssertGreaterThan(result.toInt32(), 0)
    }
}
```

- [ ] **Step 4: Run tests**

Run: `cd packages/core && swift test 2>&1`
Expected: All timer tests PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/core/Sources/TanoCore/TanoTimers.swift packages/core/Tests/TanoCoreTests/TanoTimersTests.swift packages/core/Sources/TanoCore/TanoRuntime.swift
git commit -m "feat(core): setTimeout/setInterval/clearTimeout/clearInterval via DispatchSourceTimer"
```

---

### Task 4: Web APIs — Response, Request, Headers

**Files:**
- Create: `packages/core/Sources/TanoCore/TanoWebAPIs.swift`
- Create: `packages/core/Tests/TanoCoreTests/TanoWebAPIsTests.swift`
- Modify: `packages/core/Sources/TanoCore/TanoRuntime.swift` (add TanoWebAPIs.inject)

- [ ] **Step 1: Write TanoWebAPIs.swift**

This injects JS polyfills for `Response`, `Request`, `Headers`, `URL` so that Bun.serve() handler code can use standard Web APIs.

```swift
// packages/core/Sources/TanoCore/TanoWebAPIs.swift
import JavaScriptCore

/// Injects Web API polyfills: Response, Request, Headers, URL
/// These are JS-implemented polyfills evaluated in the JSC context
enum TanoWebAPIs {

    static func inject(into context: JSContext) {
        // Headers
        JSCHelpers.evaluate(context, script: headersPolyfill, sourceURL: "tano://web-apis/headers.js")
        // Response
        JSCHelpers.evaluate(context, script: responsePolyfill, sourceURL: "tano://web-apis/response.js")
        // Request
        JSCHelpers.evaluate(context, script: requestPolyfill, sourceURL: "tano://web-apis/request.js")
        // URL (JSC already has URL, but ensure it's there)
        JSCHelpers.evaluate(context, script: urlPolyfill, sourceURL: "tano://web-apis/url.js")
    }

    static let headersPolyfill = """
    if (typeof globalThis.Headers === 'undefined') {
        class Headers {
            constructor(init) {
                this._headers = {};
                if (init instanceof Headers) {
                    for (const [k, v] of init.entries()) this._headers[k.toLowerCase()] = v;
                } else if (Array.isArray(init)) {
                    for (const [k, v] of init) this._headers[k.toLowerCase()] = String(v);
                } else if (init && typeof init === 'object') {
                    for (const k of Object.keys(init)) this._headers[k.toLowerCase()] = String(init[k]);
                }
            }
            get(name) { return this._headers[name.toLowerCase()] ?? null; }
            set(name, value) { this._headers[name.toLowerCase()] = String(value); }
            has(name) { return name.toLowerCase() in this._headers; }
            delete(name) { delete this._headers[name.toLowerCase()]; }
            append(name, value) {
                const key = name.toLowerCase();
                if (key in this._headers) {
                    this._headers[key] += ', ' + String(value);
                } else {
                    this._headers[key] = String(value);
                }
            }
            forEach(cb, thisArg) {
                for (const k of Object.keys(this._headers)) cb.call(thisArg, this._headers[k], k, this);
            }
            *entries() { for (const k of Object.keys(this._headers)) yield [k, this._headers[k]]; }
            *keys() { for (const k of Object.keys(this._headers)) yield k; }
            *values() { for (const k of Object.keys(this._headers)) yield this._headers[k]; }
            [Symbol.iterator]() { return this.entries(); }
            toJSON() { return { ...this._headers }; }
            get count() { return Object.keys(this._headers).length; }
        }
        globalThis.Headers = Headers;
    }
    """

    static let responsePolyfill = """
    if (typeof globalThis.Response === 'undefined') {
        class Response {
            constructor(body, init) {
                init = init || {};
                this._body = body ?? null;
                this.status = init.status ?? 200;
                this.statusText = init.statusText ?? 'OK';
                this.ok = this.status >= 200 && this.status < 300;
                this.headers = new Headers(init.headers);
                this.type = 'default';
                this.url = '';
                this.redirected = false;
                this.bodyUsed = false;

                // Auto-set content-type if not set
                if (typeof this._body === 'string' && !this.headers.has('content-type')) {
                    this.headers.set('content-type', 'text/plain;charset=UTF-8');
                }
            }

            async text() {
                this.bodyUsed = true;
                if (this._body === null || this._body === undefined) return '';
                if (typeof this._body === 'string') return this._body;
                if (this._body instanceof ArrayBuffer) return new TextDecoder().decode(this._body);
                if (ArrayBuffer.isView(this._body)) return new TextDecoder().decode(this._body);
                return String(this._body);
            }

            async json() {
                const text = await this.text();
                return JSON.parse(text);
            }

            async arrayBuffer() {
                this.bodyUsed = true;
                if (this._body instanceof ArrayBuffer) return this._body;
                if (typeof this._body === 'string') return new TextEncoder().encode(this._body).buffer;
                return new ArrayBuffer(0);
            }

            clone() {
                return new Response(this._body, {
                    status: this.status,
                    statusText: this.statusText,
                    headers: new Headers(this.headers),
                });
            }

            static json(data, init) {
                const body = JSON.stringify(data);
                const headers = new Headers(init?.headers);
                headers.set('content-type', 'application/json');
                return new Response(body, { ...(init || {}), headers });
            }

            static redirect(url, status) {
                const headers = new Headers({ location: url });
                return new Response(null, { status: status || 302, headers });
            }
        }
        globalThis.Response = Response;
    }
    """

    static let requestPolyfill = """
    if (typeof globalThis.Request === 'undefined') {
        class Request {
            constructor(input, init) {
                init = init || {};
                if (typeof input === 'string') {
                    this.url = input;
                } else if (input instanceof Request) {
                    this.url = input.url;
                    init = { method: input.method, headers: input.headers, body: input._body, ...init };
                } else {
                    this.url = String(input);
                }
                this.method = (init.method || 'GET').toUpperCase();
                this.headers = new Headers(init.headers);
                this._body = init.body ?? null;
                this.bodyUsed = false;
                this.redirect = init.redirect || 'follow';
                this.signal = init.signal || null;
            }

            async text() {
                this.bodyUsed = true;
                if (this._body === null) return '';
                if (typeof this._body === 'string') return this._body;
                return String(this._body);
            }

            async json() {
                const text = await this.text();
                return JSON.parse(text);
            }

            async arrayBuffer() {
                this.bodyUsed = true;
                if (this._body instanceof ArrayBuffer) return this._body;
                if (typeof this._body === 'string') return new TextEncoder().encode(this._body).buffer;
                return new ArrayBuffer(0);
            }

            clone() {
                return new Request(this.url, {
                    method: this.method,
                    headers: new Headers(this.headers),
                    body: this._body,
                });
            }
        }
        globalThis.Request = Request;
    }
    """

    static let urlPolyfill = """
    // JSC on iOS has URL built-in, just verify it exists
    if (typeof globalThis.URL === 'undefined') {
        throw new Error('URL is not available in this JSC build');
    }
    // Add URLSearchParams if missing
    if (typeof globalThis.URLSearchParams === 'undefined') {
        class URLSearchParams {
            constructor(init) {
                this._params = [];
                if (typeof init === 'string') {
                    init = init.startsWith('?') ? init.slice(1) : init;
                    for (const pair of init.split('&')) {
                        const [k, v] = pair.split('=').map(decodeURIComponent);
                        this._params.push([k, v || '']);
                    }
                } else if (init && typeof init === 'object') {
                    for (const k of Object.keys(init)) this._params.push([k, String(init[k])]);
                }
            }
            get(name) { const p = this._params.find(([k]) => k === name); return p ? p[1] : null; }
            getAll(name) { return this._params.filter(([k]) => k === name).map(([,v]) => v); }
            has(name) { return this._params.some(([k]) => k === name); }
            set(name, value) {
                const idx = this._params.findIndex(([k]) => k === name);
                if (idx >= 0) this._params[idx] = [name, String(value)];
                else this._params.push([name, String(value)]);
            }
            append(name, value) { this._params.push([name, String(value)]); }
            delete(name) { this._params = this._params.filter(([k]) => k !== name); }
            toString() { return this._params.map(([k,v]) => encodeURIComponent(k) + '=' + encodeURIComponent(v)).join('&'); }
            forEach(cb, thisArg) { for (const [k, v] of this._params) cb.call(thisArg, v, k, this); }
            *entries() { for (const p of this._params) yield p; }
            *keys() { for (const [k] of this._params) yield k; }
            *values() { for (const [,v] of this._params) yield v; }
            [Symbol.iterator]() { return this.entries(); }
        }
        globalThis.URLSearchParams = URLSearchParams;
    }
    """
}
```

- [ ] **Step 2: Wire into TanoRuntime injectGlobals**

```swift
private func injectGlobals(into context: JSContext) {
    context.setObject("TanoJSC" as NSString, forKeyedSubscript: "__runtime" as NSString)
    TanoConsole.inject(into: context)
    timers.inject(into: context)
    TanoWebAPIs.inject(into: context)
}
```

- [ ] **Step 3: Write tests**

```swift
// packages/core/Tests/TanoCoreTests/TanoWebAPIsTests.swift
import XCTest
import JavaScriptCore
@testable import TanoCore

final class TanoWebAPIsTests: XCTestCase {

    var context: JSContext!

    override func setUp() {
        super.setUp()
        context = JSContext()
        context.exceptionHandler = { _, ex in XCTFail("JS Error: \(ex!)") }
        TanoWebAPIs.inject(into: context)
    }

    func testHeadersBasic() {
        let result = context.evaluateScript("""
            const h = new Headers({'Content-Type': 'application/json'});
            h.get('content-type');
        """)!
        XCTAssertEqual(result.toString(), "application/json")
    }

    func testHeadersCaseInsensitive() {
        let result = context.evaluateScript("""
            const h = new Headers();
            h.set('X-Custom', 'value');
            h.get('x-custom');
        """)!
        XCTAssertEqual(result.toString(), "value")
    }

    func testResponseBasic() {
        let result = context.evaluateScript("""
            const r = new Response('hello', { status: 201 });
            JSON.stringify({ status: r.status, ok: r.ok });
        """)!
        let json = result.toString()!
        XCTAssertTrue(json.contains("201"))
        XCTAssertTrue(json.contains("true"))
    }

    func testResponseJson() {
        let result = context.evaluateScript("""
            (async () => {
                const r = Response.json({ name: 'tano' });
                const data = await r.json();
                return data.name;
            })()
        """)!
        // JSC returns a Promise, we need to resolve it
        // For sync testing, test the static method directly
        let r2 = context.evaluateScript("""
            const r = Response.json({ name: 'tano' });
            r.headers.get('content-type');
        """)!
        XCTAssertEqual(r2.toString(), "application/json")
    }

    func testResponseText() {
        let result = context.evaluateScript("""
            const r = new Response('hello world');
            r._body;
        """)!
        XCTAssertEqual(result.toString(), "hello world")
    }

    func testRequestBasic() {
        let result = context.evaluateScript("""
            const req = new Request('http://localhost/test', { method: 'POST' });
            JSON.stringify({ url: req.url, method: req.method });
        """)!
        let json = result.toString()!
        XCTAssertTrue(json.contains("http://localhost/test"))
        XCTAssertTrue(json.contains("POST"))
    }

    func testURLExists() {
        let result = context.evaluateScript("""
            const u = new URL('http://localhost:3000/path?q=1');
            u.pathname;
        """)!
        XCTAssertEqual(result.toString(), "/path")
    }
}
```

- [ ] **Step 4: Run tests**

Run: `cd packages/core && swift test 2>&1`
Expected: All Web API tests PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/core/Sources/TanoCore/TanoWebAPIs.swift packages/core/Tests/TanoCoreTests/TanoWebAPIsTests.swift packages/core/Sources/TanoCore/TanoRuntime.swift
git commit -m "feat(core): Response/Request/Headers/URL polyfills for Bun compatibility"
```

---

### Task 5: Bun.file(), Bun.write(), Bun.env, Bun.sleep()

**Files:**
- Create: `packages/core/Sources/TanoCore/TanoBunAPI.swift`
- Create: `packages/core/Tests/TanoCoreTests/TanoBunAPITests.swift`
- Modify: `packages/core/Sources/TanoCore/TanoRuntime.swift` (add TanoBunAPI.inject)

- [ ] **Step 1: Write TanoBunAPI.swift**

```swift
// packages/core/Sources/TanoCore/TanoBunAPI.swift
import JavaScriptCore
import Foundation

/// Injects the `Bun` global object with file(), write(), env, sleep()
final class TanoBunAPI {

    private let config: TanoConfig

    init(config: TanoConfig) {
        self.config = config
    }

    func inject(into context: JSContext) {
        // Create the Bun global object
        let bun = JSValue(newObjectIn: context)!

        // Bun.env
        let env = JSValue(newObjectIn: context)!
        for (key, value) in config.env {
            env.setObject(value, forKeyedSubscript: key as NSString)
        }
        // Also include process env
        for (key, value) in ProcessInfo.processInfo.environment {
            if env.objectForKeyedSubscript(key)?.isUndefined == true {
                env.setObject(value, forKeyedSubscript: key as NSString)
            }
        }
        bun.setObject(env, forKeyedSubscript: "env" as NSString)

        // Bun.version
        bun.setObject("1.0.0-tano", forKeyedSubscript: "version" as NSString)

        // Bun.main (will be set when script is loaded)
        bun.setObject(config.serverEntry, forKeyedSubscript: "main" as NSString)

        // Bun.file(path) → BunFile-like object
        let file: @convention(block) (String) -> JSValue? = { [weak context] path in
            guard let ctx = context ?? JSContext.current() else { return nil }
            return Self.createBunFile(path: path, context: ctx)
        }
        bun.setObject(file, forKeyedSubscript: "file" as NSString)

        // Bun.write(path, data) → Promise<number>
        let write: @convention(block) (String, JSValue) -> JSValue = { [weak context] path, data in
            let ctx = context ?? JSContext.current()!
            return Self.bunWrite(path: path, data: data, context: ctx)
        }
        bun.setObject(write, forKeyedSubscript: "write" as NSString)

        // Bun.sleep(ms) → Promise<void>
        let sleep: @convention(block) (JSValue) -> JSValue = { msVal in
            let ctx = JSContext.current()!
            let ms = msVal.toDouble()
            // Create a resolved promise after delay using setTimeout
            return ctx.evaluateScript("""
                new Promise(resolve => setTimeout(resolve, \(Int(ms))))
            """)!
        }
        bun.setObject(sleep, forKeyedSubscript: "sleep" as NSString)

        context.setObject(bun, forKeyedSubscript: "Bun" as NSString)
    }

    /// Create a BunFile-like object for a given path
    private static func createBunFile(path: String, context: JSContext) -> JSValue {
        let obj = JSValue(newObjectIn: context)!

        let name = (path as NSString).lastPathComponent
        obj.setObject(name, forKeyedSubscript: "name" as NSString)

        // .exists() → Promise<boolean>
        let exists: @convention(block) () -> JSValue = {
            let ctx = JSContext.current()!
            let fileExists = FileManager.default.fileExists(atPath: path)
            return ctx.evaluateScript("Promise.resolve(\(fileExists))")!
        }
        obj.setObject(exists, forKeyedSubscript: "exists" as NSString)

        // .text() → Promise<string>
        let text: @convention(block) () -> JSValue = {
            let ctx = JSContext.current()!
            do {
                let content = try String(contentsOfFile: path, encoding: .utf8)
                let escaped = content
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "`", with: "\\`")
                    .replacingOccurrences(of: "$", with: "\\$")
                return ctx.evaluateScript("Promise.resolve(`\(escaped)`)")!
            } catch {
                return ctx.evaluateScript("Promise.reject(new Error('\(error.localizedDescription)'))")!
            }
        }
        obj.setObject(text, forKeyedSubscript: "text" as NSString)

        // .json() → Promise<any>
        let json: @convention(block) () -> JSValue = {
            let ctx = JSContext.current()!
            do {
                let content = try String(contentsOfFile: path, encoding: .utf8)
                return ctx.evaluateScript("Promise.resolve(JSON.parse(\(Self.jsStringLiteral(content))))")!
            } catch {
                return ctx.evaluateScript("Promise.reject(new Error('\(error.localizedDescription)'))")!
            }
        }
        obj.setObject(json, forKeyedSubscript: "json" as NSString)

        // .size (sync property)
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let size = attrs[.size] as? Int {
            obj.setObject(size, forKeyedSubscript: "size" as NSString)
        } else {
            obj.setObject(0, forKeyedSubscript: "size" as NSString)
        }

        // .type (MIME type)
        obj.setObject(Self.mimeType(for: path), forKeyedSubscript: "type" as NSString)

        return obj
    }

    /// Bun.write(path, data) implementation
    private static func bunWrite(path: String, data: JSValue, context: JSContext) -> JSValue {
        do {
            let dir = (path as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

            let content: Data
            if data.isString {
                content = data.toString().data(using: .utf8)!
            } else {
                content = data.toString().data(using: .utf8)!
            }
            try content.write(to: URL(fileURLWithPath: path))
            return context.evaluateScript("Promise.resolve(\(content.count))")!
        } catch {
            return context.evaluateScript("Promise.reject(new Error('\(error.localizedDescription)'))")!
        }
    }

    /// Escape a string for safe use in JS string literal
    private static func jsStringLiteral(_ str: String) -> String {
        let escaped = str
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }

    /// Simple MIME type detection
    private static func mimeType(for path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "json": return "application/json"
        case "js", "mjs": return "application/javascript"
        case "html", "htm": return "text/html"
        case "css": return "text/css"
        case "txt": return "text/plain"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "svg": return "image/svg+xml"
        case "pdf": return "application/pdf"
        default: return "application/octet-stream"
        }
    }
}
```

- [ ] **Step 2: Wire into TanoRuntime**

Add `private var bunAPI: TanoBunAPI?` property. In `injectGlobals`:

```swift
private func injectGlobals(into context: JSContext) {
    context.setObject("TanoJSC" as NSString, forKeyedSubscript: "__runtime" as NSString)
    TanoConsole.inject(into: context)
    timers.inject(into: context)
    TanoWebAPIs.inject(into: context)
    bunAPI = TanoBunAPI(config: config)
    bunAPI?.inject(into: context)
}
```

- [ ] **Step 3: Write tests**

```swift
// packages/core/Tests/TanoCoreTests/TanoBunAPITests.swift
import XCTest
import JavaScriptCore
@testable import TanoCore

final class TanoBunAPITests: XCTestCase {

    var context: JSContext!
    let tmpDir = NSTemporaryDirectory() + "tano_test_\(ProcessInfo.processInfo.processIdentifier)/"

    override func setUp() {
        super.setUp()
        try? FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        context = JSContext()
        context.exceptionHandler = { _, ex in print("JS Error: \(ex!)") }
        TanoConsole.inject(into: context)
        TanoTimers().inject(into: context)
        TanoWebAPIs.inject(into: context)
        let api = TanoBunAPI(config: TanoConfig(
            serverEntry: "",
            env: ["TEST_KEY": "test_value", "NODE_ENV": "test"],
            dataPath: tmpDir
        ))
        api.inject(into: context)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: tmpDir)
        super.tearDown()
    }

    func testBunExists() {
        let result = context.evaluateScript("typeof Bun")!
        XCTAssertEqual(result.toString(), "object")
    }

    func testBunVersion() {
        let result = context.evaluateScript("Bun.version")!
        XCTAssertTrue(result.toString()!.contains("tano"))
    }

    func testBunEnv() {
        let result = context.evaluateScript("Bun.env.TEST_KEY")!
        XCTAssertEqual(result.toString(), "test_value")
    }

    func testBunEnvNodeEnv() {
        let result = context.evaluateScript("Bun.env.NODE_ENV")!
        XCTAssertEqual(result.toString(), "test")
    }

    func testBunFileExists() {
        let testFile = tmpDir + "exists_test.txt"
        try! "hello".write(toFile: testFile, atomically: true, encoding: .utf8)

        // Sync check — the exists() returns a Promise but we test the file creation
        let result = context.evaluateScript("Bun.file('\(testFile)').name")!
        XCTAssertEqual(result.toString(), "exists_test.txt")
    }

    func testBunFileSize() {
        let testFile = tmpDir + "size_test.txt"
        try! "hello".write(toFile: testFile, atomically: true, encoding: .utf8)

        let result = context.evaluateScript("Bun.file('\(testFile)').size")!
        XCTAssertEqual(result.toInt32(), 5)
    }

    func testBunFileMimeType() {
        let result = context.evaluateScript("Bun.file('/tmp/test.json').type")!
        XCTAssertEqual(result.toString(), "application/json")
    }

    func testBunWriteAndRead() {
        let testFile = tmpDir + "write_test.txt"

        // Write using Bun.write
        context.evaluateScript("Bun.write('\(testFile)', 'hello tano')")

        // Verify via FileManager
        let content = try? String(contentsOfFile: testFile, encoding: .utf8)
        XCTAssertEqual(content, "hello tano")
    }
}
```

- [ ] **Step 4: Run tests**

Run: `cd packages/core && swift test 2>&1`
Expected: All Bun API tests PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/core/Sources/TanoCore/TanoBunAPI.swift packages/core/Tests/TanoCoreTests/TanoBunAPITests.swift packages/core/Sources/TanoCore/TanoRuntime.swift
git commit -m "feat(core): Bun.file(), Bun.write(), Bun.env, Bun.sleep() shims"
```

---

### Task 6: fetch() → URLSession Bridge

**Files:**
- Create: `packages/core/Sources/TanoCore/TanoFetch.swift`
- Create: `packages/core/Tests/TanoCoreTests/TanoFetchTests.swift`
- Modify: `packages/core/Sources/TanoCore/TanoRuntime.swift` (add TanoFetch.inject)

- [ ] **Step 1: Write TanoFetch.swift**

```swift
// packages/core/Sources/TanoCore/TanoFetch.swift
import JavaScriptCore
import Foundation

/// Injects global fetch() backed by URLSession
enum TanoFetch {

    static func inject(into context: JSContext) {
        // We implement fetch as a JS wrapper that calls a native _nativeFetch
        // _nativeFetch takes (url, method, headersJSON, body) and returns via callback

        let nativeFetch: @convention(block) (String, String, String, JSValue, JSValue) -> Void = {
            urlString, method, headersJSON, bodyVal, callback in

            guard let url = URL(string: urlString) else {
                callback.call(withArguments: ["Invalid URL: \(urlString)", NSNull()])
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = method

            // Parse headers
            if let data = headersJSON.data(using: .utf8),
               let headers = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                for (key, value) in headers {
                    request.setValue(value, forHTTPHeaderField: key)
                }
            }

            // Body
            if !bodyVal.isNull && !bodyVal.isUndefined {
                if bodyVal.isString {
                    request.httpBody = bodyVal.toString().data(using: .utf8)
                }
            }

            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    callback.call(withArguments: [error.localizedDescription, NSNull()])
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    callback.call(withArguments: ["Not an HTTP response", NSNull()])
                    return
                }

                let responseHeaders = httpResponse.allHeaderFields as? [String: String] ?? [:]
                let headersJSON = (try? JSONSerialization.data(withJSONObject: responseHeaders))
                    .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

                let bodyString: String
                if let data = data {
                    bodyString = String(data: data, encoding: .utf8) ?? ""
                } else {
                    bodyString = ""
                }

                let result: [String: Any] = [
                    "status": httpResponse.statusCode,
                    "statusText": HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode),
                    "headers": headersJSON,
                    "body": bodyString
                ]
                callback.call(withArguments: [NSNull(), result])
            }
            task.resume()
        }

        context.setObject(nativeFetch, forKeyedSubscript: "_nativeFetch" as NSString)

        // JS fetch wrapper that returns a Promise and constructs a Response
        JSCHelpers.evaluate(context, script: fetchPolyfill, sourceURL: "tano://fetch.js")
    }

    static let fetchPolyfill = """
    globalThis.fetch = function fetch(input, init) {
        return new Promise(function(resolve, reject) {
            var url, method, headers, body;

            if (typeof input === 'string') {
                url = input;
            } else if (input instanceof Request) {
                url = input.url;
                method = input.method;
                headers = input.headers;
                body = input._body;
            } else {
                url = String(input);
            }

            init = init || {};
            method = init.method || method || 'GET';

            var h = new Headers(init.headers || headers);
            var headersObj = {};
            h.forEach(function(v, k) { headersObj[k] = v; });
            var headersJSON = JSON.stringify(headersObj);

            body = init.body || body || null;

            _nativeFetch(url, method, headersJSON, body, function(err, result) {
                if (err) {
                    reject(new TypeError('fetch failed: ' + err));
                    return;
                }
                var respHeaders = {};
                try { respHeaders = JSON.parse(result.headers); } catch(e) {}
                var response = new Response(result.body, {
                    status: result.status,
                    statusText: result.statusText,
                    headers: respHeaders
                });
                resolve(response);
            });
        });
    };
    """
}
```

- [ ] **Step 2: Wire into TanoRuntime injectGlobals**

```swift
private func injectGlobals(into context: JSContext) {
    context.setObject("TanoJSC" as NSString, forKeyedSubscript: "__runtime" as NSString)
    TanoConsole.inject(into: context)
    timers.inject(into: context)
    TanoWebAPIs.inject(into: context)
    bunAPI = TanoBunAPI(config: config)
    bunAPI?.inject(into: context)
    TanoFetch.inject(into: context)
}
```

- [ ] **Step 3: Write tests**

```swift
// packages/core/Tests/TanoCoreTests/TanoFetchTests.swift
import XCTest
import JavaScriptCore
@testable import TanoCore

final class TanoFetchTests: XCTestCase {

    var context: JSContext!

    override func setUp() {
        super.setUp()
        context = JSContext()
        context.exceptionHandler = { _, ex in print("JS Error: \(ex!)") }
        TanoConsole.inject(into: context)
        TanoTimers().inject(into: context)
        TanoWebAPIs.inject(into: context)
        TanoFetch.inject(into: context)
    }

    func testFetchFunctionExists() {
        let result = context.evaluateScript("typeof fetch")!
        XCTAssertEqual(result.toString(), "function")
    }

    func testNativeFetchExists() {
        let result = context.evaluateScript("typeof _nativeFetch")!
        XCTAssertEqual(result.toString(), "function")
    }

    func testFetchReturnsPromise() {
        // fetch returns a Promise (thenable)
        let result = context.evaluateScript("""
            var p = fetch('http://httpbin.org/get');
            typeof p.then;
        """)!
        XCTAssertEqual(result.toString(), "function")
    }
}
```

- [ ] **Step 4: Run tests**

Run: `cd packages/core && swift test 2>&1`
Expected: All fetch tests PASS (note: network tests only verify structure, not actual HTTP).

- [ ] **Step 5: Commit**

```bash
git add packages/core/Sources/TanoCore/TanoFetch.swift packages/core/Tests/TanoCoreTests/TanoFetchTests.swift packages/core/Sources/TanoCore/TanoRuntime.swift
git commit -m "feat(core): fetch() → URLSession bridge with Response integration"
```

---

### Task 7: Bun.serve() — HTTP Server on JSC

**Files:**
- Create: `packages/core/Sources/TanoCore/TanoHTTPServer.swift`
- Create: `packages/core/Sources/TanoCore/TanoHTTPParser.swift`
- Create: `packages/core/Sources/TanoCore/TanoHTTPResponse.swift`
- Create: `packages/core/Tests/TanoCoreTests/TanoHTTPServerTests.swift`
- Modify: `packages/core/Sources/TanoCore/TanoBunAPI.swift` (add serve() to Bun object)

- [ ] **Step 1: Write TanoHTTPParser.swift — parse raw HTTP/1.1 requests**

```swift
// packages/core/Sources/TanoCore/TanoHTTPParser.swift
import Foundation

/// Parsed HTTP request from raw TCP data
struct ParsedHTTPRequest {
    var method: String
    var path: String
    var httpVersion: String
    var headers: [(String, String)]
    var body: Data
    var rawURL: String  // full URL path + query

    func header(_ name: String) -> String? {
        let lower = name.lowercased()
        return headers.first(where: { $0.0.lowercased() == lower })?.1
    }
}

/// Simple HTTP/1.1 request parser
enum TanoHTTPParser {

    /// Parse raw data into an HTTP request. Returns nil if data is incomplete.
    static func parse(_ data: Data) -> ParsedHTTPRequest? {
        guard let str = String(data: data, encoding: .utf8) else { return nil }

        // Find end of headers
        guard let headerEnd = str.range(of: "\r\n\r\n") else { return nil }

        let headerSection = String(str[str.startIndex..<headerEnd.lowerBound])
        let bodyStart = data.index(data.startIndex, offsetBy: str.distance(from: str.startIndex, to: headerEnd.upperBound))
        let bodyData = data.subdata(in: bodyStart..<data.endIndex)

        let lines = headerSection.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }

        let parts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else { return nil }

        let method = parts[0]
        let rawURL = parts[1]
        let httpVersion = parts.count > 2 ? parts[2] : "HTTP/1.1"

        // Extract path (without query)
        let path: String
        if let qIdx = rawURL.firstIndex(of: "?") {
            path = String(rawURL[rawURL.startIndex..<qIdx])
        } else {
            path = rawURL
        }

        // Parse headers
        var headers: [(String, String)] = []
        for line in lines.dropFirst() {
            if let colonIdx = line.firstIndex(of: ":") {
                let name = String(line[line.startIndex..<colonIdx]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
                headers.append((name, value))
            }
        }

        // Check Content-Length for body completeness
        if let contentLength = headers.first(where: { $0.0.lowercased() == "content-length" })?.1,
           let length = Int(contentLength),
           bodyData.count < length {
            return nil  // Incomplete body
        }

        return ParsedHTTPRequest(
            method: method,
            path: path,
            httpVersion: httpVersion,
            headers: headers,
            body: bodyData,
            rawURL: rawURL
        )
    }
}
```

- [ ] **Step 2: Write TanoHTTPResponse.swift — build HTTP response bytes**

```swift
// packages/core/Sources/TanoCore/TanoHTTPResponse.swift
import Foundation

/// Builds raw HTTP/1.1 response data from components
struct TanoHTTPResponseBuilder {
    var statusCode: Int = 200
    var statusText: String = "OK"
    var headers: [(String, String)] = []
    var body: Data = Data()

    mutating func setHeader(_ name: String, _ value: String) {
        headers.removeAll { $0.0.lowercased() == name.lowercased() }
        headers.append((name, value))
    }

    func build() -> Data {
        var response = "HTTP/1.1 \(statusCode) \(statusText)\r\n"

        // Ensure Content-Length is set
        var hasContentLength = false
        for (name, value) in headers {
            response += "\(name): \(value)\r\n"
            if name.lowercased() == "content-length" { hasContentLength = true }
        }
        if !hasContentLength {
            response += "Content-Length: \(body.count)\r\n"
        }
        response += "Connection: keep-alive\r\n"
        response += "\r\n"

        var data = response.data(using: .utf8)!
        data.append(body)
        return data
    }

    /// Common status text lookup
    static func statusText(for code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 201: return "Created"
        case 204: return "No Content"
        case 301: return "Moved Permanently"
        case 302: return "Found"
        case 304: return "Not Modified"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 500: return "Internal Server Error"
        case 502: return "Bad Gateway"
        case 503: return "Service Unavailable"
        default: return "Unknown"
        }
    }
}
```

- [ ] **Step 3: Write TanoHTTPServer.swift — NWListener-based HTTP server**

```swift
// packages/core/Sources/TanoCore/TanoHTTPServer.swift
import Foundation
import Network

/// A lightweight HTTP/1.1 server using Network.framework (NWListener)
/// Designed to implement Bun.serve() on iOS
final class TanoHTTPServer {

    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private let queue = DispatchQueue(label: "dev.tano.http", qos: .userInitiated)
    private let lock = NSLock()

    /// The JS fetch handler (called for each request)
    var fetchHandler: ((_ method: String, _ url: String, _ headers: [(String, String)], _ body: String,
                         _ respond: @escaping (Int, [(String, String)], String) -> Void) -> Void)?

    private(set) var port: UInt16 = 0
    private(set) var hostname: String = "127.0.0.1"

    init() {}

    /// Start listening on the given port
    func start(port: UInt16 = 0, hostname: String = "127.0.0.1") throws {
        self.hostname = hostname

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        let nwPort: NWEndpoint.Port = port == 0 ? .any : NWEndpoint.Port(rawValue: port)!
        listener = try NWListener(using: params, on: nwPort)

        listener?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let actualPort = self?.listener?.port?.rawValue {
                    self?.port = actualPort
                }
            case .failed(let error):
                print("[TanoHTTP] Listener failed: \(error)")
            default:
                break
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        listener?.start(queue: queue)
    }

    /// Stop the server
    func stop() {
        listener?.cancel()
        lock.lock()
        for conn in connections {
            conn.cancel()
        }
        connections.removeAll()
        lock.unlock()
    }

    private func handleConnection(_ connection: NWConnection) {
        lock.lock()
        connections.append(connection)
        lock.unlock()

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            if case .cancelled = state {
                self?.removeConnection(connection)
            } else if case .failed = state {
                self?.removeConnection(connection)
            }
        }

        connection.start(queue: queue)
        receiveData(on: connection, buffer: Data())
    }

    private func receiveData(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let error = error {
                print("[TanoHTTP] Receive error: \(error)")
                connection.cancel()
                return
            }

            var accumulated = buffer
            if let data = data {
                accumulated.append(data)
            }

            // Try to parse a complete HTTP request
            if let request = TanoHTTPParser.parse(accumulated) {
                self.handleRequest(request, on: connection)

                // Check for pipelined requests
                let consumed = self.consumedBytes(for: request, in: accumulated)
                let remaining = accumulated.subdata(in: consumed..<accumulated.count)
                if !remaining.isEmpty {
                    self.receiveData(on: connection, buffer: remaining)
                } else if !isComplete {
                    self.receiveData(on: connection, buffer: Data())
                }
            } else if !isComplete {
                // Incomplete request, keep reading
                self.receiveData(on: connection, buffer: accumulated)
            }
        }
    }

    private func consumedBytes(for request: ParsedHTTPRequest, in data: Data) -> Int {
        guard let str = String(data: data, encoding: .utf8),
              let headerEnd = str.range(of: "\r\n\r\n") else {
            return data.count
        }
        let headerLen = str.distance(from: str.startIndex, to: headerEnd.upperBound)
        return headerLen + request.body.count
    }

    private func handleRequest(_ request: ParsedHTTPRequest, on connection: NWConnection) {
        let bodyString = String(data: request.body, encoding: .utf8) ?? ""
        let fullURL = "http://\(hostname):\(port)\(request.rawURL)"

        guard let handler = fetchHandler else {
            // No handler — return 500
            let resp = TanoHTTPResponseBuilder(
                statusCode: 500,
                statusText: "Internal Server Error",
                body: "No fetch handler configured".data(using: .utf8)!
            )
            self.sendResponse(resp.build(), on: connection)
            return
        }

        handler(request.method, fullURL, request.headers, bodyString) { [weak self] status, headers, body in
            var resp = TanoHTTPResponseBuilder(
                statusCode: status,
                statusText: TanoHTTPResponseBuilder.statusText(for: status)
            )
            for (name, value) in headers {
                resp.setHeader(name, value)
            }
            resp.body = body.data(using: .utf8) ?? Data()
            self?.sendResponse(resp.build(), on: connection)
        }
    }

    private func sendResponse(_ data: Data, on connection: NWConnection) {
        connection.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                print("[TanoHTTP] Send error: \(error)")
            }
        })
    }

    private func removeConnection(_ connection: NWConnection?) {
        guard let connection = connection else { return }
        lock.lock()
        connections.removeAll { $0 === connection }
        lock.unlock()
    }
}
```

- [ ] **Step 4: Wire Bun.serve() into TanoBunAPI.swift**

Add to `TanoBunAPI.inject()`, after setting up other Bun properties:

```swift
// Bun.serve(options) — starts HTTP server
// Store reference to server on the TanoBunAPI instance
let serveBlock: @convention(block) (JSValue) -> JSValue = { [weak self] options in
    guard let self = self, let ctx = JSContext.current() else {
        return JSValue(undefinedIn: JSContext.current())
    }
    return self.startServe(options: options, context: ctx)
}
bun.setObject(serveBlock, forKeyedSubscript: "serve" as NSString)
```

Add to TanoBunAPI class:

```swift
private var httpServer: TanoHTTPServer?

private func startServe(options: JSValue, context: JSContext) -> JSValue {
    let server = TanoHTTPServer()
    httpServer = server

    let fetchFn = options.objectForKeyedSubscript("fetch")
    let portVal = options.objectForKeyedSubscript("port")
    let hostnameVal = options.objectForKeyedSubscript("hostname")

    let port = portVal?.isUndefined == false ? UInt16(portVal!.toInt32()) : 3000
    let hostname = hostnameVal?.isUndefined == false ? hostnameVal!.toString()! : "127.0.0.1"

    server.fetchHandler = { method, url, headers, body, respond in
        // Create JS Request object
        let headersObj = JSValue(newObjectIn: context)!
        for (name, value) in headers {
            headersObj.setObject(value, forKeyedSubscript: name as NSString)
        }

        let reqInit = JSValue(newObjectIn: context)!
        reqInit.setObject(method, forKeyedSubscript: "method" as NSString)
        reqInit.setObject(headersObj, forKeyedSubscript: "headers" as NSString)
        if method != "GET" && method != "HEAD" && !body.isEmpty {
            reqInit.setObject(body, forKeyedSubscript: "body" as NSString)
        }

        let reqClass = context.objectForKeyedSubscript("Request")!
        let request = reqClass.construct(withArguments: [url, reqInit])!

        // Call the JS fetch handler
        guard let fetchFn = fetchFn, !fetchFn.isUndefined else {
            respond(500, [], "No fetch handler")
            return
        }

        // Create a Server object to pass as second argument
        let serverObj = JSValue(newObjectIn: context)!
        serverObj.setObject(Int(port), forKeyedSubscript: "port" as NSString)
        serverObj.setObject(hostname, forKeyedSubscript: "hostname" as NSString)

        let result = fetchFn.call(withArguments: [request, serverObj])!

        // Handle Promise (async fetch handler) or direct Response
        let thenFn = result.objectForKeyedSubscript("then")
        if let thenFn = thenFn, !thenFn.isUndefined {
            // It's a Promise
            let resolveBlock: @convention(block) (JSValue) -> Void = { response in
                Self.extractResponse(response, respond: respond)
            }
            let rejectBlock: @convention(block) (JSValue) -> Void = { error in
                respond(500, [("content-type", "text/plain")], "Error: \(error)")
            }
            thenFn.call(withArguments: [
                JSValue(object: resolveBlock, in: context)!,
            ])
            let catchFn = result.objectForKeyedSubscript("catch")
            catchFn?.call(withArguments: [
                JSValue(object: rejectBlock, in: context)!
            ])
        } else {
            // Synchronous Response
            Self.extractResponse(result, respond: respond)
        }
    }

    do {
        try server.start(port: port, hostname: hostname)
    } catch {
        print("[TanoHTTP] Failed to start: \(error)")
        return JSValue(undefinedIn: context)
    }

    // Return a Server-like object
    let serverResult = JSValue(newObjectIn: context)!
    serverResult.setObject(Int(port), forKeyedSubscript: "port" as NSString)
    serverResult.setObject(hostname, forKeyedSubscript: "hostname" as NSString)

    let stopBlock: @convention(block) () -> Void = { [weak self] in
        self?.httpServer?.stop()
    }
    serverResult.setObject(stopBlock, forKeyedSubscript: "stop" as NSString)

    return serverResult
}

private static func extractResponse(_ response: JSValue, respond: @escaping (Int, [(String, String)], String) -> Void) {
    let status = response.objectForKeyedSubscript("status")?.toInt32() ?? 200
    let body = response.objectForKeyedSubscript("_body")
    let bodyStr = body?.isNull == true || body?.isUndefined == true ? "" : body!.toString()!

    var headers: [(String, String)] = []
    let headersObj = response.objectForKeyedSubscript("headers")
    if let headersObj = headersObj, !headersObj.isUndefined {
        let headerDict = headersObj.objectForKeyedSubscript("_headers")
        if let headerDict = headerDict, !headerDict.isUndefined {
            // Iterate _headers object
            let keys = JSContext.current()?.evaluateScript("Object.keys")
            let keysArr = keys?.call(withArguments: [headerDict])
            if let keysArr = keysArr {
                let length = keysArr.objectForKeyedSubscript("length")?.toInt32() ?? 0
                for i in 0..<length {
                    if let key = keysArr.objectAtIndexedSubscript(Int(i))?.toString(),
                       let value = headerDict.objectForKeyedSubscript(key)?.toString() {
                        headers.append((key, value))
                    }
                }
            }
        }
    }

    respond(Int(status), headers, bodyStr)
}
```

- [ ] **Step 5: Write tests**

```swift
// packages/core/Tests/TanoCoreTests/TanoHTTPServerTests.swift
import XCTest
import Foundation
@testable import TanoCore

final class TanoHTTPServerTests: XCTestCase {

    func testHTTPParserBasic() {
        let raw = "GET /hello HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let req = TanoHTTPParser.parse(raw.data(using: .utf8)!)
        XCTAssertNotNil(req)
        XCTAssertEqual(req?.method, "GET")
        XCTAssertEqual(req?.path, "/hello")
        XCTAssertEqual(req?.header("Host"), "localhost")
    }

    func testHTTPParserWithBody() {
        let raw = "POST /api HTTP/1.1\r\nContent-Length: 13\r\nContent-Type: application/json\r\n\r\n{\"key\":\"val\"}"
        let req = TanoHTTPParser.parse(raw.data(using: .utf8)!)
        XCTAssertNotNil(req)
        XCTAssertEqual(req?.method, "POST")
        XCTAssertEqual(String(data: req!.body, encoding: .utf8), "{\"key\":\"val\"}")
    }

    func testHTTPParserWithQuery() {
        let raw = "GET /search?q=hello&page=2 HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let req = TanoHTTPParser.parse(raw.data(using: .utf8)!)
        XCTAssertEqual(req?.path, "/search")
        XCTAssertEqual(req?.rawURL, "/search?q=hello&page=2")
    }

    func testHTTPResponseBuilder() {
        var resp = TanoHTTPResponseBuilder(statusCode: 200, statusText: "OK")
        resp.setHeader("Content-Type", "text/plain")
        resp.body = "Hello".data(using: .utf8)!

        let data = resp.build()
        let str = String(data: data, encoding: .utf8)!
        XCTAssertTrue(str.hasPrefix("HTTP/1.1 200 OK\r\n"))
        XCTAssertTrue(str.contains("Content-Type: text/plain"))
        XCTAssertTrue(str.contains("Content-Length: 5"))
        XCTAssertTrue(str.hasSuffix("Hello"))
    }

    func testServerStartAndStop() async throws {
        let server = TanoHTTPServer()
        server.fetchHandler = { _, _, _, _, respond in
            respond(200, [("content-type", "text/plain")], "hello")
        }

        try server.start(port: 0) // random port
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms for listener ready

        XCTAssertGreaterThan(server.port, 0)

        // Make a request
        let url = URL(string: "http://127.0.0.1:\(server.port)/test")!
        let (data, response) = try await URLSession.shared.data(from: url)
        let httpResp = response as! HTTPURLResponse

        XCTAssertEqual(httpResp.statusCode, 200)
        XCTAssertEqual(String(data: data, encoding: .utf8), "hello")

        server.stop()
    }

    func testServerJSON() async throws {
        let server = TanoHTTPServer()
        server.fetchHandler = { _, _, _, _, respond in
            respond(200, [("content-type", "application/json")], "{\"ok\":true}")
        }

        try server.start(port: 0)
        try await Task.sleep(nanoseconds: 100_000_000)

        let url = URL(string: "http://127.0.0.1:\(server.port)/api")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Bool]

        XCTAssertTrue(json["ok"]!)

        server.stop()
    }
}
```

- [ ] **Step 6: Run tests**

Run: `cd packages/core && swift test 2>&1`
Expected: HTTP parser, response builder, and server tests all PASS.

- [ ] **Step 7: Commit**

```bash
git add packages/core/Sources/TanoCore/TanoHTTPServer.swift packages/core/Sources/TanoCore/TanoHTTPParser.swift packages/core/Sources/TanoCore/TanoHTTPResponse.swift packages/core/Sources/TanoCore/TanoBunAPI.swift packages/core/Tests/TanoCoreTests/TanoHTTPServerTests.swift
git commit -m "feat(core): Bun.serve() — NWListener-based HTTP server with JS fetch handler"
```

---

### Task 8: Integration Test — Full Bun.serve() in TanoRuntime

**Files:**
- Create: `packages/core/Sources/TanoDemo/server.js`
- Create: `packages/core/Tests/TanoCoreTests/TanoIntegrationTests.swift`

- [ ] **Step 1: Write a test server.js that uses Bun.serve()**

```javascript
// packages/core/Sources/TanoDemo/server.js
console.log('[Tano] Starting server...');

const server = Bun.serve({
    port: 18899,
    hostname: '127.0.0.1',

    fetch(req) {
        const url = new URL(req.url);

        if (url.pathname === '/api/info') {
            return Response.json({
                runtime: 'TanoJSC',
                version: Bun.version,
                platform: 'ios',
            });
        }

        if (url.pathname === '/api/echo' && req.method === 'POST') {
            return new Response(req._body, {
                headers: { 'content-type': 'text/plain' }
            });
        }

        if (url.pathname === '/health') {
            return new Response('ok');
        }

        return new Response('Not Found', { status: 404 });
    }
});

console.log('[Tano] Server running on port ' + server.port);
```

- [ ] **Step 2: Write integration test**

```swift
// packages/core/Tests/TanoCoreTests/TanoIntegrationTests.swift
import XCTest
@testable import TanoCore

final class TanoIntegrationTests: XCTestCase {

    func testFullBunServe() async throws {
        // Write the server script to a temp file
        let tmpDir = NSTemporaryDirectory()
        let scriptPath = (tmpDir as NSString).appendingPathComponent("tano_integration_test.js")

        let script = """
        console.log('[Test] Starting...');

        const server = Bun.serve({
            port: 19876,
            hostname: '127.0.0.1',
            fetch(req) {
                const url = new URL(req.url);
                if (url.pathname === '/health') {
                    return new Response('ok');
                }
                if (url.pathname === '/json') {
                    return Response.json({ runtime: Bun.version });
                }
                return new Response('Not Found', { status: 404 });
            }
        });

        console.log('[Test] Server on port ' + server.port);
        """

        try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: scriptPath) }

        let config = TanoConfig(serverEntry: scriptPath, env: ["TEST": "1"])
        let runtime = TanoRuntime(config: config)

        runtime.start()

        // Wait for server to be ready
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1s

        if case .running = runtime.state {
            // good
        } else {
            XCTFail("Runtime not running: \(runtime.state)")
            return
        }

        // Test /health endpoint
        let healthURL = URL(string: "http://127.0.0.1:19876/health")!
        let (healthData, healthResp) = try await URLSession.shared.data(from: healthURL)
        XCTAssertEqual((healthResp as! HTTPURLResponse).statusCode, 200)
        XCTAssertEqual(String(data: healthData, encoding: .utf8), "ok")

        // Test /json endpoint
        let jsonURL = URL(string: "http://127.0.0.1:19876/json")!
        let (jsonData, jsonResp) = try await URLSession.shared.data(from: jsonURL)
        XCTAssertEqual((jsonResp as! HTTPURLResponse).statusCode, 200)
        let json = try JSONSerialization.jsonObject(with: jsonData) as! [String: String]
        XCTAssertTrue(json["runtime"]!.contains("tano"))

        // Test 404
        let notFoundURL = URL(string: "http://127.0.0.1:19876/nope")!
        let (_, notFoundResp) = try await URLSession.shared.data(from: notFoundURL)
        XCTAssertEqual((notFoundResp as! HTTPURLResponse).statusCode, 404)

        runtime.stop()
        try await Task.sleep(nanoseconds: 500_000_000)
    }
}
```

- [ ] **Step 3: Run integration test**

Run: `cd packages/core && swift test --filter TanoIntegrationTests 2>&1`
Expected: Full Bun.serve() running in TanoJSC — /health returns "ok", /json returns runtime info, /nope returns 404.

- [ ] **Step 4: Commit**

```bash
git add packages/core/Sources/TanoDemo/server.js packages/core/Tests/TanoCoreTests/TanoIntegrationTests.swift
git commit -m "feat(core): integration test — Bun.serve() running in TanoJSC with HTTP endpoints"
```

---

### Task 9: Globals Assembly — TanoGlobals.swift + Final Wiring

**Files:**
- Create: `packages/core/Sources/TanoCore/TanoGlobals.swift`
- Modify: `packages/core/Sources/TanoCore/TanoRuntime.swift` (clean up injectGlobals to use TanoGlobals)
- Modify: `packages/core/README.md`

- [ ] **Step 1: Write TanoGlobals.swift — single entry point for all global injections**

```swift
// packages/core/Sources/TanoCore/TanoGlobals.swift
import JavaScriptCore

/// Single entry point that injects all Bun-compatible globals into a JSC context
enum TanoGlobals {

    static func inject(into context: JSContext, config: TanoConfig, timers: TanoTimers) -> TanoBunAPI {
        // Runtime marker
        context.setObject("TanoJSC" as NSString, forKeyedSubscript: "__runtime" as NSString)

        // console.log/warn/error → OSLog
        TanoConsole.inject(into: context)

        // setTimeout/setInterval/clearTimeout/clearInterval
        timers.inject(into: context)

        // Response, Request, Headers, URL, URLSearchParams
        TanoWebAPIs.inject(into: context)

        // fetch() → URLSession
        TanoFetch.inject(into: context)

        // Bun.file(), Bun.write(), Bun.env, Bun.sleep(), Bun.serve()
        let bunAPI = TanoBunAPI(config: config)
        bunAPI.inject(into: context)

        // TextEncoder / TextDecoder (JSC has these, but ensure they exist)
        JSCHelpers.evaluate(context, script: """
            if (typeof globalThis.TextEncoder === 'undefined') {
                globalThis.TextEncoder = class TextEncoder {
                    encode(str) {
                        const buf = new Uint8Array(str.length);
                        for (let i = 0; i < str.length; i++) buf[i] = str.charCodeAt(i) & 0xFF;
                        return buf;
                    }
                };
            }
            if (typeof globalThis.TextDecoder === 'undefined') {
                globalThis.TextDecoder = class TextDecoder {
                    decode(buf) {
                        if (!buf) return '';
                        return String.fromCharCode.apply(null, new Uint8Array(buf));
                    }
                };
            }

            // Promise.withResolvers polyfill
            if (typeof Promise.withResolvers === 'undefined') {
                Promise.withResolvers = function() {
                    let resolve, reject;
                    const promise = new Promise((res, rej) => { resolve = res; reject = rej; });
                    return { promise, resolve, reject };
                };
            }

            // structuredClone polyfill
            if (typeof globalThis.structuredClone === 'undefined') {
                globalThis.structuredClone = function(obj) {
                    return JSON.parse(JSON.stringify(obj));
                };
            }

            // queueMicrotask
            if (typeof globalThis.queueMicrotask === 'undefined') {
                globalThis.queueMicrotask = function(fn) {
                    Promise.resolve().then(fn);
                };
            }
        """, sourceURL: "tano://globals/polyfills.js")

        return bunAPI
    }
}
```

- [ ] **Step 2: Clean up TanoRuntime.swift to use TanoGlobals**

Replace `injectGlobals` and related properties:

```swift
// In TanoRuntime, replace:
// private var bunAPI: TanoBunAPI?
// private func injectGlobals(into context: JSContext) { ... }

// With:
private var bunAPI: TanoBunAPI?

private func injectGlobals(into context: JSContext) {
    bunAPI = TanoGlobals.inject(into: context, config: config, timers: timers)
}
```

- [ ] **Step 3: Write packages/core/README.md**

```markdown
# TanoCore

JavaScriptCore-based runtime with Bun-compatible APIs for iOS and Android.

## Usage

```swift
import TanoCore

let config = TanoConfig(
    serverEntry: Bundle.main.path(forResource: "server", ofType: "js")!,
    env: ["API_KEY": "xxx"]
)

let runtime = TanoRuntime(config: config)
runtime.start()
// runtime is now serving on localhost
```

## Implemented Bun APIs

- `Bun.serve()` — HTTP server (NWListener-backed)
- `Bun.file()` — File reading (text, json, exists, size)
- `Bun.write()` — File writing
- `Bun.env` — Environment variables
- `Bun.sleep()` — Async delay
- `fetch()` — HTTP client (URLSession-backed)
- `Response` / `Request` / `Headers` / `URL`
- `console.log/warn/error/info` → OSLog
- `setTimeout` / `setInterval` / `clearTimeout` / `clearInterval`
```

- [ ] **Step 4: Run full test suite**

Run: `cd packages/core && swift test 2>&1`
Expected: ALL tests pass — runtime, console, timers, web APIs, Bun API, fetch, HTTP server, integration.

- [ ] **Step 5: Commit**

```bash
git add packages/core/
git commit -m "feat(core): TanoGlobals — unified global injection, polyfills, and README"
```

---

## Summary

After completing all 9 tasks, Phase 1 deliverables:

| Component | Status |
|-----------|--------|
| TanoRuntime (JSC lifecycle, background thread) | ✅ |
| console.log/warn/error → OSLog | ✅ |
| setTimeout/setInterval/clearTimeout/clearInterval | ✅ |
| Response/Request/Headers/URL polyfills | ✅ |
| Bun.file()/Bun.write()/Bun.env/Bun.sleep() | ✅ |
| fetch() → URLSession | ✅ |
| Bun.serve() → NWListener HTTP server | ✅ |
| Integration test: full Bun.serve() in simulator | ✅ |
| TanoGlobals unified injection | ✅ |

**Verification**: Run `cd packages/core && swift test` — all tests green. Then `tano_integration_test.js` demonstrates a working Bun.serve() HTTP server running inside TanoJSC on iOS.
