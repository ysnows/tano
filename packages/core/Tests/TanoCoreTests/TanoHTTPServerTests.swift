import XCTest
import Foundation
@testable import TanoCore

final class TanoHTTPServerTests: XCTestCase {

    // MARK: - Parser Tests

    func testHTTPParserBasic() {
        let raw = "GET /hello HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let data = Data(raw.utf8)
        let parsed = TanoHTTPParser.parse(data)

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.method, "GET")
        XCTAssertEqual(parsed?.path, "/hello")
        XCTAssertEqual(parsed?.rawURL, "/hello")
        XCTAssertEqual(parsed?.httpVersion, "HTTP/1.1")
        XCTAssertEqual(parsed?.headers.count, 1)
        XCTAssertEqual(parsed?.headers.first?.0, "Host")
        XCTAssertEqual(parsed?.headers.first?.1, "localhost")
    }

    func testHTTPParserWithBody() {
        let body = "{\"name\":\"tano\"}"
        let raw = "POST /api HTTP/1.1\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        let data = Data(raw.utf8)
        let parsed = TanoHTTPParser.parse(data)

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.method, "POST")
        XCTAssertEqual(parsed?.path, "/api")
        XCTAssertEqual(String(data: parsed?.body ?? Data(), encoding: .utf8), body)
    }

    func testHTTPParserWithQuery() {
        let raw = "GET /search?q=tano&page=1 HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let data = Data(raw.utf8)
        let parsed = TanoHTTPParser.parse(data)

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.path, "/search")
        XCTAssertEqual(parsed?.rawURL, "/search?q=tano&page=1")
    }

    func testHTTPParserIncomplete() {
        // Missing \r\n\r\n — should return nil
        let raw = "GET /hello HTTP/1.1\r\nHost: localhost\r\n"
        let data = Data(raw.utf8)
        let parsed = TanoHTTPParser.parse(data)
        XCTAssertNil(parsed)
    }

    func testHTTPParserIncompleteBody() {
        // Content-Length says 100 but body is shorter — should return nil
        let raw = "POST /api HTTP/1.1\r\nContent-Length: 100\r\n\r\nshort"
        let data = Data(raw.utf8)
        let parsed = TanoHTTPParser.parse(data)
        XCTAssertNil(parsed)
    }

    // MARK: - Response Builder Tests

    func testHTTPResponseBuilder() {
        var builder = TanoHTTPResponseBuilder()
        builder.statusCode = 200
        builder.statusText = "OK"
        builder.setHeader("Content-Type", "text/plain")
        builder.body = Data("Hello".utf8)

        let data = builder.build()
        let str = String(data: data, encoding: .utf8)!

        XCTAssertTrue(str.hasPrefix("HTTP/1.1 200 OK\r\n"))
        XCTAssertTrue(str.contains("Content-Type: text/plain\r\n"))
        XCTAssertTrue(str.contains("Content-Length: 5\r\n"))
        XCTAssertTrue(str.contains("Connection: close\r\n"))
        XCTAssertTrue(str.hasSuffix("\r\n\r\nHello"))
    }

    func testHTTPResponseBuilderStatusText() {
        XCTAssertEqual(TanoHTTPResponseBuilder.statusText(for: 200), "OK")
        XCTAssertEqual(TanoHTTPResponseBuilder.statusText(for: 404), "Not Found")
        XCTAssertEqual(TanoHTTPResponseBuilder.statusText(for: 500), "Internal Server Error")
    }

    // MARK: - Server Integration Tests

    func testServerStartAndStop() async throws {
        let server = TanoHTTPServer()
        let expectation = XCTestExpectation(description: "Server response received")

        server.fetchHandler = { method, url, headers, body, respond in
            respond(200, [("Content-Type", "text/plain")], "Hello from Tano")
        }

        let readyExpectation = XCTestExpectation(description: "Server ready")
        var serverPort: UInt16 = 0

        try server.start(port: 0, hostname: "127.0.0.1") { port in
            serverPort = port
            readyExpectation.fulfill()
        }

        await fulfillment(of: [readyExpectation], timeout: 5.0)
        XCTAssertGreaterThan(serverPort, 0)

        // Make an HTTP request to the server
        let url = URL(string: "http://127.0.0.1:\(serverPort)/test")!
        let (data, response) = try await URLSession.shared.data(from: url)
        let httpResponse = response as! HTTPURLResponse

        XCTAssertEqual(httpResponse.statusCode, 200)
        let body = String(data: data, encoding: .utf8)
        XCTAssertEqual(body, "Hello from Tano")

        expectation.fulfill()
        await fulfillment(of: [expectation], timeout: 5.0)

        server.stop()
    }

    func testServerJSON() async throws {
        let server = TanoHTTPServer()

        server.fetchHandler = { method, url, headers, body, respond in
            let jsonBody = "{\"status\":\"ok\",\"runtime\":\"tano\"}"
            respond(200, [("Content-Type", "application/json")], jsonBody)
        }

        let readyExpectation = XCTestExpectation(description: "Server ready")
        var serverPort: UInt16 = 0

        try server.start(port: 0, hostname: "127.0.0.1") { port in
            serverPort = port
            readyExpectation.fulfill()
        }

        await fulfillment(of: [readyExpectation], timeout: 5.0)

        let url = URL(string: "http://127.0.0.1:\(serverPort)/api")!
        let (data, response) = try await URLSession.shared.data(from: url)
        let httpResponse = response as! HTTPURLResponse

        XCTAssertEqual(httpResponse.statusCode, 200)

        let json = try JSONSerialization.jsonObject(with: data) as! [String: String]
        XCTAssertEqual(json["status"], "ok")
        XCTAssertEqual(json["runtime"], "tano")

        server.stop()
    }
}
