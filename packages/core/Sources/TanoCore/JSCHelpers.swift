import Foundation
import JavaScriptCore

/// Convenience wrappers around the JavaScriptCore C API.
public enum JSCHelpers {

    /// Evaluate a JavaScript string in the given context.
    ///
    /// If an exception is thrown inside JSC it is logged to stderr and
    /// the function returns `nil`.
    @discardableResult
    public static func evaluate(
        _ context: JSContext,
        script: String,
        sourceURL: String? = nil
    ) -> JSValue? {
        let url: URL? = sourceURL.flatMap { URL(string: $0) }

        // Capture any JSC exception.
        var caughtException: JSValue?
        let previousHandler = context.exceptionHandler
        context.exceptionHandler = { _, exception in
            caughtException = exception
        }

        let result: JSValue?
        if let url {
            result = context.evaluateScript(script, withSourceURL: url)
        } else {
            result = context.evaluateScript(script)
        }

        // Restore previous handler.
        context.exceptionHandler = previousHandler

        if let exception = caughtException {
            let message = exception.toString() ?? "unknown error"
            let line = exception.forProperty("line")?.toInt32() ?? 0
            let sourceFile = sourceURL ?? "<eval>"
            print("[TanoJSC] Error in \(sourceFile):\(line): \(message)")
            return nil
        }

        return result
    }

    /// Retrieve a nested property from the global object.
    ///
    /// For example `getProperty(ctx, path: "Bun.serve")` walks
    /// `globalThis.Bun` then `.serve`.
    public static func getProperty(
        _ context: JSContext,
        path: String
    ) -> JSValue? {
        let components = path.split(separator: ".").map(String.init)
        guard !components.isEmpty else { return nil }

        var current: JSValue? = context.globalObject
        for component in components {
            guard let next = current?.forProperty(component),
                  !next.isUndefined else {
                return nil
            }
            current = next
        }
        return current
    }
}
