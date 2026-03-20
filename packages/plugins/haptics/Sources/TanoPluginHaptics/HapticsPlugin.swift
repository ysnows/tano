import Foundation
import TanoBridge

#if canImport(UIKit)
import UIKit
#endif

/// Native haptic feedback plugin for Tano.
///
/// Provides haptic feedback using UIKit feedback generators on iOS.
/// On macOS (and in tests), methods succeed without triggering hardware.
///
/// Supported methods: `impact`, `notification`, `selection`.
public final class HapticsPlugin: TanoPlugin {

    // MARK: - TanoPlugin conformance

    public static let name = "haptics"
    public static let permissions: [String] = []

    public init() {}

    // MARK: - Routing

    public func handle(method: String, params: [String: Any]) async throws -> Any? {
        switch method {
        case "impact":
            return try await impact(params: params)
        case "notification":
            return try await notification(params: params)
        case "selection":
            return try await selection()
        default:
            throw HapticsPluginError.unknownMethod(method)
        }
    }

    // MARK: - impact

    private func impact(params: [String: Any]) async throws -> [String: Any] {
        let style = params["style"] as? String ?? "medium"

        #if canImport(UIKit) && !targetEnvironment(simulator) && !os(macOS)
        let feedbackStyle: UIImpactFeedbackGenerator.FeedbackStyle
        switch style {
        case "light":
            feedbackStyle = .light
        case "medium":
            feedbackStyle = .medium
        case "heavy":
            feedbackStyle = .heavy
        default:
            throw HapticsPluginError.invalidParameter("style", style)
        }
        await MainActor.run {
            let generator = UIImpactFeedbackGenerator(style: feedbackStyle)
            generator.impactOccurred()
        }
        #else
        // Validate style even on macOS / test environments
        guard ["light", "medium", "heavy"].contains(style) else {
            throw HapticsPluginError.invalidParameter("style", style)
        }
        #endif

        return ["success": true]
    }

    // MARK: - notification

    private func notification(params: [String: Any]) async throws -> [String: Any] {
        let type = params["type"] as? String ?? "success"

        #if canImport(UIKit) && !targetEnvironment(simulator) && !os(macOS)
        let feedbackType: UINotificationFeedbackGenerator.FeedbackType
        switch type {
        case "success":
            feedbackType = .success
        case "warning":
            feedbackType = .warning
        case "error":
            feedbackType = .error
        default:
            throw HapticsPluginError.invalidParameter("type", type)
        }
        await MainActor.run {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(feedbackType)
        }
        #else
        guard ["success", "warning", "error"].contains(type) else {
            throw HapticsPluginError.invalidParameter("type", type)
        }
        #endif

        return ["success": true]
    }

    // MARK: - selection

    private func selection() async -> [String: Any] {
        #if canImport(UIKit) && !targetEnvironment(simulator) && !os(macOS)
        await MainActor.run {
            let generator = UISelectionFeedbackGenerator()
            generator.selectionChanged()
        }
        #endif

        return ["success": true]
    }
}

// MARK: - Errors

public enum HapticsPluginError: Error, LocalizedError {
    case unknownMethod(String)
    case invalidParameter(String, String)

    public var errorDescription: String? {
        switch self {
        case .unknownMethod(let m):
            return "Unknown haptics plugin method: \(m)"
        case .invalidParameter(let param, let value):
            return "Invalid value '\(value)' for parameter '\(param)'"
        }
    }
}
