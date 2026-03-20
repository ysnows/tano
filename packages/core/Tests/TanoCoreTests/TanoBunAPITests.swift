import XCTest
import JavaScriptCore
@testable import TanoCore

final class TanoBunAPITests: XCTestCase {

    private var ctx: JSContext!
    private var bunAPI: TanoBunAPI!
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        ctx = JSContext()!
        ctx.exceptionHandler = { _, exception in
            let msg = exception?.toString() ?? "unknown"
            print("JS exception: \(msg)")
        }

        // Inject prerequisites
        TanoWebAPIs.inject(into: ctx)

        // Need setTimeout for Bun.sleep
        let timers = TanoTimers(jscPerform: { block in block() })
        timers.inject(into: ctx)

        let config = TanoConfig(
            serverEntry: tempDir.appendingPathComponent("entry.js").path,
            env: ["TANO_TEST": "hello"],
            dataPath: tempDir.path
        )
        bunAPI = TanoBunAPI(config: config, jscPerform: { block in block() })
        bunAPI.inject(into: ctx)
    }

    override func tearDown() {
        ctx = nil
        bunAPI = nil
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        super.tearDown()
    }

    // MARK: - Tests

    func testBunExists() {
        let result = ctx.evaluateScript("typeof Bun")
        XCTAssertEqual(result?.toString(), "object")
    }

    func testBunVersion() {
        let result = ctx.evaluateScript("Bun.version")
        XCTAssertEqual(result?.toString(), "1.0.0-tano")
    }

    func testBunEnv() {
        // config.env should be available
        let result = ctx.evaluateScript("Bun.env.TANO_TEST")
        XCTAssertEqual(result?.toString(), "hello")

        // ProcessInfo environment should be merged too
        let pathResult = ctx.evaluateScript("typeof Bun.env.PATH")
        // PATH should exist on macOS
        XCTAssertEqual(pathResult?.toString(), "string")
    }

    func testBunFileNameAndSize() {
        // Write a test file
        let filePath = tempDir.appendingPathComponent("test.txt")
        let content = "Hello, Tano!"
        try! content.write(to: filePath, atomically: true, encoding: .utf8)

        let pathStr = filePath.path
        ctx.evaluateScript("var f = Bun.file('\(pathStr)');")

        let name = ctx.evaluateScript("f.name")
        XCTAssertEqual(name?.toString(), pathStr)

        let size = ctx.evaluateScript("f.size")
        XCTAssertEqual(size?.toInt32(), Int32(content.utf8.count))
    }

    func testBunFileMimeType() {
        ctx.evaluateScript("var fJson = Bun.file('data.json');")
        XCTAssertEqual(ctx.evaluateScript("fJson.type")?.toString(), "application/json")

        ctx.evaluateScript("var fJs = Bun.file('app.js');")
        XCTAssertEqual(ctx.evaluateScript("fJs.type")?.toString(), "application/javascript")

        ctx.evaluateScript("var fHtml = Bun.file('page.html');")
        XCTAssertEqual(ctx.evaluateScript("fHtml.type")?.toString(), "text/html")

        ctx.evaluateScript("var fCss = Bun.file('style.css');")
        XCTAssertEqual(ctx.evaluateScript("fCss.type")?.toString(), "text/css")

        ctx.evaluateScript("var fTxt = Bun.file('readme.txt');")
        XCTAssertEqual(ctx.evaluateScript("fTxt.type")?.toString(), "text/plain")

        ctx.evaluateScript("var fPng = Bun.file('image.png');")
        XCTAssertEqual(ctx.evaluateScript("fPng.type")?.toString(), "image/png")

        ctx.evaluateScript("var fUnknown = Bun.file('data.bin');")
        XCTAssertEqual(ctx.evaluateScript("fUnknown.type")?.toString(), "application/octet-stream")
    }

    func testBunWriteAndRead() {
        let filePath = tempDir.appendingPathComponent("output.txt").path
        let content = "Written by Bun.write"

        // Write via Bun.write
        ctx.evaluateScript("""
            var writeResult = 0;
            var p = Bun.write('\(filePath)', '\(content)');
            p.then(function(n) { writeResult = n; });
        """)

        let bytesWritten = ctx.evaluateScript("writeResult")?.toInt32() ?? 0
        XCTAssertEqual(bytesWritten, Int32(content.utf8.count))

        // Verify via FileManager
        let readBack = try? String(contentsOfFile: filePath, encoding: .utf8)
        XCTAssertEqual(readBack, content)
    }
}
