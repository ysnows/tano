import XCTest
import Foundation
@testable import TanoCore

/// End-to-end integration tests that spin up a full TanoRuntime with a
/// `Bun.serve()` JS script and make real HTTP requests against it.
final class TanoIntegrationTests: XCTestCase {

    // MARK: - Shared Setup

    private static let testPort: UInt16 = 19876
    private static var runtime: TanoRuntime!
    private static var tempDir: URL!

    override class func setUp() {
        super.setUp()

        // Write the JS server script to a temp file
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tano-integration-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempDir = dir

        let scriptPath = dir.appendingPathComponent("server.js")
        let script = """
        console.log('[Test] Starting...');

        var server = Bun.serve({
            port: \(testPort),
            hostname: '127.0.0.1',
            fetch: function(req) {
                var url = new URL(req.url);
                if (url.pathname === '/health') {
                    return new Response('ok');
                }
                if (url.pathname === '/json') {
                    return Response.json({ runtime: Bun.version, env: Bun.env.TEST_VAR || 'unset' });
                }
                if (url.pathname === '/echo' && req.method === 'POST') {
                    return new Response(req._body, { headers: { 'content-type': 'text/plain' } });
                }
                return new Response('Not Found', { status: 404 });
            }
        });

        console.log('[Test] Server on port ' + server.port);
        """
        try! script.write(to: scriptPath, atomically: true, encoding: .utf8)

        let config = TanoConfig(
            serverEntry: scriptPath.path,
            env: ["TEST_VAR": "hello_tano"]
        )
        runtime = TanoRuntime(config: config)
        runtime.start()

        // Wait for the runtime to reach .running state (up to 3s)
        let deadline = Date().addingTimeInterval(3.0)
        while Date() < deadline {
            if case .running = runtime.state { break }
            Thread.sleep(forTimeInterval: 0.1)
        }

        // Give the HTTP server a moment to fully bind
        Thread.sleep(forTimeInterval: 1.0)
    }

    override class func tearDown() {
        runtime?.stop()

        // Wait for stopped
        let deadline = Date().addingTimeInterval(3.0)
        while Date() < deadline {
            if case .stopped = runtime.state { break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        runtime = nil

        if let dir = tempDir {
            try? FileManager.default.removeItem(at: dir)
        }
        tempDir = nil

        super.tearDown()
    }

    // MARK: - Helpers

    private var baseURL: String {
        "http://127.0.0.1:\(Self.testPort)"
    }

    // MARK: - Tests

    func testHealthEndpoint() async throws {
        let url = URL(string: "\(baseURL)/health")!
        let (data, response) = try await URLSession.shared.data(from: url)
        let httpResponse = response as! HTTPURLResponse

        XCTAssertEqual(httpResponse.statusCode, 200)
        let body = String(data: data, encoding: .utf8)
        XCTAssertEqual(body, "ok")
    }

    func testJsonEndpoint() async throws {
        let url = URL(string: "\(baseURL)/json")!
        let (data, response) = try await URLSession.shared.data(from: url)
        let httpResponse = response as! HTTPURLResponse

        XCTAssertEqual(httpResponse.statusCode, 200)

        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["runtime"] as? String, "1.0.0-tano")
        XCTAssertEqual(json["env"] as? String, "hello_tano")
    }

    func testNotFound() async throws {
        let url = URL(string: "\(baseURL)/nonexistent")!
        let (data, response) = try await URLSession.shared.data(from: url)
        let httpResponse = response as! HTTPURLResponse

        XCTAssertEqual(httpResponse.statusCode, 404)
        let body = String(data: data, encoding: .utf8)
        XCTAssertEqual(body, "Not Found")
    }

    func testPostEcho() async throws {
        let url = URL(string: "\(baseURL)/echo")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data("Hello Tano!".utf8)
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as! HTTPURLResponse

        XCTAssertEqual(httpResponse.statusCode, 200)
        let body = String(data: data, encoding: .utf8)
        XCTAssertEqual(body, "Hello Tano!")
    }
}
