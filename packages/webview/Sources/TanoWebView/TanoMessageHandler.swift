#if canImport(WebKit)
import Foundation
import WebKit
import TanoBridge

// MARK: - TanoMessageHandler

/// WKScriptMessageHandler that bridges `window.Tano.invoke()` and `window.Tano.send()`
/// calls from the WebView to the native plugin system.
///
/// When the WebView's JavaScript calls `window.Tano.invoke(plugin, method, params)`,
/// the message is posted to this handler, which routes it through the ``PluginRouter``
/// and sends the result (or error) back to the WebView via `evaluateJavaScript`.
class TanoMessageHandler: NSObject, WKScriptMessageHandler {

    /// Reference to the WebView for sending results back via evaluateJavaScript.
    weak var webView: WKWebView?

    /// Plugin router for dispatching invoke calls to registered plugins.
    var pluginRouter: PluginRouter?

    /// Callback for fire-and-forget events sent via `window.Tano.send()`.
    var onEvent: ((String, [String: Any]) -> Void)?

    // MARK: - WKScriptMessageHandler

    func userContentController(
        _ controller: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else {
            print("[TanoWebView] Invalid message from WebView")
            return
        }

        switch type {
        case "invoke":
            handleInvoke(body)
        case "event":
            handleEvent(body)
        default:
            print("[TanoWebView] Unknown message type: \(type)")
        }
    }

    // MARK: - Invoke Handling

    private func handleInvoke(_ body: [String: Any]) {
        guard let callId = body["callId"] as? String,
              let plugin = body["plugin"] as? String,
              let method = body["method"] as? String else {
            print("[TanoWebView] Invoke message missing required fields")
            return
        }

        let params = body["params"] as? [String: Any] ?? [:]

        guard let router = pluginRouter else {
            rejectInWebView(callId: callId, error: "No plugin router configured")
            return
        }

        // Build a bridge message and route it through the PluginRouter
        let message = TanoBridgeMessage.request(
            callId: callId,
            plugin: plugin,
            method: method,
            params: params
        )

        router.handle(message: message) { [weak self] result in
            if let result = result {
                self?.resolveInWebView(callId: callId, result: result)
            } else {
                self?.rejectInWebView(
                    callId: callId,
                    error: "Plugin '\(plugin)' failed to handle '\(method)'"
                )
            }
        }
    }

    // MARK: - Event Handling

    private func handleEvent(_ body: [String: Any]) {
        let event = body["event"] as? String ?? ""
        let data = body["data"] as? [String: Any] ?? [:]
        onEvent?(event, data)
    }

    // MARK: - WebView Response

    /// Resolve a pending invoke in the WebView with a successful result.
    func resolveInWebView(callId: String, result: Any?) {
        let jsonResult: String
        if let result = result {
            if let data = try? JSONSerialization.data(withJSONObject: result),
               let str = String(data: data, encoding: .utf8) {
                jsonResult = str
            } else {
                // Wrap non-serializable values as a JSON string
                let escaped = String(describing: result)
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                jsonResult = "\"\(escaped)\""
            }
        } else {
            jsonResult = "null"
        }

        let escapedCallId = callId.replacingOccurrences(of: "'", with: "\\'")
        let js = "window.Tano._resolve('\(escapedCallId)', \(jsonResult))"
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    /// Reject a pending invoke in the WebView with an error message.
    func rejectInWebView(callId: String, error: String) {
        let escapedCallId = callId.replacingOccurrences(of: "'", with: "\\'")
        let escapedError = error
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        let js = "window.Tano._reject('\(escapedCallId)', '\(escapedError)')"
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    /// Emit an event to the WebView's event listeners.
    func emitEventInWebView(event: String, data: [String: Any]) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: data),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            print("[TanoWebView] Failed to serialize event data for '\(event)'")
            return
        }

        let escapedEvent = event
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        let js = "window.Tano._emit('\(escapedEvent)', \(jsonString))"
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}
#endif
