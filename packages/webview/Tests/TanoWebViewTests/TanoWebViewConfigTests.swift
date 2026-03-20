import XCTest
@testable import TanoWebView

final class TanoWebViewConfigTests: XCTestCase {

    // MARK: - Default Values

    func testDefaultEntry() {
        let config = TanoWebViewConfig()
        XCTAssertEqual(config.entry, "index.html")
    }

    func testDefaultDevMode() {
        let config = TanoWebViewConfig()
        XCTAssertFalse(config.devMode)
    }

    func testDefaultServerPort() {
        let config = TanoWebViewConfig()
        XCTAssertEqual(config.serverPort, 18899)
    }

    func testDefaultAllowedOrigins() {
        let config = TanoWebViewConfig()
        XCTAssertEqual(config.allowedOrigins, ["127.0.0.1", "localhost"])
    }

    // MARK: - Custom Values

    func testCustomEntry() {
        let config = TanoWebViewConfig(entry: "app.html")
        XCTAssertEqual(config.entry, "app.html")
    }

    func testCustomDevMode() {
        let config = TanoWebViewConfig(devMode: true)
        XCTAssertTrue(config.devMode)
    }

    func testCustomServerPort() {
        let config = TanoWebViewConfig(serverPort: 3000)
        XCTAssertEqual(config.serverPort, 3000)
    }

    func testCustomAllowedOrigins() {
        let config = TanoWebViewConfig(allowedOrigins: ["example.com"])
        XCTAssertEqual(config.allowedOrigins, ["example.com"])
    }

    func testAllCustomValues() {
        let config = TanoWebViewConfig(
            entry: "main.html",
            devMode: true,
            serverPort: 8080,
            allowedOrigins: ["myhost.local"]
        )
        XCTAssertEqual(config.entry, "main.html")
        XCTAssertTrue(config.devMode)
        XCTAssertEqual(config.serverPort, 8080)
        XCTAssertEqual(config.allowedOrigins, ["myhost.local"])
    }

    // MARK: - Entry URL Construction (Dev Mode)

    func testDevModeEntryURL() {
        let config = TanoWebViewConfig(entry: "index.html", devMode: true, serverPort: 18899)
        let url = config.entryURL()
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.absoluteString, "http://localhost:18899/index.html")
    }

    func testDevModeCustomPort() {
        let config = TanoWebViewConfig(entry: "app.html", devMode: true, serverPort: 3000)
        let url = config.entryURL()
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.absoluteString, "http://localhost:3000/app.html")
    }

    func testDevModeEmptyEntry() {
        let config = TanoWebViewConfig(entry: "", devMode: true, serverPort: 8080)
        let url = config.entryURL()
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.absoluteString, "http://localhost:8080/")
    }

    // MARK: - Entry URL Construction (Production)

    func testProductionEntryURLWithBundlePath() {
        let config = TanoWebViewConfig(entry: "index.html", devMode: false)
        let url = config.entryURL(bundlePath: "/tmp/testbundle")
        XCTAssertNotNil(url)
        XCTAssertTrue(url?.isFileURL ?? false, "Production URL should be a file URL")
        XCTAssertTrue(
            url?.path.contains("index.html") ?? false,
            "Production URL should contain the entry filename"
        )
    }

    func testProductionEntryURLWithoutBundlePath() {
        // Without a bundle path and without an actual bundle file, it should return nil
        let config = TanoWebViewConfig(entry: "nonexistent_file_12345.html", devMode: false)
        let url = config.entryURL()
        // This will be nil since the file doesn't exist in the test bundle
        XCTAssertNil(url)
    }

    // MARK: - Mutability

    func testConfigIsMutable() {
        var config = TanoWebViewConfig()
        config.entry = "changed.html"
        config.devMode = true
        config.serverPort = 9999
        config.allowedOrigins = ["new.origin"]

        XCTAssertEqual(config.entry, "changed.html")
        XCTAssertTrue(config.devMode)
        XCTAssertEqual(config.serverPort, 9999)
        XCTAssertEqual(config.allowedOrigins, ["new.origin"])
    }
}
