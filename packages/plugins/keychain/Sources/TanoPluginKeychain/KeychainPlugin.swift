import Foundation
import TanoBridge

/// Native key-value storage plugin for Tano.
///
/// Provides simple key-value persistence using a dedicated `UserDefaults` suite.
/// A future version may migrate to the real Keychain for secure storage.
///
/// Supported methods: `set`, `get`, `delete`.
public final class KeychainPlugin: TanoPlugin {

    // MARK: - TanoPlugin conformance

    public static let name = "keychain"
    public static let permissions: [String] = ["storage"]

    // MARK: - State

    private let defaults: UserDefaults

    /// Creates a new KeychainPlugin backed by the given UserDefaults suite.
    ///
    /// - Parameter suiteName: The suite name for `UserDefaults`. Defaults to `"dev.tano.keychain"`.
    public init(suiteName: String = "dev.tano.keychain") {
        self.defaults = UserDefaults(suiteName: suiteName) ?? .standard
    }

    // MARK: - Routing

    public func handle(method: String, params: [String: Any]) async throws -> Any? {
        switch method {
        case "set":
            return try setValue(params: params)
        case "get":
            return try getValue(params: params)
        case "delete":
            return try deleteValue(params: params)
        default:
            throw KeychainPluginError.unknownMethod(method)
        }
    }

    // MARK: - set

    private func setValue(params: [String: Any]) throws -> [String: Any] {
        guard let key = params["key"] as? String, !key.isEmpty else {
            throw KeychainPluginError.missingParameter("key")
        }
        guard let value = params["value"] as? String else {
            throw KeychainPluginError.missingParameter("value")
        }

        defaults.set(value, forKey: key)
        return ["success": true]
    }

    // MARK: - get

    private func getValue(params: [String: Any]) throws -> [String: Any] {
        guard let key = params["key"] as? String, !key.isEmpty else {
            throw KeychainPluginError.missingParameter("key")
        }

        if let value = defaults.string(forKey: key) {
            return ["value": value]
        } else {
            return ["value": NSNull()]
        }
    }

    // MARK: - delete

    private func deleteValue(params: [String: Any]) throws -> [String: Any] {
        guard let key = params["key"] as? String, !key.isEmpty else {
            throw KeychainPluginError.missingParameter("key")
        }

        defaults.removeObject(forKey: key)
        return ["success": true]
    }
}

// MARK: - Errors

public enum KeychainPluginError: Error, LocalizedError {
    case unknownMethod(String)
    case missingParameter(String)

    public var errorDescription: String? {
        switch self {
        case .unknownMethod(let m):
            return "Unknown keychain plugin method: \(m)"
        case .missingParameter(let p):
            return "Missing required parameter: \(p)"
        }
    }
}
