import Foundation
import TanoBridge

#if canImport(UserNotifications)
import UserNotifications
#endif

/// Native local-notifications plugin for Tano.
///
/// Provides permission requests, scheduling, and cancellation of local
/// notifications via UNUserNotificationCenter on iOS.
/// On macOS (test environment), returns success stubs.
///
/// Supported methods: `requestPermission`, `schedule`, `cancel`.
public final class NotificationsPlugin: TanoPlugin {

    // MARK: - TanoPlugin conformance

    public static let name = "notifications"
    public static let permissions: [String] = ["notifications"]

    public init() {}

    // MARK: - Routing

    public func handle(method: String, params: [String: Any]) async throws -> Any? {
        switch method {
        case "requestPermission":
            return try await requestPermission()
        case "schedule":
            return try await schedule(params: params)
        case "cancel":
            return try await cancel(params: params)
        default:
            throw NotificationsPluginError.unknownMethod(method)
        }
    }

    // MARK: - requestPermission

    private func requestPermission() async throws -> [String: Any] {
        #if os(iOS)
        let center = UNUserNotificationCenter.current()
        let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        return ["granted": granted]
        #else
        // Stub for macOS tests
        return ["granted": true]
        #endif
    }

    // MARK: - schedule

    private func schedule(params: [String: Any]) async throws -> [String: Any] {
        guard let title = params["title"] as? String else {
            throw NotificationsPluginError.missingParameter("title")
        }

        let body = params["body"] as? String ?? ""
        let delay: TimeInterval
        if let d = params["delay"] as? Double {
            delay = d
        } else if let d = params["delay"] as? Int {
            delay = TimeInterval(d)
        } else {
            delay = 1.0
        }

        let identifier = UUID().uuidString

        #if os(iOS)
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(delay, 1),
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )

        try await UNUserNotificationCenter.current().add(request)
        #endif

        return ["id": identifier]
    }

    // MARK: - cancel

    private func cancel(params: [String: Any]) async throws -> [String: Any] {
        guard let identifier = params["id"] as? String else {
            throw NotificationsPluginError.missingParameter("id")
        }

        #if os(iOS)
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [identifier])
        #endif

        return ["success": true]
    }
}

// MARK: - Errors

public enum NotificationsPluginError: Error, LocalizedError {
    case unknownMethod(String)
    case missingParameter(String)

    public var errorDescription: String? {
        switch self {
        case .unknownMethod(let m):
            return "Unknown notifications plugin method: \(m)"
        case .missingParameter(let p):
            return "Missing required parameter: \(p)"
        }
    }
}
