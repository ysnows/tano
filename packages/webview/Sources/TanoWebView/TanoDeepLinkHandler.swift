#if canImport(UIKit)
import UIKit
import WebKit
import TanoCore

// MARK: - TanoDeepLinkHandler

/// Handles deep link URLs by forwarding them to a connected WKWebView
/// via the ``TanoDeepLink`` utility.
///
/// Designed to be called from your `SceneDelegate` or `AppDelegate` when
/// a universal link or custom scheme URL arrives.
///
/// Usage:
/// ```swift
/// let handler = TanoDeepLinkHandler()
/// handler.connect(to: webView)
///
/// // In SceneDelegate:
/// func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
///     if let url = URLContexts.first?.url {
///         handler.handle(url: url)
///     }
/// }
/// ```
public class TanoDeepLinkHandler {

    private weak var webView: WKWebView?

    public init() {}

    /// Connect this handler to a WKWebView so that deep links can be
    /// forwarded to it as JavaScript navigation calls.
    ///
    /// - Parameter webView: The WKWebView to evaluate deep link JS on.
    public func connect(to webView: WKWebView) {
        self.webView = webView
    }

    /// Handle an incoming deep link URL.
    ///
    /// Parses the URL into a path and query parameters, generates the
    /// appropriate JavaScript to push the route, and evaluates it in
    /// the connected WebView.
    ///
    /// - Parameter url: The deep link URL to handle.
    public func handle(url: URL) {
        let (path, params) = TanoDeepLink.parse(url: url)
        let js = TanoDeepLink.navigationJS(path: path, params: params)
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}
#endif
