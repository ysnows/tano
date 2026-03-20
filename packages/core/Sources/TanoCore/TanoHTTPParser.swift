import Foundation

/// A parsed HTTP/1.1 request.
struct ParsedHTTPRequest {
    let method: String
    let path: String
    let rawURL: String
    let httpVersion: String
    let headers: [(String, String)]
    let body: Data
}

/// Simple HTTP/1.1 request parser that works on raw `Data`.
enum TanoHTTPParser {

    /// Attempt to parse a complete HTTP request from the given data.
    ///
    /// Returns `nil` if the data does not yet contain a complete request
    /// (e.g. headers are incomplete or the body is shorter than `Content-Length`).
    static func parse(_ data: Data) -> ParsedHTTPRequest? {
        guard let str = String(data: data, encoding: .utf8) else { return nil }

        // Find the end of the header section (\r\n\r\n)
        guard let headerEndRange = str.range(of: "\r\n\r\n") else {
            return nil  // Headers not yet complete
        }

        let headerSection = String(str[str.startIndex..<headerEndRange.lowerBound])
        let bodyStartIndex = headerEndRange.upperBound

        // Split header lines
        let lines = headerSection.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return nil }

        // Parse request line: "GET /path HTTP/1.1"
        let requestLine = lines[0]
        let parts = requestLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2 else { return nil }

        let method = String(parts[0])
        let rawURL = String(parts[1])
        let httpVersion = parts.count >= 3 ? String(parts[2]) : "HTTP/1.1"

        // Extract path (without query string)
        let path: String
        if let qIdx = rawURL.firstIndex(of: "?") {
            path = String(rawURL[rawURL.startIndex..<qIdx])
        } else {
            path = rawURL
        }

        // Parse headers
        var headers: [(String, String)] = []
        var contentLength: Int?

        for i in 1..<lines.count {
            let line = lines[i]
            guard let colonIdx = line.firstIndex(of: ":") else { continue }
            let name = String(line[line.startIndex..<colonIdx]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
            headers.append((name, value))

            if name.lowercased() == "content-length" {
                contentLength = Int(value)
            }
        }

        // Check body completeness
        let bodyString = String(str[bodyStartIndex...])
        let bodyData = Data(bodyString.utf8)

        if let contentLength = contentLength {
            if bodyData.count < contentLength {
                return nil  // Body not yet complete
            }
            // Only take Content-Length bytes
            let trimmedBody = bodyData.prefix(contentLength)
            return ParsedHTTPRequest(
                method: method,
                path: path,
                rawURL: rawURL,
                httpVersion: httpVersion,
                headers: headers,
                body: Data(trimmedBody)
            )
        }

        // No Content-Length — body is everything after headers (or empty for GET)
        return ParsedHTTPRequest(
            method: method,
            path: path,
            rawURL: rawURL,
            httpVersion: httpVersion,
            headers: headers,
            body: bodyData
        )
    }
}
