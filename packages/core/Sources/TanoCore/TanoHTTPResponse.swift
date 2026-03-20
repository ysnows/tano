import Foundation

/// Builds a raw HTTP/1.1 response from components.
struct TanoHTTPResponseBuilder {
    var statusCode: Int = 200
    var statusText: String = "OK"
    var headers: [(String, String)] = []
    var body: Data = Data()

    mutating func setHeader(_ name: String, _ value: String) {
        // Replace existing header with the same name (case-insensitive)
        headers.removeAll { $0.0.lowercased() == name.lowercased() }
        headers.append((name, value))
    }

    /// Build the complete HTTP/1.1 response as raw bytes.
    func build() -> Data {
        var response = "HTTP/1.1 \(statusCode) \(statusText)\r\n"

        // Collect headers, auto-adding Content-Length and Connection
        var finalHeaders = headers
        if !finalHeaders.contains(where: { $0.0.lowercased() == "content-length" }) {
            finalHeaders.append(("Content-Length", "\(body.count)"))
        }
        if !finalHeaders.contains(where: { $0.0.lowercased() == "connection" }) {
            finalHeaders.append(("Connection", "close"))
        }

        for (name, value) in finalHeaders {
            response += "\(name): \(value)\r\n"
        }
        response += "\r\n"

        var data = Data(response.utf8)
        data.append(body)
        return data
    }

    // MARK: - Status text lookup

    static func statusText(for code: Int) -> String {
        switch code {
        case 100: return "Continue"
        case 101: return "Switching Protocols"
        case 200: return "OK"
        case 201: return "Created"
        case 202: return "Accepted"
        case 204: return "No Content"
        case 301: return "Moved Permanently"
        case 302: return "Found"
        case 304: return "Not Modified"
        case 307: return "Temporary Redirect"
        case 308: return "Permanent Redirect"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 408: return "Request Timeout"
        case 409: return "Conflict"
        case 413: return "Payload Too Large"
        case 415: return "Unsupported Media Type"
        case 422: return "Unprocessable Entity"
        case 429: return "Too Many Requests"
        case 500: return "Internal Server Error"
        case 501: return "Not Implemented"
        case 502: return "Bad Gateway"
        case 503: return "Service Unavailable"
        case 504: return "Gateway Timeout"
        default:  return "Unknown"
        }
    }
}
