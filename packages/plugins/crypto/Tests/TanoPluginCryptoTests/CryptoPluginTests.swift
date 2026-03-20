import XCTest
@testable import TanoPluginCrypto

final class CryptoPluginTests: XCTestCase {

    private var plugin: CryptoPlugin!

    override func setUp() {
        super.setUp()
        plugin = CryptoPlugin()
    }

    override func tearDown() {
        plugin = nil
        super.tearDown()
    }

    // MARK: - testPluginName

    func testPluginName() {
        XCTAssertEqual(CryptoPlugin.name, "crypto")
        XCTAssertEqual(CryptoPlugin.permissions, [])
    }

    // MARK: - testHashSHA256

    func testHashSHA256() async throws {
        let result = try await plugin.handle(method: "hash", params: [
            "algorithm": "sha256",
            "data": "hello"
        ])
        let dict = try XCTUnwrap(result as? [String: Any])
        let hash = try XCTUnwrap(dict["hash"] as? String)

        // SHA-256 of "hello" is well-known
        XCTAssertEqual(hash, "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
    }

    // MARK: - testHashSHA512

    func testHashSHA512() async throws {
        let result = try await plugin.handle(method: "hash", params: [
            "algorithm": "sha512",
            "data": "hello"
        ])
        let dict = try XCTUnwrap(result as? [String: Any])
        let hash = try XCTUnwrap(dict["hash"] as? String)

        // SHA-512 of "hello"
        XCTAssertEqual(hash, "9b71d224bd62f3785d96d46ad3ea3d73319bfbc2890caadae2dff72519673ca72323c3d99ba5c11d7c7acc6e14b8c5da0c4663475c2e5c3adef46f73bcdec043")
    }

    // MARK: - testHMAC

    func testHMAC() async throws {
        let result = try await plugin.handle(method: "hmac", params: [
            "algorithm": "sha256",
            "key": "secret",
            "data": "hello"
        ])
        let dict = try XCTUnwrap(result as? [String: Any])
        let hmac = try XCTUnwrap(dict["hmac"] as? String)

        // HMAC-SHA256("hello", "secret") — well-known value
        XCTAssertEqual(hmac, "88aab3ede8d3adf94d26ab90d3bafd4a2083070c3bcce9c014ee04a443847c0b")
    }

    // MARK: - testRandomUUID

    func testRandomUUID() async throws {
        let result = try await plugin.handle(method: "randomUUID", params: [:])
        let dict = try XCTUnwrap(result as? [String: Any])
        let uuid = try XCTUnwrap(dict["uuid"] as? String)

        // UUID format: 8-4-4-4-12 hex digits
        let uuidPattern = "^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$"
        let regex = try NSRegularExpression(pattern: uuidPattern, options: [])
        let range = NSRange(uuid.startIndex..., in: uuid)
        XCTAssertNotNil(regex.firstMatch(in: uuid, options: [], range: range),
                        "UUID '\(uuid)' does not match expected pattern")
    }

    // MARK: - testRandomBytes

    func testRandomBytes() async throws {
        let result = try await plugin.handle(method: "randomBytes", params: [
            "length": 32
        ])
        let dict = try XCTUnwrap(result as? [String: Any])
        let base64 = try XCTUnwrap(dict["bytes"] as? String)

        // Decode base64 and verify length
        let data = try XCTUnwrap(Data(base64Encoded: base64))
        XCTAssertEqual(data.count, 32)
    }

    // MARK: - testEncryptDecrypt

    func testEncryptDecrypt() async throws {
        // Generate a 32-byte key
        var keyBytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, 32, &keyBytes)
        let keyBase64 = Data(keyBytes).base64EncodedString()

        let plaintext = "Hello, Tano Crypto!"

        // Encrypt
        let encryptResult = try await plugin.handle(method: "encrypt", params: [
            "key": keyBase64,
            "data": plaintext
        ])
        let encDict = try XCTUnwrap(encryptResult as? [String: Any])
        let ciphertext = try XCTUnwrap(encDict["ciphertext"] as? String)
        let iv = try XCTUnwrap(encDict["iv"] as? String)
        let tag = try XCTUnwrap(encDict["tag"] as? String)

        // Ciphertext should be non-empty and different from plaintext
        XCTAssertFalse(ciphertext.isEmpty)

        // Decrypt
        let decryptResult = try await plugin.handle(method: "decrypt", params: [
            "key": keyBase64,
            "ciphertext": ciphertext,
            "iv": iv,
            "tag": tag
        ])
        let decDict = try XCTUnwrap(decryptResult as? [String: Any])
        let decrypted = try XCTUnwrap(decDict["plaintext"] as? String)

        XCTAssertEqual(decrypted, plaintext)
    }

    // MARK: - testDecryptInvalidKey

    func testDecryptInvalidKey() async throws {
        // Generate a valid key and encrypt
        var keyBytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, 32, &keyBytes)
        let keyBase64 = Data(keyBytes).base64EncodedString()

        let encryptResult = try await plugin.handle(method: "encrypt", params: [
            "key": keyBase64,
            "data": "secret data"
        ])
        let encDict = try XCTUnwrap(encryptResult as? [String: Any])
        let ciphertext = try XCTUnwrap(encDict["ciphertext"] as? String)
        let iv = try XCTUnwrap(encDict["iv"] as? String)
        let tag = try XCTUnwrap(encDict["tag"] as? String)

        // Generate a different key
        var wrongKeyBytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, 32, &wrongKeyBytes)
        let wrongKeyBase64 = Data(wrongKeyBytes).base64EncodedString()

        // Decrypt with wrong key should fail
        do {
            _ = try await plugin.handle(method: "decrypt", params: [
                "key": wrongKeyBase64,
                "ciphertext": ciphertext,
                "iv": iv,
                "tag": tag
            ])
            XCTFail("Decryption with wrong key should have thrown an error")
        } catch {
            // Expected — decryption fails with incorrect key
        }
    }
}
