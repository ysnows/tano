import Foundation
import TanoBridge

/// Native HTTP client plugin for Tano.
///
/// Uses URLSession to make HTTP requests directly from the native layer,
/// bypassing WebView CORS restrictions. Works on both iOS and macOS.
///
/// Supported methods: `request`.
public final class HTTPPlugin: TanoPlugin {

    // MARK: - TanoPlugin conformance

    public static let name = "http"
    public static let permissions: [String] = ["network"]

    public init() {}

    // MARK: - Routing

    public func handle(method: String, params: [String: Any]) async throws -> Any? {
        switch method {
        case "request":
            return try await request(params: params)
        default:
            throw HTTPPluginError.unknownMethod(method)
        }
    }

    // MARK: - request

    private func request(params: [String: Any]) async throws -> [String: Any] {
        guard let urlString = params["url"] as? String else {
            throw HTTPPluginError.missingParameter("url")
        }

        guard let url = URL(string: urlString) else {
            throw HTTPPluginError.invalidParameter("url is not a valid URL: \(urlString)")
        }

        let httpMethod = (params["method"] as? String)?.uppercased() ?? "GET"
        let headers = params["headers"] as? [String: String] ?? [:]
        let bodyString = params["body"] as? String

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = httpMethod

        for (key, value) in headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        if let bodyString = bodyString {
            urlRequest.httpBody = Data(bodyString.utf8)
        }

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HTTPPluginError.invalidResponse
        }

        // Convert response headers to [String: String]
        var responseHeaders: [String: String] = [:]
        for (key, value) in httpResponse.allHeaderFields {
            if let k = key as? String, let v = value as? String {
                responseHeaders[k] = v
            }
        }

        let bodyText = String(data: data, encoding: .utf8) ?? data.base64EncodedString()

        return [
            "status": httpResponse.statusCode,
            "headers": responseHeaders,
            "body": bodyText,
        ]
    }
}

// MARK: - Errors

public enum HTTPPluginError: Error, LocalizedError {
    case unknownMethod(String)
    case missingParameter(String)
    case invalidParameter(String)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .unknownMethod(let m):
            return "Unknown HTTP plugin method: \(m)"
        case .missingParameter(let p):
            return "Missing required parameter: \(p)"
        case .invalidParameter(let p):
            return "Invalid parameter: \(p)"
        case .invalidResponse:
            return "Received a non-HTTP response"
        }
    }
}
