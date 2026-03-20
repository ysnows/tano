import SwiftUI
import WebKit

/// WebView shell with WKScriptMessageHandler for Swift <-> WebView control channel.
/// Data flows: WebView → HTTP → Node.js (data), WebView → WKScriptMessageHandler → Swift (control).
struct WebBridgeView: UIViewRepresentable {

    func makeCoordinator() -> WebBridgeCoordinator {
        WebBridgeCoordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Allow localhost connections from file:// pages
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        // Register the "enconvo" script message handler for control messages
        let contentController = config.userContentController
        contentController.add(context.coordinator, name: "enconvo")

        // Inject the bridge JS into the page
        let bridgeScript = WKUserScript(
            source: WebBridgeCoordinator.bridgeJavaScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        contentController.addUserScript(bridgeScript)

        let webView = WKWebView(frame: .zero, configuration: config)
        if #available(iOS 16.4, *) { webView.isInspectable = true }

        // Store reference for evaluateJavaScript calls
        context.coordinator.webView = webView

        if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "web") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

// MARK: - Coordinator

class WebBridgeCoordinator: NSObject, WKScriptMessageHandler {
    weak var webView: WKWebView?

    /// Handle messages from WebView via webkit.messageHandlers.enconvo.postMessage()
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String
        else {
            print("[WebBridge] Invalid message from WebView")
            return
        }

        let method = body["method"] as? String ?? ""
        let data = body["data"] as? [String: Any] ?? [:]

        switch type {
        case "control":
            handleControlMessage(method: method, data: data)
        case "native":
            handleNativeCall(method: method, data: data)
        default:
            print("[WebBridge] Unknown message type: \(type)")
        }
    }

    // MARK: - Control Messages (WebView → Swift)

    private func handleControlMessage(method: String, data: [String: Any]) {
        switch method {
        case "ready":
            print("[WebBridge] WebView ready")
        case "log":
            let message = data["message"] as? String ?? ""
            print("[WebBridge:JS] \(message)")
        default:
            print("[WebBridge] Unhandled control: \(method)")
        }
    }

    // MARK: - Native Calls (WebView → Swift → ProducerTasks)

    private func handleNativeCall(method: String, data: [String: Any]) {
        let context = TaskContext(
            callId: "webview|native",
            requestId: UUID().uuidString,
            stateId: "",
            sendId: "",
            type: "request",
            inputParams: data,
            payloads: data,
            client: nil
        ) { [weak self] result in
            self?.sendToWebView(event: "nativeResult", data: result)
        }

        let handled = SocketManager.shared.producer?.producerTasks.handle(method: method, context: context) ?? false
        if !handled {
            sendToWebView(event: "nativeResult", data: ["error": "Unknown method: \(method)"])
        }
    }

    // MARK: - Swift → WebView

    func sendToWebView(event: String, data: [String: Any]) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: data),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }

        let safeEvent = event.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")

        let js = "(function(){var d=\(jsonString);window.onEnconvoMessage&&window.onEnconvoMessage('\(safeEvent)',d)})();"
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    // MARK: - Bridge JavaScript

    /// Injected at document start to provide the bridge API.
    static let bridgeJavaScript = """
    (function() {
        // Bridge API for WebView → Swift control messages
        window.EnconvoBridge = {
            // Send a control message to Swift
            sendControl: function(method, data) {
                window.webkit.messageHandlers.enconvo.postMessage({
                    type: 'control',
                    method: method,
                    data: data || {}
                });
            },
            // Call a native Swift function
            callNative: function(method, data) {
                window.webkit.messageHandlers.enconvo.postMessage({
                    type: 'native',
                    method: method,
                    data: data || {}
                });
            },
            // Log to Swift console
            log: function(message) {
                this.sendControl('log', { message: String(message) });
            }
        };

        // Callback handler for Swift → WebView messages
        // Override this in your web app to handle messages from Swift
        window.onEnconvoMessage = window.onEnconvoMessage || function(event, data) {
            console.log('[EnconvoBridge] Received:', event, data);
        };

        // Signal ready
        window.EnconvoBridge.sendControl('ready');
    })();
    """;
}
