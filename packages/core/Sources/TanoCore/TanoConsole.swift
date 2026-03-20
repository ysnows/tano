import Foundation
import JavaScriptCore
import os

/// Maps `console.log/warn/error/info/debug` to Apple's unified logging (OSLog).
public enum TanoConsole {

    // MARK: - Logger

    private static let logger = Logger(subsystem: "dev.tano.runtime", category: "JS")

    // MARK: - Capture (for tests)

    /// When `true`, log messages are appended to ``capturedLogs``.
    /// Leave `false` in production to avoid unbounded memory growth.
    public static var captureEnabled = false

    /// Captured log entries (level + formatted message). Only populated
    /// when ``captureEnabled`` is `true`.
    public private(set) static var capturedLogs: [(level: String, message: String)] = []

    /// Remove all captured log entries.
    public static func clearCapturedLogs() {
        capturedLogs.removeAll()
    }

    // MARK: - Injection

    /// Injects a `console` object with `log`, `warn`, `error`, `info`,
    /// and `debug` methods into the given JSContext.
    public static func inject(into context: JSContext) {
        let console = JSValue(newObjectIn: context)!

        let makeHandler: (String, OSLogType) -> @convention(block) () -> Void = { level, logType in
            return {
                let args = JSContext.currentArguments() as? [JSValue] ?? []
                let message = args.map { $0.toString() ?? "undefined" }.joined(separator: " ")
                logger.log(level: logType, "\(message, privacy: .public)")
                if captureEnabled {
                    capturedLogs.append((level: level, message: message))
                }
            }
        }

        console.setObject(makeHandler("log",   .debug),   forKeyedSubscript: "log"   as NSString)
        console.setObject(makeHandler("warn",  .default), forKeyedSubscript: "warn"  as NSString)
        console.setObject(makeHandler("error", .error),   forKeyedSubscript: "error" as NSString)
        console.setObject(makeHandler("info",  .info),    forKeyedSubscript: "info"  as NSString)
        console.setObject(makeHandler("debug", .debug),   forKeyedSubscript: "debug" as NSString)

        context.setObject(console, forKeyedSubscript: "console" as NSString)
    }
}
