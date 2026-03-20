import Foundation
import TanoBridge

#if canImport(UIKit)
import UIKit
#endif

/// Native share-sheet plugin for Tano.
///
/// Presents the system share sheet on iOS (UIActivityViewController).
/// On macOS (test environment), returns a success stub.
///
/// Supported methods: `share`.
public final class SharePlugin: TanoPlugin {

    // MARK: - TanoPlugin conformance

    public static let name = "share"
    public static let permissions: [String] = []

    public init() {}

    // MARK: - Routing

    public func handle(method: String, params: [String: Any]) async throws -> Any? {
        switch method {
        case "share":
            return try await share(params: params)
        default:
            throw SharePluginError.unknownMethod(method)
        }
    }

    // MARK: - share

    private func share(params: [String: Any]) async throws -> [String: Any] {
        guard let text = params["text"] as? String else {
            throw SharePluginError.missingParameter("text")
        }

        let urlString = params["url"] as? String

        #if os(iOS)
        await MainActor.run {
            var items: [Any] = [text]
            if let us = urlString, let url = URL(string: us) {
                items.append(url)
            }

            let activityVC = UIActivityViewController(
                activityItems: items,
                applicationActivities: nil
            )

            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootVC = scene.windows.first?.rootViewController else { return }

            var topVC = rootVC
            while let presented = topVC.presentedViewController {
                topVC = presented
            }

            // iPad popover support
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = topVC.view
                popover.sourceRect = CGRect(
                    x: topVC.view.bounds.midX,
                    y: topVC.view.bounds.midY,
                    width: 0, height: 0
                )
            }

            topVC.present(activityVC, animated: true)
        }

        return ["success": true]
        #else
        // macOS / test stub
        _ = text
        _ = urlString
        return ["success": true]
        #endif
    }
}

// MARK: - Errors

public enum SharePluginError: Error, LocalizedError {
    case unknownMethod(String)
    case missingParameter(String)

    public var errorDescription: String? {
        switch self {
        case .unknownMethod(let m):
            return "Unknown share plugin method: \(m)"
        case .missingParameter(let p):
            return "Missing required parameter: \(p)"
        }
    }
}
