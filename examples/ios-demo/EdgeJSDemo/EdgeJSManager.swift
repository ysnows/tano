//
//  EdgeJSManager.swift
//  EdgeJSDemo
//
//  Manages the Edge.js runtime lifecycle on a background thread.
//  Exposes @Published properties for SwiftUI binding.
//  Passes socket_path and extension_path to the EdgeJS runtime.
//

import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#endif

final class EdgeJSManager: ObservableObject {

    // MARK: - Published State

    @Published var isRunning: Bool = false
    @Published var lastOutput: String = ""

    // MARK: - Private State

    private var runtime: OpaquePointer?  // EdgeRuntime*
    private var runtimeThread: Thread?
    private var exitCode: Int32 = 0
    private let runtimeDone = DispatchSemaphore(value: 0)
    private static var processInitialized = false
    private static var runtimeActive = false  // Process-wide guard: only one runtime allowed

    // MARK: - Lifecycle

    /// Start the Edge.js runtime with the given JavaScript entry script.
    ///
    /// - Parameters:
    ///   - scriptPath: Absolute path to the JavaScript entry file.
    ///   - socketPath: UDS socket path for Swift <-> Node.js communication.
    ///   - extensionPath: Path to extension modules directory.
    func start(scriptPath: String, socketPath: String? = nil, extensionPath: String? = nil) {
        guard !isRunning, !EdgeJSManager.runtimeActive else {
            appendOutput("[EdgeJSManager] Already running.")
            return
        }
        EdgeJSManager.runtimeActive = true

        // Inject paths as environment variables BEFORE EdgeProcessInit so they're
        // visible to process.env in the JS runtime. EdgeJS inherits the host
        // process environment; config.socket_path is NOT auto-injected.
        if let sp = socketPath {
            setenv("ENCONVO_SOCKET_PATH", sp, 1)
        }
        if let ep = extensionPath {
            setenv("ENCONVO_EXTENSION_PATH", ep, 1)
        }
        // Set macOS user home for simulator (to find webapp and other macOS extensions)
        #if targetEnvironment(simulator)
        if let macHome = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] {
            setenv("ENCONVO_MACOS_HOME", macHome, 1)
        }
        #endif
        // Set data path for preferences/commands storage (iOS sandbox compatible)
        // Pre-create subdirectories since JSC's fs.mkdirSync may not handle recursive creation
        if let appSupportUrl = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let dataPath = appSupportUrl.appendingPathComponent("enconvo").path
            let subdirs = ["installed_preferences", "installed_commands", "installed_extensions"]
            for subdir in subdirs {
                let fullPath = (dataPath as NSString).appendingPathComponent(subdir)
                if !FileManager.default.fileExists(atPath: fullPath) {
                    try? FileManager.default.createDirectory(atPath: fullPath, withIntermediateDirectories: true)
                }
            }
            setenv("ENCONVO_DATA_PATH", dataPath, 1)
        }
        // Set bundle extensions path — js/extensions/ is inside the js resource folder
        if let bundlePath = Bundle.main.path(forResource: "extensions", ofType: nil, inDirectory: "js") {
            setenv("ENCONVO_BUNDLE_EXTENSIONS_PATH", bundlePath, 1)
        } else if let bundlePath = Bundle.main.resourcePath {
            let bundleExtPath = (bundlePath as NSString).appendingPathComponent("extensions")
            setenv("ENCONVO_BUNDLE_EXTENSIONS_PATH", bundleExtPath, 1)
        }

        // One-time process initialization (thread-safe internally).
        if !EdgeJSManager.processInitialized {
            let initStatus = EdgeProcessInit()
            guard initStatus == EDGE_OK else {
                appendOutput("[EdgeJSManager] EdgeProcessInit failed: \(initStatus.rawValue)")
                EdgeJSManager.runtimeActive = false
                return
            }
            EdgeJSManager.processInitialized = true
        }

        // Build the runtime configuration using nested withCString for memory safety.
        // Each withCString must be nested so pointers remain valid until EdgeRuntimeCreate copies them.
        func withOptionalCString<R>(_ string: String?, _ body: (UnsafePointer<CChar>?) -> R) -> R {
            if let s = string { return s.withCString { body($0) } }
            return body(nil)
        }

        let createdRuntime: OpaquePointer? = scriptPath.withCString { scriptCStr in
            withOptionalCString(socketPath) { socketCStr in
                withOptionalCString(extensionPath) { extensionCStr in
                    var config = EdgeRuntimeConfig()
                    config.script_path = scriptCStr
                    config.socket_path = socketCStr
                    config.extension_path = extensionCStr
                    config.argc = 0
                    config.argv = nil
                    config.on_fatal = { message, _ in
                        if let msg = message {
                            let str = String(cString: msg)
                            DispatchQueue.main.async {
                                print("[EdgeJS FATAL] \(str)")
                            }
                        }
                    }
                    config.user_data = nil
                    return EdgeRuntimeCreate(&config)
                }
            }
        }

        guard let rt = createdRuntime else {
            appendOutput("[EdgeJSManager] EdgeRuntimeCreate returned NULL.")
            EdgeJSManager.runtimeActive = false
            return
        }

        runtime = rt
        isRunning = true
        appendOutput("[EdgeJSManager] Runtime created. Starting background thread...")

        // Run the event loop on a dedicated background thread.
        let doneSema = self.runtimeDone
        let thread = Thread { [weak self] in
            guard let self = self, let rt = self.runtime else {
                doneSema.signal()
                return
            }

            let code = EdgeRuntimeRun(rt)

            DispatchQueue.main.async {
                self.exitCode = code
                self.isRunning = false
                EdgeJSManager.runtimeActive = false
                self.appendOutput("[EdgeJSManager] Runtime exited with code \(code).")
            }
            doneSema.signal() // Signal that EdgeRuntimeRun has returned
        }
        thread.name = "EdgeJS-Runtime"
        thread.qualityOfService = .userInitiated
        runtimeThread = thread
        thread.start()
    }

    /// Request graceful shutdown. Thread-safe; can be called from any thread.
    func stop() {
        guard let rt = runtime else {
            appendOutput("[EdgeJSManager] No runtime to stop.")
            return
        }

        appendOutput("[EdgeJSManager] Requesting shutdown...")
        EdgeRuntimeShutdown(rt)
    }

    deinit {
        // Ensure we shut down before releasing.
        if let rt = runtime {
            if EdgeRuntimeIsRunning(rt) != 0 {
                EdgeRuntimeShutdown(rt)
            }
            // Wait for EdgeRuntimeRun to return via semaphore, then safely destroy.
            // No spin-wait, no main-thread blocking.
            let rtCopy = rt
            let sema = runtimeDone
            DispatchQueue.global(qos: .utility).async {
                _ = sema.wait(timeout: .now() + 3.0)
                EdgeRuntimeDestroy(rtCopy)
            }
        }
        runtime = nil
    }

    // MARK: - App Lifecycle Hooks

    func onBackground() {
        appendOutput("[EdgeJSManager] App backgrounded.")
        beginBackgroundTask()
    }

    func onForeground() {
        appendOutput("[EdgeJSManager] App foregrounded.")
        endBackgroundTask()
    }

    func didReceiveMemoryWarning() {
        appendOutput("[EdgeJSManager] Memory warning — clearing caches.")
        // Send clearCache message to JS runtime via UDS
        do {
            try SocketUtil.sendRequestToClient(
                method: "clearCache",
                callId: "system",
                input: [:]
            )
        } catch {
            print("[EdgeJSManager] Failed to send clearCache: \(error)")
        }
    }

    // MARK: - Background Task Management

    #if canImport(UIKit)
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    private func beginBackgroundTask() {
        guard backgroundTaskID == .invalid else { return }
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "EdgeJS") { [weak self] in
            self?.appendOutput("[EdgeJSManager] Background time expired.")
            self?.endBackgroundTask()
        }
        appendOutput("[EdgeJSManager] Background task started.")
    }

    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }
    #else
    private func beginBackgroundTask() {}
    private func endBackgroundTask() {}
    #endif

    // MARK: - Helpers

    private func appendOutput(_ text: String) {
        DispatchQueue.main.async {
            self.lastOutput = text
        }
    }
}
