import Foundation
import TanoBridge

#if canImport(LocalAuthentication)
import LocalAuthentication
#endif

/// Native biometrics plugin for Tano.
///
/// Provides Face ID / Touch ID authentication on iOS devices.
/// On macOS (test environment), returns a success stub.
///
/// Supported methods: `authenticate`.
public final class BiometricsPlugin: TanoPlugin {

    // MARK: - TanoPlugin conformance

    public static let name = "biometrics"
    public static let permissions: [String] = ["biometrics"]

    public init() {}

    // MARK: - Routing

    public func handle(method: String, params: [String: Any]) async throws -> Any? {
        switch method {
        case "authenticate":
            return try await authenticate(params: params)
        default:
            throw BiometricsPluginError.unknownMethod(method)
        }
    }

    // MARK: - authenticate

    private func authenticate(params: [String: Any]) async throws -> [String: Any] {
        guard let reason = params["reason"] as? String else {
            throw BiometricsPluginError.missingParameter("reason")
        }

        #if os(iOS)
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            throw BiometricsPluginError.biometricsUnavailable(
                error?.localizedDescription ?? "Biometrics not available on this device"
            )
        }

        let success = try await context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: reason
        )

        return ["success": success]
        #else
        // macOS / test stub — always succeeds
        return ["success": true]
        #endif
    }
}

// MARK: - Errors

public enum BiometricsPluginError: Error, LocalizedError {
    case unknownMethod(String)
    case missingParameter(String)
    case biometricsUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .unknownMethod(let m):
            return "Unknown biometrics plugin method: \(m)"
        case .missingParameter(let p):
            return "Missing required parameter: \(p)"
        case .biometricsUnavailable(let msg):
            return "Biometrics unavailable: \(msg)"
        }
    }
}
