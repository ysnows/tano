import SwiftUI
import WebKit

/// WebappView — loads the Enconvo management UI (extension config, chat, workflows).
///
/// The webapp can be loaded from:
///   1. Local HTTP server (http://127.0.0.1:18899/webapp/...) — served by Node.js
///   2. Remote URL (https://app.enconvo.com/...) — cloud-hosted
///   3. Bundle file (web/webapp/index.html) — offline fallback
///
/// Communication:
///   - WebView → Swift: WKScriptMessageHandler ("enconvoWebapp")
///   - Swift → WebView: evaluateJavaScript("window.onEnconvoMessage(...)")
///   - WebView → Node.js: HTTP API (fetch localhost)
struct WebappView: UIViewRepresentable {
    let initialPath: String
    let queryParams: [String: String]

    init(path: String = "/", queryParams: [String: String] = [:]) {
        self.initialPath = path
        self.queryParams = queryParams
    }

    func makeCoordinator() -> WebappCoordinator {
        WebappCoordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        let contentController = config.userContentController
        contentController.add(context.coordinator, name: "enconvoWebapp")

        // Inject bridge + Enconvo API shim
        let bridgeScript = WKUserScript(
            source: WebappCoordinator.webappBridgeJS,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        contentController.addUserScript(bridgeScript)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        if #available(iOS 16.4, *) { webView.isInspectable = true }

        context.coordinator.webView = webView

        // Build URL — webapp routes are served under /webapp/ prefix
        let baseURL = "http://127.0.0.1:18899"
        let webappPath = initialPath.hasPrefix("/api") || initialPath.hasPrefix("/settings") || initialPath.hasPrefix("/terminal")
            ? initialPath  // Direct routes — not under /webapp
            : "/webapp" + initialPath  // Webapp routes go through static file server
        var urlString = baseURL + webappPath
        if !queryParams.isEmpty {
            let params = queryParams.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            urlString += "?" + params.joined(separator: "&")
        }

        if let url = URL(string: urlString) {
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

// MARK: - Settings View (SwiftUI wrapper)

/// Displays extension settings for a specific command.
struct ExtensionSettingsView: View {
    let commandKey: String

    var body: some View {
        WebappView(
            path: "/settings",
            queryParams: ["commandKey": commandKey]
        )
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Chat view powered by the webapp.
struct WebappChatView: View {
    let conversationId: String

    init(conversationId: String = "") {
        self.conversationId = conversationId
    }

    var body: some View {
        WebappView(
            path: "/chat",
            queryParams: conversationId.isEmpty ? [:] : ["id": conversationId]
        )
    }
}

/// Extension store / marketplace view.
struct ExtensionStoreView: View {
    var body: some View {
        WebappView(path: "/store")
    }
}

// MARK: - Coordinator

class WebappCoordinator: NSObject, WKScriptMessageHandler {
    weak var webView: WKWebView?

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String
        else { return }

        let data = body["data"] as? [String: Any] ?? [:]

        switch action {
        case "executeCommand":
            handleExecuteCommand(data: data)
        case "getPreferences":
            handleGetPreferences(data: data)
        case "setPreference":
            handleSetPreference(data: data)
        case "navigate":
            handleNavigate(data: data)
        case "native":
            handleNativeCall(method: data["method"] as? String ?? "", data: data)
        default:
            print("[WebappBridge] Unhandled action: \(action)")
        }
    }

    // MARK: - Action Handlers

    private func handleExecuteCommand(data: [String: Any]) {
        guard let callId = data["callId"] as? String else { return }
        let input = data["input"] as? [String: Any] ?? [:]
        let stateId = data["stateId"] as? String ?? UUID().uuidString

        Task {
            let result = await NodeJsTask.call(
                callId: callId,
                stateId: stateId,
                input: input
            ) { [weak self] streamPayloads in
                // Forward stream chunks to webapp
                self?.sendToWebapp(event: "stream", data: streamPayloads)
            }
            sendToWebapp(event: "commandResult", data: result.body ?? ["error": "No result"])
        }
    }

    private func handleGetPreferences(data: [String: Any]) {
        // Preferences are loaded via HTTP API (/api/preferences)
        // This handler is for the WKScriptMessageHandler path
        guard let commandKey = data["commandKey"] as? String else { return }
        sendToWebapp(event: "preferencesLoaded", data: ["commandKey": commandKey, "note": "Use HTTP /api/preferences endpoint"])
    }

    private func handleSetPreference(data: [String: Any]) {
        guard let commandKey = data["commandKey"] as? String,
              let name = data["name"] as? String
        else { return }
        let value = data["value"] ?? ""

        // Forward to Node.js via HTTP
        sendToWebapp(event: "preferenceSet", data: ["commandKey": commandKey, "name": name, "value": value, "success": true])
    }

    private func handleNavigate(data: [String: Any]) {
        guard let path = data["path"] as? String,
              let url = URL(string: "http://127.0.0.1:18899\(path)")
        else { return }

        DispatchQueue.main.async { [weak self] in
            self?.webView?.load(URLRequest(url: url))
        }
    }

    private func handleNativeCall(method: String, data: [String: Any]) {
        let payloads = data["payloads"] as? [String: Any] ?? data
        let context = TaskContext(
            callId: "webapp|native",
            requestId: UUID().uuidString,
            stateId: "",
            sendId: "",
            type: "request",
            inputParams: payloads,
            payloads: payloads,
            client: nil
        ) { [weak self] result in
            self?.sendToWebapp(event: "nativeResult", data: result)
        }

        let handled = SocketManager.shared.producer?.producerTasks.handle(method: method, context: context) ?? false
        if !handled {
            sendToWebapp(event: "nativeResult", data: ["error": "Unknown method: \(method)"])
        }
    }

    // MARK: - Swift → Webapp

    func sendToWebapp(event: String, data: [String: Any]) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: data),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }

        // Escape event name for JS string literal
        let safeEvent = event.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")

        // Insert JSON directly as JS object literal (not inside a string)
        // This avoids all quoting/escaping issues since JSONSerialization output is valid JS
        let js = "(function(){var d=\(jsonString);window.onEnconvoMessage&&window.onEnconvoMessage('\(safeEvent)',d)})();"
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    // MARK: - Bridge JavaScript

    static let webappBridgeJS = """
    (function() {
        window.EnconvoWebapp = {
            executeCommand: function(callId, input, stateId) {
                window.webkit.messageHandlers.enconvoWebapp.postMessage({
                    action: 'executeCommand',
                    data: { callId: callId, input: input || {}, stateId: stateId || '' }
                });
            },
            getPreferences: function(commandKey) {
                // Prefer HTTP API for full preference resolution
                return fetch('http://127.0.0.1:18899/api/preferences', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ commandKey: commandKey })
                }).then(r => r.json());
            },
            setPreference: function(commandKey, name, value) {
                return fetch('http://127.0.0.1:18899/api/preferences', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ commandKey: commandKey, name: name, value: value, action: 'set' })
                }).then(r => r.json());
            },
            navigate: function(path) {
                window.webkit.messageHandlers.enconvoWebapp.postMessage({
                    action: 'navigate',
                    data: { path: path }
                });
            },
            callNative: function(method, payloads) {
                window.webkit.messageHandlers.enconvoWebapp.postMessage({
                    action: 'native',
                    data: { method: method, payloads: payloads || {} }
                });
            },
            // HTTP-based API for data operations
            api: function(path, body) {
                return fetch('http://127.0.0.1:18899' + path, {
                    method: body ? 'POST' : 'GET',
                    headers: body ? { 'Content-Type': 'application/json' } : {},
                    body: body ? JSON.stringify(body) : undefined
                }).then(r => r.json());
            }
        };

        // Message handler from Swift
        window.onEnconvoMessage = window.onEnconvoMessage || function(event, data) {
            console.log('[EnconvoWebapp] Received:', event, data);
            // Dispatch custom event for webapp frameworks (React, etc.)
            window.dispatchEvent(new CustomEvent('enconvo:' + event, { detail: data }));
        };

        console.log('[EnconvoWebapp] Bridge initialized');
    })();
    """;
}
