import XCTest
@testable import TanoCore

final class TanoOTAUpdateTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        super.tearDown()
    }

    // MARK: - Config Defaults

    func testConfigDefaults() {
        let config = TanoOTAUpdate.Config(updateURL: "https://example.com/manifest")

        XCTAssertEqual(config.updateURL, "https://example.com/manifest")
        XCTAssertEqual(config.currentHash, "")
        XCTAssertEqual(config.channel, "production")
        XCTAssertTrue(config.autoCheck)
        // Default updateDir should be in the caches directory
        XCTAssertTrue(config.updateDir.contains("tano-updates"), "updateDir should contain 'tano-updates', got: \(config.updateDir)")
        XCTAssertTrue(config.updateDir.contains("Caches"), "updateDir should be under Caches, got: \(config.updateDir)")
    }

    func testConfigCustomValues() {
        let customDir = tempDir.appendingPathComponent("custom-updates").path
        let config = TanoOTAUpdate.Config(
            updateURL: "https://ota.example.com/check",
            currentHash: "abc123",
            channel: "staging",
            updateDir: customDir,
            autoCheck: false
        )

        XCTAssertEqual(config.updateURL, "https://ota.example.com/check")
        XCTAssertEqual(config.currentHash, "abc123")
        XCTAssertEqual(config.channel, "staging")
        XCTAssertEqual(config.updateDir, customDir)
        XCTAssertFalse(config.autoCheck)
    }

    // MARK: - Pending Update

    func testPendingUpdateWhenNone() {
        let config = TanoOTAUpdate.Config(
            updateURL: "https://example.com/manifest",
            updateDir: tempDir.path
        )
        let ota = TanoOTAUpdate(config: config)

        let result = ota.pendingUpdate()
        XCTAssertNil(result, "Should return nil when no pending update exists")
    }

    func testPendingUpdateWhenPendingFileExistsButNoServerJS() {
        let config = TanoOTAUpdate.Config(
            updateURL: "https://example.com/manifest",
            updateDir: tempDir.path
        )
        let ota = TanoOTAUpdate(config: config)

        // Write a pending file but don't create the update directory with server.js
        let pendingPath = tempDir.appendingPathComponent("pending")
        try! "fakehash123".write(to: pendingPath, atomically: true, encoding: .utf8)

        let result = ota.pendingUpdate()
        XCTAssertNil(result, "Should return nil when server.js doesn't exist for the pending hash")
    }

    func testPendingUpdateWhenValid() {
        let config = TanoOTAUpdate.Config(
            updateURL: "https://example.com/manifest",
            updateDir: tempDir.path
        )
        let ota = TanoOTAUpdate(config: config)

        let hash = "abc123def456"

        // Create the update directory with a server.js
        let updateDir = tempDir.appendingPathComponent(hash)
        try! FileManager.default.createDirectory(at: updateDir, withIntermediateDirectories: true)
        let serverJSPath = updateDir.appendingPathComponent("server.js")
        try! "console.log('updated');".write(to: serverJSPath, atomically: true, encoding: .utf8)

        // Write the pending file
        let pendingPath = tempDir.appendingPathComponent("pending")
        try! hash.write(to: pendingPath, atomically: true, encoding: .utf8)

        let result = ota.pendingUpdate()
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.serverEntry, serverJSPath.path)
        XCTAssertEqual(result?.webDir, updateDir.appendingPathComponent("web").path)
    }

    // MARK: - Manifest Decoding

    func testManifestDecoding() {
        let json = """
        {
            "version": "1.2.0",
            "hash": "sha256abcdef1234567890",
            "channel": "production",
            "serverBundle": {
                "url": "https://ota.example.com/bundles/production/server.js",
                "hash": "serverhash123",
                "size": 45678
            },
            "webBundle": {
                "url": "https://ota.example.com/bundles/production/web.zip",
                "hash": "webhash456",
                "size": 123456
            },
            "createdAt": "2026-03-21T10:00:00Z"
        }
        """.data(using: .utf8)!

        let manifest = try! JSONDecoder().decode(TanoOTAUpdate.Manifest.self, from: json)

        XCTAssertEqual(manifest.version, "1.2.0")
        XCTAssertEqual(manifest.hash, "sha256abcdef1234567890")
        XCTAssertEqual(manifest.channel, "production")
        XCTAssertEqual(manifest.createdAt, "2026-03-21T10:00:00Z")

        XCTAssertNotNil(manifest.serverBundle)
        XCTAssertEqual(manifest.serverBundle?.url, "https://ota.example.com/bundles/production/server.js")
        XCTAssertEqual(manifest.serverBundle?.hash, "serverhash123")
        XCTAssertEqual(manifest.serverBundle?.size, 45678)

        XCTAssertNotNil(manifest.webBundle)
        XCTAssertEqual(manifest.webBundle?.url, "https://ota.example.com/bundles/production/web.zip")
        XCTAssertEqual(manifest.webBundle?.hash, "webhash456")
        XCTAssertEqual(manifest.webBundle?.size, 123456)
    }

    func testManifestDecodingWithoutOptionalBundles() {
        let json = """
        {
            "version": "1.0.0",
            "hash": "minimalhash",
            "channel": "canary",
            "createdAt": "2026-03-21T12:00:00Z"
        }
        """.data(using: .utf8)!

        let manifest = try! JSONDecoder().decode(TanoOTAUpdate.Manifest.self, from: json)

        XCTAssertEqual(manifest.version, "1.0.0")
        XCTAssertEqual(manifest.hash, "minimalhash")
        XCTAssertEqual(manifest.channel, "canary")
        XCTAssertNil(manifest.serverBundle)
        XCTAssertNil(manifest.webBundle)
    }

    // MARK: - Cleanup

    func testCleanup() {
        let config = TanoOTAUpdate.Config(
            updateURL: "https://example.com/manifest",
            updateDir: tempDir.path
        )
        let ota = TanoOTAUpdate(config: config)

        let currentHash = "current_v2"
        let oldHash1 = "old_v1"
        let oldHash2 = "old_v0"

        // Create fake update directories
        for hash in [currentHash, oldHash1, oldHash2] {
            let dir = tempDir.appendingPathComponent(hash)
            try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let serverJS = dir.appendingPathComponent("server.js")
            try! "// version".write(to: serverJS, atomically: true, encoding: .utf8)
        }

        // Mark current as applied
        let appliedPath = tempDir.appendingPathComponent("applied")
        try! currentHash.write(to: appliedPath, atomically: true, encoding: .utf8)

        // Run cleanup
        ota.cleanup()

        // The current hash directory and the "applied" file should remain
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent(currentHash).path),
                      "Current update directory should be kept")
        XCTAssertTrue(FileManager.default.fileExists(atPath: appliedPath.path),
                      "Applied marker file should be kept")

        // Old directories should be removed
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent(oldHash1).path),
                       "Old update directory should be removed")
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent(oldHash2).path),
                       "Old update directory should be removed")
    }

    // MARK: - Rollback

    func testRollback() {
        let config = TanoOTAUpdate.Config(
            updateURL: "https://example.com/manifest",
            updateDir: tempDir.path
        )
        let ota = TanoOTAUpdate(config: config)

        let hash = "pending_update_hash"

        // Create fake pending update
        let updateDir = tempDir.appendingPathComponent(hash)
        try! FileManager.default.createDirectory(at: updateDir, withIntermediateDirectories: true)
        let serverJS = updateDir.appendingPathComponent("server.js")
        try! "// new version".write(to: serverJS, atomically: true, encoding: .utf8)

        let pendingPath = tempDir.appendingPathComponent("pending")
        try! hash.write(to: pendingPath, atomically: true, encoding: .utf8)

        // Verify pending exists before rollback
        XCTAssertTrue(FileManager.default.fileExists(atPath: pendingPath.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: updateDir.path))

        // Rollback
        ota.rollback()

        // Both the pending marker and the update directory should be gone
        XCTAssertFalse(FileManager.default.fileExists(atPath: pendingPath.path),
                       "Pending file should be removed after rollback")
        XCTAssertFalse(FileManager.default.fileExists(atPath: updateDir.path),
                       "Update directory should be removed after rollback")
    }

    func testRollbackWhenNoPending() {
        let config = TanoOTAUpdate.Config(
            updateURL: "https://example.com/manifest",
            updateDir: tempDir.path
        )
        let ota = TanoOTAUpdate(config: config)

        // Should not crash when there's nothing to rollback
        ota.rollback()
    }

    // MARK: - Mark Applied

    func testMarkApplied() {
        let config = TanoOTAUpdate.Config(
            updateURL: "https://example.com/manifest",
            updateDir: tempDir.path
        )
        let ota = TanoOTAUpdate(config: config)

        let hash = "applied_hash_123"
        let pendingPath = tempDir.appendingPathComponent("pending")
        try! hash.write(to: pendingPath, atomically: true, encoding: .utf8)

        ota.markApplied()

        // Pending should be removed
        XCTAssertFalse(FileManager.default.fileExists(atPath: pendingPath.path),
                       "Pending file should be removed after marking applied")

        // Applied file should contain the hash
        let appliedPath = tempDir.appendingPathComponent("applied")
        let appliedHash = try! String(contentsOf: appliedPath, encoding: .utf8)
        XCTAssertEqual(appliedHash, hash)
    }

    // MARK: - SHA256

    func testSha256Consistency() {
        let config = TanoOTAUpdate.Config(
            updateURL: "https://example.com/manifest",
            updateDir: tempDir.path
        )
        let ota = TanoOTAUpdate(config: config)

        let data = "Hello, Tano OTA!".data(using: .utf8)!
        let hash1 = ota.sha256(data: data)
        let hash2 = ota.sha256(data: data)

        // Same data should produce the same hash
        XCTAssertEqual(hash1, hash2)
        XCTAssertFalse(hash1.isEmpty)

        // Different data should produce a different hash
        let otherData = "Different content".data(using: .utf8)!
        let hash3 = ota.sha256(data: otherData)
        XCTAssertNotEqual(hash1, hash3)
    }
}
