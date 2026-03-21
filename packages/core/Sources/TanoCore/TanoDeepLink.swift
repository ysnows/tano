import Foundation

// MARK: - TanoDeepLink

/// Utilities for parsing deep link URLs and generating JavaScript to navigate
/// the WebView's client-side router.
///
/// Supports both universal links (`https://example.com/settings?tab=privacy`)
/// and custom scheme links (`myapp://user?id=123`).
///
/// The generated JavaScript uses the History API (`pushState` + `popstate` event)
/// which works with most SPA routers (react-router, vue-router, etc.) and also
/// emits a `deepLink` event via `window.Tano._emit()` for custom handling.
///
/// Usage:
/// ```swift
/// let (path, params) = TanoDeepLink.parse(url: incomingURL)
/// let js = TanoDeepLink.navigationJS(path: path, params: params)
/// webView.evaluateJavaScript(js)
/// ```
public enum TanoDeepLink {

    /// Parse a deep link URL and return the path plus query parameters.
    ///
    /// - Parameter url: The incoming deep link URL.
    /// - Returns: A tuple of (path, params) where path defaults to "/" if empty,
    ///   and params is a dictionary of query string key-value pairs.
    public static func parse(url: URL) -> (path: String, params: [String: String]) {
        let path = url.path.isEmpty ? "/" : url.path
        var params: [String: String] = [:]
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let queryItems = components.queryItems {
            for item in queryItems {
                params[item.name] = item.value ?? ""
            }
        }
        return (path, params)
    }

    /// Generate JavaScript to navigate the WebView's router to the given path.
    ///
    /// The generated code:
    /// 1. Pushes the path onto the browser history via `history.pushState`.
    /// 2. Dispatches a `popstate` event so SPA routers pick up the change.
    /// 3. Emits a `deepLink` event via `Tano._emit()` for custom handling.
    ///
    /// - Parameters:
    ///   - path: The URL path to navigate to (e.g. "/settings").
    ///   - params: Query parameters to append (e.g. ["tab": "privacy"]).
    /// - Returns: A self-contained JavaScript string safe for `evaluateJavaScript`.
    public static func navigationJS(path: String, params: [String: String]) -> String {
        let query = params.map { "\(escapeJS($0.key))=\(escapeJS($0.value))" }
            .joined(separator: "&")
        let fullPath = query.isEmpty ? escapeJS(path) : "\(escapeJS(path))?\(query)"
        let jsonParams = paramsJSON(params)

        return """
        (function() {
            var path = '\(fullPath)';
            if (window.history && window.history.pushState) {
                window.history.pushState({}, '', path);
                window.dispatchEvent(new PopStateEvent('popstate'));
            }
            if (window.Tano && window.Tano._emit) {
                window.Tano._emit('deepLink', { path: '\(escapeJS(path))', params: \(jsonParams) });
            }
        })();
        """
    }

    // MARK: - Internal Helpers

    /// Serialize a dictionary to a simple JSON object string.
    static func paramsJSON(_ params: [String: String]) -> String {
        if params.isEmpty { return "{}" }
        let pairs = params
            .sorted(by: { $0.key < $1.key })
            .map { "\"\(escapeJS($0.key))\": \"\(escapeJS($0.value))\"" }
        return "{ \(pairs.joined(separator: ", ")) }"
    }

    /// Escape a string for safe embedding inside a JavaScript single-quoted
    /// string literal or JSON double-quoted string.
    private static func escapeJS(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }
}
