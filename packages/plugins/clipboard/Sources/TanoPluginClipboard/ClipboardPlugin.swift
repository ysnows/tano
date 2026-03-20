import Foundation
import TanoBridge

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Native clipboard plugin for Tano.
///
/// Provides copy/read operations via the ``TanoPlugin`` protocol.
/// Uses `UIPasteboard` on iOS and `NSPasteboard` on macOS.
///
/// Supported methods: `copy`, `read`.
public final class ClipboardPlugin: TanoPlugin {

    // MARK: - TanoPlugin conformance

    public static let name = "clipboard"
    public static let permissions: [String] = []

    public init() {}

    // MARK: - Routing

    public func handle(method: String, params: [String: Any]) async throws -> Any? {
        switch method {
        case "copy":
            return try copyText(params: params)
        case "read":
            return readText()
        default:
            throw ClipboardPluginError.unknownMethod(method)
        }
    }

    // MARK: - copy

    private func copyText(params: [String: Any]) throws -> [String: Any] {
        let text = params["text"] as? String ?? ""
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #endif
        return ["success": true]
    }

    // MARK: - read

    private func readText() -> [String: Any] {
        let text: String?
        #if canImport(UIKit)
        text = UIPasteboard.general.string
        #elseif canImport(AppKit)
        text = NSPasteboard.general.string(forType: .string)
        #else
        text = nil
        #endif

        if let text = text {
            return ["text": text]
        } else {
            return ["text": NSNull()]
        }
    }
}

// MARK: - Errors

public enum ClipboardPluginError: Error, LocalizedError {
    case unknownMethod(String)

    public var errorDescription: String? {
        switch self {
        case .unknownMethod(let m):
            return "Unknown clipboard plugin method: \(m)"
        }
    }
}
