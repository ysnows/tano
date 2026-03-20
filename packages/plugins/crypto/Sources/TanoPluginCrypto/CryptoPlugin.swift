import Foundation
import CryptoKit
import TanoBridge

/// Native cryptography plugin for Tano.
///
/// Provides hashing, HMAC, AES-GCM encryption/decryption, and random data
/// generation via Apple's CryptoKit framework.
///
/// Supported methods: `hash`, `hmac`, `randomUUID`, `randomBytes`, `encrypt`, `decrypt`.
public final class CryptoPlugin: TanoPlugin {

    // MARK: - TanoPlugin conformance

    public static let name = "crypto"
    public static let permissions: [String] = []

    public init() {}

    // MARK: - Routing

    public func handle(method: String, params: [String: Any]) async throws -> Any? {
        switch method {
        case "hash":
            return try hash(params: params)
        case "hmac":
            return try hmac(params: params)
        case "randomUUID":
            return randomUUID()
        case "randomBytes":
            return try randomBytes(params: params)
        case "encrypt":
            return try encrypt(params: params)
        case "decrypt":
            return try decrypt(params: params)
        default:
            throw CryptoPluginError.unknownMethod(method)
        }
    }

    // MARK: - hash

    private func hash(params: [String: Any]) throws -> [String: Any] {
        guard let algorithm = params["algorithm"] as? String else {
            throw CryptoPluginError.missingParameter("algorithm")
        }
        guard let data = params["data"] as? String else {
            throw CryptoPluginError.missingParameter("data")
        }

        let inputData = Data(data.utf8)
        let hexString: String

        switch algorithm.lowercased() {
        case "sha256":
            hexString = SHA256.hash(data: inputData).hexString
        case "sha384":
            hexString = SHA384.hash(data: inputData).hexString
        case "sha512":
            hexString = SHA512.hash(data: inputData).hexString
        default:
            throw CryptoPluginError.unsupportedAlgorithm(algorithm)
        }

        return ["hash": hexString]
    }

    // MARK: - hmac

    private func hmac(params: [String: Any]) throws -> [String: Any] {
        guard let algorithm = params["algorithm"] as? String else {
            throw CryptoPluginError.missingParameter("algorithm")
        }
        guard let keyString = params["key"] as? String else {
            throw CryptoPluginError.missingParameter("key")
        }
        guard let data = params["data"] as? String else {
            throw CryptoPluginError.missingParameter("data")
        }

        let keyData = Data(keyString.utf8)
        let symmetricKey = SymmetricKey(data: keyData)
        let inputData = Data(data.utf8)
        let hexString: String

        switch algorithm.lowercased() {
        case "sha256":
            let mac = HMAC<SHA256>.authenticationCode(for: inputData, using: symmetricKey)
            hexString = Data(mac).hexString
        case "sha384":
            let mac = HMAC<SHA384>.authenticationCode(for: inputData, using: symmetricKey)
            hexString = Data(mac).hexString
        case "sha512":
            let mac = HMAC<SHA512>.authenticationCode(for: inputData, using: symmetricKey)
            hexString = Data(mac).hexString
        default:
            throw CryptoPluginError.unsupportedAlgorithm(algorithm)
        }

        return ["hmac": hexString]
    }

    // MARK: - randomUUID

    private func randomUUID() -> [String: Any] {
        return ["uuid": UUID().uuidString]
    }

    // MARK: - randomBytes

    private func randomBytes(params: [String: Any]) throws -> [String: Any] {
        let length: Int
        if let l = params["length"] as? Int {
            length = l
        } else {
            length = 16
        }

        guard length > 0, length <= 1024 else {
            throw CryptoPluginError.invalidParameter("length must be between 1 and 1024")
        }

        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        guard status == errSecSuccess else {
            throw CryptoPluginError.randomGenerationFailed
        }

        let base64 = Data(bytes).base64EncodedString()
        return ["bytes": base64]
    }

    // MARK: - encrypt (AES-GCM)

    private func encrypt(params: [String: Any]) throws -> [String: Any] {
        guard let keyBase64 = params["key"] as? String,
              let keyData = Data(base64Encoded: keyBase64) else {
            throw CryptoPluginError.missingParameter("key (base64-encoded 32 bytes)")
        }
        guard keyData.count == 32 else {
            throw CryptoPluginError.invalidParameter("key must be 32 bytes (256-bit) base64-encoded")
        }

        guard let plaintext = params["data"] as? String else {
            throw CryptoPluginError.missingParameter("data")
        }

        let symmetricKey = SymmetricKey(data: keyData)
        let plaintextData = Data(plaintext.utf8)

        let nonce: AES.GCM.Nonce
        if let ivBase64 = params["iv"] as? String,
           let ivData = Data(base64Encoded: ivBase64) {
            nonce = try AES.GCM.Nonce(data: ivData)
        } else {
            nonce = AES.GCM.Nonce()
        }

        let sealedBox = try AES.GCM.seal(plaintextData, using: symmetricKey, nonce: nonce)

        return [
            "ciphertext": sealedBox.ciphertext.base64EncodedString(),
            "iv": Data(sealedBox.nonce).base64EncodedString(),
            "tag": sealedBox.tag.base64EncodedString(),
        ]
    }

    // MARK: - decrypt (AES-GCM)

    private func decrypt(params: [String: Any]) throws -> [String: Any] {
        guard let keyBase64 = params["key"] as? String,
              let keyData = Data(base64Encoded: keyBase64) else {
            throw CryptoPluginError.missingParameter("key (base64-encoded)")
        }

        guard let ciphertextBase64 = params["ciphertext"] as? String,
              let ciphertextData = Data(base64Encoded: ciphertextBase64) else {
            throw CryptoPluginError.missingParameter("ciphertext (base64-encoded)")
        }

        guard let ivBase64 = params["iv"] as? String,
              let ivData = Data(base64Encoded: ivBase64) else {
            throw CryptoPluginError.missingParameter("iv (base64-encoded)")
        }

        guard let tagBase64 = params["tag"] as? String,
              let tagData = Data(base64Encoded: tagBase64) else {
            throw CryptoPluginError.missingParameter("tag (base64-encoded)")
        }

        let symmetricKey = SymmetricKey(data: keyData)
        let nonce = try AES.GCM.Nonce(data: ivData)
        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertextData, tag: tagData)
        let decryptedData = try AES.GCM.open(sealedBox, using: symmetricKey)

        guard let plaintext = String(data: decryptedData, encoding: .utf8) else {
            throw CryptoPluginError.decryptionFailed("Could not decode plaintext as UTF-8")
        }

        return ["plaintext": plaintext]
    }
}

// MARK: - Hex String Extension

private extension Sequence where Element == UInt8 {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

private extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Errors

public enum CryptoPluginError: Error, LocalizedError {
    case unknownMethod(String)
    case missingParameter(String)
    case invalidParameter(String)
    case unsupportedAlgorithm(String)
    case randomGenerationFailed
    case decryptionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unknownMethod(let m):
            return "Unknown crypto plugin method: \(m)"
        case .missingParameter(let p):
            return "Missing required parameter: \(p)"
        case .invalidParameter(let p):
            return "Invalid parameter: \(p)"
        case .unsupportedAlgorithm(let a):
            return "Unsupported algorithm: \(a). Use sha256, sha384, or sha512."
        case .randomGenerationFailed:
            return "Failed to generate random bytes"
        case .decryptionFailed(let msg):
            return "Decryption failed: \(msg)"
        }
    }
}
