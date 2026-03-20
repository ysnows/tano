#if canImport(UIKit)
import SwiftUI
import WebKit
import TanoCore
import TanoBridge

// MARK: - TanoWebView

/// SwiftUI WebView wrapper that connects a user's web app to the Tano runtime
/// via the injected `window.Tano` bridge.
///
/// Usage:
/// ```swift
/// TanoWebView(
///     config: TanoWebViewConfig(entry: "index.html", devMode: true),
///     pluginRouter: bridgeManager.router
/// ) { event, data in
///     print("Event from WebView: \(event)")
/// }
/// ```
///
/// The WebView:
/// 1. Injects `window.Tano` bridge JS at document start.
/// 2. Registers a `WKScriptMessageHandler` for "tano" messages.
/// 3. Routes `Tano.invoke()` calls through the ``PluginRouter``.
/// 4. Delivers `Tano.send()` events to the ``onEvent`` callback.
public struct TanoWebView: UIViewRepresentable {

    private let config: TanoWebViewConfig
    private let pluginRouter: PluginRouter?
    private let onEvent: ((String, [String: Any]) -> Void)?

    /// Create a new TanoWebView.
    ///
    /// - Parameters:
    ///   - config: WebView configuration (entry URL, dev mode, port, etc.).
    ///   - pluginRouter: The plugin router for handling `Tano.invoke()` calls.
    ///   - onEvent: Callback for `Tano.send()` fire-and-forget events from JS.
    public init(
        config: TanoWebViewConfig = TanoWebViewConfig(),
        pluginRouter: PluginRouter? = nil,
        onEvent: ((String, [String: Any]) -> Void)? = nil
    ) {
        self.config = config
        self.pluginRouter = pluginRouter
        self.onEvent = onEvent
    }

    // MARK: - UIViewRepresentable

    public func makeCoordinator() -> Coordinator {
        Coordinator(config: config, pluginRouter: pluginRouter, onEvent: onEvent)
    }

    public func makeUIView(context: Context) -> WKWebView {
        let wkConfig = WKWebViewConfiguration()

        // Allow localhost connections from file:// pages (for dev mode)
        wkConfig.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        // Set up content controller with bridge JS and message handler
        let contentController = wkConfig.userContentController

        // Inject the Tano bridge JS at document start
        let bridgeScript = WKUserScript(
            source: TanoBridgeJS.script,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        contentController.addUserScript(bridgeScript)

        // Register the "tano" message handler
        let handler = context.coordinator.messageHandler
        contentController.add(handler, name: "tano")

        // Create the WKWebView
        let webView = WKWebView(frame: .zero, configuration: wkConfig)

        // Enable Web Inspector in debug builds (iOS 16.4+)
        #if DEBUG
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        #endif

        // Store reference so we can call evaluateJavaScript on it
        handler.webView = webView

        // Load the entry content
        loadEntry(in: webView)

        return webView
    }

    public func updateUIView(_ uiView: WKWebView, context: Context) {
        // No dynamic updates needed — the WebView manages its own state.
    }

    // MARK: - Entry Loading

    private func loadEntry(in webView: WKWebView) {
        if config.devMode {
            // Dev mode: load from localhost Bun.serve() server
            if let url = config.entryURL() {
                let request = URLRequest(url: url)
                webView.load(request)
                print("[TanoWebView] Loading dev URL: \(url)")
            } else {
                print("[TanoWebView] Failed to construct dev entry URL")
            }
        } else {
            // Production: load from app bundle
            if let url = config.entryURL() {
                webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
                print("[TanoWebView] Loading bundle file: \(url)")
            } else {
                print("[TanoWebView] Failed to find entry file '\(config.entry)' in bundle")
            }
        }
    }

    // MARK: - Coordinator

    /// Coordinator that owns the message handler and manages its lifecycle.
    public class Coordinator {
        let messageHandler: TanoMessageHandler

        init(
            config: TanoWebViewConfig,
            pluginRouter: PluginRouter?,
            onEvent: ((String, [String: Any]) -> Void)?
        ) {
            self.messageHandler = TanoMessageHandler()
            self.messageHandler.pluginRouter = pluginRouter
            self.messageHandler.onEvent = onEvent
        }

        /// Emit an event from native to the WebView's `window.Tano._emit()`.
        ///
        /// - Parameters:
        ///   - event: The event name.
        ///   - data: The event data dictionary.
        public func emitEvent(_ event: String, data: [String: Any] = [:]) {
            messageHandler.emitEventInWebView(event: event, data: data)
        }
    }
}
#endif
