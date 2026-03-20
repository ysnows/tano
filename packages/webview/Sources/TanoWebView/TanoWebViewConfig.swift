import Foundation

// MARK: - TanoWebViewConfig

/// Configuration for the TanoWebView component.
///
/// Controls how the WebView loads its content (dev server vs. production bundle)
/// and which origins are permitted for navigation.
public struct TanoWebViewConfig {

    /// URL or file path the WebView loads initially (e.g. "index.html").
    public var entry: String

    /// Whether to load from localhost dev server (`true`) or bundle file (`false`).
    public var devMode: Bool

    /// Port of the local Bun.serve() server used in dev mode.
    public var serverPort: UInt16

    /// Allowed origin patterns for navigation (e.g. "127.0.0.1", "localhost").
    public var allowedOrigins: [String]

    public init(
        entry: String = "index.html",
        devMode: Bool = false,
        serverPort: UInt16 = 18899,
        allowedOrigins: [String] = ["127.0.0.1", "localhost"]
    ) {
        self.entry = entry
        self.devMode = devMode
        self.serverPort = serverPort
        self.allowedOrigins = allowedOrigins
    }

    // MARK: - URL Construction

    /// Build the entry URL based on the current mode.
    ///
    /// - In dev mode: `http://localhost:{serverPort}/{entry}`
    /// - In production: `file://{bundlePath}/{entry}`
    ///
    /// - Parameter bundlePath: The bundle resource path (used in production mode).
    /// - Returns: The resolved URL, or `nil` if construction fails.
    public func entryURL(bundlePath: String? = nil) -> URL? {
        if devMode {
            let urlString = "http://localhost:\(serverPort)/\(entry)"
            return URL(string: urlString)
        } else {
            // Production: load from app bundle
            if let bundlePath = bundlePath {
                let filePath = (bundlePath as NSString).appendingPathComponent(entry)
                return URL(fileURLWithPath: filePath)
            }
            // Try to find in main bundle
            let name = (entry as NSString).deletingPathExtension
            let ext = (entry as NSString).pathExtension
            if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "web") {
                return url
            }
            return nil
        }
    }
}
