import Foundation
import JavaScriptCore

/// Single entry point for injecting all global bindings into a JSContext.
///
/// This consolidates runtime marker, console, timers, Web APIs, Bun shims,
/// fetch, and polyfills into one call.
enum TanoGlobals {
    static func inject(
        into context: JSContext,
        config: TanoConfig,
        timers: TanoTimers,
        bunAPI: TanoBunAPI,
        jscPerform: @escaping (@escaping () -> Void) -> Void
    ) {
        // 1. Runtime marker
        context.setObject("TanoJSC" as NSString, forKeyedSubscript: "__runtime" as NSString)

        // 2. console → OSLog
        TanoConsole.inject(into: context)

        // 3. Timers
        timers.inject(into: context)

        // 4. Web APIs (Response, Request, Headers, URL)
        TanoWebAPIs.inject(into: context)

        // 5. Bun global (file, write, env, sleep, serve)
        bunAPI.inject(into: context)

        // 6. fetch → URLSession
        TanoFetch.inject(into: context, jscPerform: jscPerform)

        // 7. WebSocket → URLSessionWebSocketTask
        TanoWebSocket.inject(into: context, jscPerform: jscPerform)

        // 8. Additional polyfills
        JSCHelpers.evaluate(context, script: polyfills, sourceURL: "tano://globals/polyfills.js")
    }

    private static let polyfills = """
    // TextEncoder / TextDecoder (may exist in JSC, ensure available)
    if (typeof globalThis.TextEncoder === 'undefined') {
        globalThis.TextEncoder = class TextEncoder {
            encode(str) {
                var buf = new Uint8Array(str.length);
                for (var i = 0; i < str.length; i++) buf[i] = str.charCodeAt(i) & 0xFF;
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

    // queueMicrotask
    if (typeof globalThis.queueMicrotask === 'undefined') {
        globalThis.queueMicrotask = function(fn) {
            Promise.resolve().then(fn);
        };
    }

    // structuredClone (simple JSON-based)
    if (typeof globalThis.structuredClone === 'undefined') {
        globalThis.structuredClone = function(obj) {
            return JSON.parse(JSON.stringify(obj));
        };
    }
    """
}
