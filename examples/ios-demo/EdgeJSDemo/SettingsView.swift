import SwiftUI
import WebKit

// MARK: - Settings Menu Data

struct SettingsMenuItem: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let webappPath: String  // Path appended to /webapp/
}

struct SettingsMenuGroup: Identifiable {
    let id = UUID()
    let title: String
    let items: [SettingsMenuItem]
}

// MARK: - iOS Settings View

struct SettingsView: View {
    @State private var searchText = ""

    private let menuGroups: [SettingsMenuGroup] = [
        SettingsMenuGroup(title: "AI Providers", items: [
            SettingsMenuItem(title: "AI Model", icon: "cube.transparent.fill",
                           webappPath: "extension_settings?extensionName=llm"),
            SettingsMenuItem(title: "Text-to-Speech", icon: "waveform.circle.fill",
                           webappPath: "provider_settings?providerCategory=tts"),
            SettingsMenuItem(title: "Image Generation", icon: "photo.fill",
                           webappPath: "provider_settings?providerCategory=image_create"),
            SettingsMenuItem(title: "Web Search", icon: "globe",
                           webappPath: "provider_settings?providerCategory=web_search"),
            SettingsMenuItem(title: "OCR", icon: "doc.text.viewfinder",
                           webappPath: "provider_settings?providerCategory=ocr"),
        ]),
        SettingsMenuGroup(title: "Agents", items: [
            SettingsMenuItem(title: "Agent List", icon: "person.2.fill",
                           webappPath: "agent_list"),
            SettingsMenuItem(title: "Memory", icon: "brain.head.profile.fill",
                           webappPath: "memory_management"),
        ]),
        SettingsMenuGroup(title: "Extensions", items: [
            SettingsMenuItem(title: "Extension Store", icon: "cart.circle.fill",
                           webappPath: "store"),
            SettingsMenuItem(title: "Installed", icon: "puzzlepiece.extension.fill",
                           webappPath: "installed_extensions"),
            SettingsMenuItem(title: "Skills", icon: "star.fill",
                           webappPath: "skills"),
        ]),
        SettingsMenuGroup(title: "Knowledge Base", items: [
            SettingsMenuItem(title: "Knowledge Base", icon: "books.vertical.fill",
                           webappPath: "knowledge_base_management"),
            SettingsMenuItem(title: "Embeddings", icon: "k.circle.fill",
                           webappPath: "provider_settings?providerCategory=embeddings"),
        ]),
        SettingsMenuGroup(title: "Workflows", items: [
            SettingsMenuItem(title: "Workflow Store", icon: "doc.text.fill",
                           webappPath: "store?categories=Workflow"),
        ]),
        SettingsMenuGroup(title: "Credentials", items: [
            SettingsMenuItem(title: "API Keys", icon: "key.viewfinder",
                           webappPath: "credential_management?extensionName=credentials"),
        ]),
        SettingsMenuGroup(title: "Account", items: [
            SettingsMenuItem(title: "My Profile", icon: "person.fill",
                           webappPath: "command_settings?commandKey=enconvo|my_profile&titleEditable=false&title=My%20Profile"),
        ]),
    ]

    private var filteredGroups: [SettingsMenuGroup] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return menuGroups }
        return menuGroups.compactMap { group in
            let matched = group.items.filter { $0.title.localizedCaseInsensitiveContains(keyword) }
            guard !matched.isEmpty else { return nil }
            return SettingsMenuGroup(title: group.title, items: matched)
        }
    }

    var body: some View {
        NavigationView {
            List {
                ForEach(filteredGroups) { group in
                    Section(header: Text(group.title)) {
                        ForEach(group.items) { item in
                            NavigationLink(destination: SettingsWebView(item: item)) {
                                Label(item.title, systemImage: item.icon)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $searchText, prompt: "Search settings...")
            .navigationTitle("Settings")
        }
        .navigationViewStyle(.stack)
    }
}

// MARK: - Settings Web View (loads webapp page)

struct SettingsWebView: View {
    let item: SettingsMenuItem

    var body: some View {
        SettingsWebViewRepresentable(path: item.webappPath)
            .ignoresSafeArea(.all, edges: .bottom)
            .navigationTitle(item.title)
            .navigationBarTitleDisplayMode(.inline)
    }
}

struct SettingsWebViewRepresentable: UIViewRepresentable {
    let path: String

    func makeCoordinator() -> SettingsWebCoordinator {
        SettingsWebCoordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        let contentController = config.userContentController
        contentController.add(context.coordinator, name: "enconvoParentPort")

        // Inject parentPort bridge that the webapp expects
        let bridgeScript = WKUserScript(
            source: SettingsWebCoordinator.parentPortBridgeJS,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        contentController.addUserScript(bridgeScript)

        let webView = WKWebView(frame: .zero, configuration: config)
        if #available(iOS 16.4, *) { webView.isInspectable = true }
        webView.allowsBackForwardNavigationGestures = true

        context.coordinator.webView = webView

        let urlString = "http://127.0.0.1:18899/webapp/\(path)"
        if let url = URL(string: urlString) {
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

// MARK: - Settings Web Coordinator with parentPort bridge

class SettingsWebCoordinator: NSObject, WKScriptMessageHandler {
    weak var webView: WKWebView?
    private var pendingRequests: [String: Bool] = [:]

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any] else { return }

        let method = body["method"] as? String ?? ""
        let callId = body["callId"] as? String ?? ""
        let requestId = body["requestId"] as? String ?? ""
        let payloads = body["payloads"] as? [String: Any] ?? [:]

        // Route through Node.js server via HTTP (which handles UDS to Swift)
        Task {
            await handleParentPortMessage(
                method: method, callId: callId, requestId: requestId, payloads: payloads
            )
        }
    }

    private func handleParentPortMessage(method: String, callId: String, requestId: String, payloads: [String: Any]) async {
        // Forward the message to the Node.js server which handles it via the extension system
        guard let url = URL(string: "http://127.0.0.1:18899/api/native") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "method": method,
            "payloads": payloads,
            "callId": callId,
            "requestId": requestId,
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return }
        request.httpBody = httpBody

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                sendResponse(requestId: requestId, callId: callId, method: method, payloads: result)
            }
        } catch {
            sendResponse(requestId: requestId, callId: callId, method: method, payloads: ["error": error.localizedDescription])
        }
    }

    private func sendResponse(requestId: String, callId: String, method: String, payloads: [String: Any]) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payloads),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }

        let js = "(function(){var d=\(jsonString);window._enconvoResolve&&window._enconvoResolve('\(requestId)','\(method)',d)})();"
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    // JavaScript injected to provide window.parentPort and window.workerData
    static let parentPortBridgeJS = """
    (function() {
        // Pending request resolvers
        window._enconvoPending = {};
        window._enconvoResolve = function(requestId, method, data) {
            var key = requestId || method;
            if (window._enconvoPending[key]) {
                window._enconvoPending[key](data);
                delete window._enconvoPending[key];
            }
        };

        // parentPort shim — matches what the webapp expects
        window.parentPort = {
            postMessage: function(msg) {
                // Send to Swift via WKScriptMessageHandler
                window.webkit.messageHandlers.enconvoParentPort.postMessage(msg);
            }
        };

        // workerData — provides callId/requestId context
        window.workerData = {
            callId: 'webapp|settings',
            requestId: 'ios-settings'
        };

        // Runtime detection
        window.__ENCONVO_RUNTIME__ = 'ios';
        window.__ENCONVO_BASE_URL__ = 'http://127.0.0.1:18899';

        console.log('[SettingsBridge] parentPort bridge injected');
    })();
    """;
}
