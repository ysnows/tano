import Foundation
import JavaScriptCore

// MARK: - TanoConfig

/// Configuration for the Tano runtime.
public struct TanoConfig: Sendable {
    /// Path to the JavaScript entry file that the runtime will evaluate on start.
    public var serverEntry: String
    /// Environment variables exposed to the JS context.
    public var env: [String: String]
    /// Writable data path (e.g. for caches or databases).
    public var dataPath: String

    public init(
        serverEntry: String,
        env: [String: String] = [:],
        dataPath: String = ""
    ) {
        self.serverEntry = serverEntry
        self.env = env
        self.dataPath = dataPath
    }
}

// MARK: - TanoRuntime

/// A JavaScriptCore runtime that runs on a dedicated background thread
/// with its own CFRunLoop.
///
/// All JSC operations are confined to the runtime thread. Other threads
/// can schedule work via ``performOnJSCThread(_:)``.
public final class TanoRuntime: @unchecked Sendable {

    // MARK: State

    /// Runtime lifecycle state.
    public enum State: Sendable, CustomStringConvertible {
        case idle
        case starting
        case running
        case stopping
        case stopped
        case error(String)

        public var description: String {
            switch self {
            case .idle:             return "idle"
            case .starting:         return "starting"
            case .running:          return "running"
            case .stopping:         return "stopping"
            case .stopped:          return "stopped"
            case .error(let msg):   return "error(\(msg))"
            }
        }
    }

    // MARK: Properties

    private let config: TanoConfig

    private let stateLock = NSLock()
    private var _state: State = .idle

    /// Thread-safe access to the current runtime state.
    public var state: State {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return _state
        }
        set {
            stateLock.lock()
            _state = newValue
            stateLock.unlock()
        }
    }

    /// The dedicated runtime thread.
    private var runtimeThread: Thread?

    /// The CFRunLoop of the runtime thread. Set once the thread starts.
    private var runLoop: CFRunLoop?
    private let runLoopLock = NSLock()

    /// The JSContext – only accessed from the runtime thread.
    /// Internal visibility so tests (via @testable import) can access it
    /// inside `performOnJSCThread` blocks.
    var jsContext: JSContext?

    /// Timer manager (setTimeout / setInterval).
    private var timers: TanoTimers?

    /// Bun API shim (Bun.file, Bun.write, Bun.env, Bun.sleep, Bun.serve).
    private var bunAPI: TanoBunAPI?

    // MARK: Init

    public init(config: TanoConfig) {
        self.config = config
    }

    // MARK: Lifecycle

    /// Spawn the dedicated background thread, create the JSContext,
    /// inject globals, evaluate the server entry script, and start
    /// the run loop.
    public func start() {
        state = .starting

        let thread = Thread { [weak self] in
            self?.runtimeMain()
        }
        thread.name = "dev.tano.runtime"
        thread.qualityOfService = .userInitiated
        runtimeThread = thread
        thread.start()
    }

    /// Stop the runtime by terminating the run loop on the JSC thread.
    public func stop() {
        state = .stopping

        runLoopLock.lock()
        let rl = runLoop
        runLoopLock.unlock()

        if let rl {
            CFRunLoopStop(rl)
        }
    }

    /// Schedule a block to execute on the JSC thread's run loop.
    ///
    /// This is the **primary** mechanism for other threads to interact
    /// with the JSContext safely. JSC contexts are **not** thread-safe,
    /// so all evaluation / value access must go through this method
    /// (or happen during the initial thread setup in ``runtimeMain()``).
    public func performOnJSCThread(_ block: @escaping () -> Void) {
        runLoopLock.lock()
        let rl = runLoop
        runLoopLock.unlock()

        guard let rl else {
            print("[TanoRuntime] performOnJSCThread called but run loop not ready")
            return
        }

        CFRunLoopPerformBlock(rl, CFRunLoopMode.defaultMode.rawValue, block)
        CFRunLoopWakeUp(rl)
    }

    // MARK: - Runtime Thread Main

    /// Entry point that runs on the dedicated thread.
    private func runtimeMain() {
        // 1. Create JSContext
        let context = JSContext()!
        jsContext = context

        // Store the current run loop before doing anything else.
        let currentRunLoop = CFRunLoopGetCurrent()!
        runLoopLock.lock()
        runLoop = currentRunLoop
        runLoopLock.unlock()

        // 2. Set up default exception handler
        context.exceptionHandler = { _, exception in
            let message = exception?.toString() ?? "unknown error"
            print("[TanoJSC] Unhandled exception: \(message)")
        }

        // 3. Create timers (needs jscPerform)
        timers = TanoTimers(jscPerform: { [weak self] block in
            self?.performOnJSCThread(block)
        })

        // 3b. Create Bun API shim
        bunAPI = TanoBunAPI(config: config, jscPerform: { [weak self] block in
            self?.performOnJSCThread(block)
        })

        // 4. Inject globals
        injectGlobals(into: context)

        // 5. Evaluate server entry script (if provided and file exists)
        if !config.serverEntry.isEmpty {
            let entryPath = config.serverEntry
            if FileManager.default.fileExists(atPath: entryPath) {
                do {
                    let script = try String(contentsOfFile: entryPath, encoding: .utf8)
                    JSCHelpers.evaluate(context, script: script, sourceURL: entryPath)
                } catch {
                    state = .error("Failed to read entry script: \(error.localizedDescription)")
                    return
                }
            } else {
                state = .error("Entry script not found: \(entryPath)")
                return
            }
        }

        // 6. Mark as running
        state = .running

        // 7. Run the run loop — blocks until CFRunLoopStop is called.
        CFRunLoopRun()

        // 8. Cleanup after run loop exits
        bunAPI?.httpServer?.stop()
        bunAPI = nil
        timers?.cancelAll()
        timers = nil
        jsContext = nil

        runLoopLock.lock()
        runLoop = nil
        runLoopLock.unlock()

        state = .stopped
    }

    // MARK: - Globals Injection

    /// Inject minimal global bindings into the JSContext.
    ///
    /// This will be expanded in subsequent tasks (timers, fetch, console, etc.).
    private func injectGlobals(into context: JSContext) {
        // Runtime marker so JS code can detect it's running inside Tano.
        context.setObject("TanoJSC" as NSString, forKeyedSubscript: "__runtime" as NSString)

        // console.log/warn/error/info/debug → OSLog
        TanoConsole.inject(into: context)

        // setTimeout / setInterval / clearTimeout / clearInterval
        timers?.inject(into: context)

        // Response / Request / Headers / URLSearchParams polyfills
        TanoWebAPIs.inject(into: context)

        // Bun.file / Bun.write / Bun.env / Bun.sleep / Bun.serve
        bunAPI?.inject(into: context)

        // fetch() → URLSession bridge
        TanoFetch.inject(into: context, jscPerform: { [weak self] block in
            self?.performOnJSCThread(block)
        })
    }
}
