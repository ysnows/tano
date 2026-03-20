import Foundation

// MARK: - TanoBridgeMessage

/// Constants for the Tano bridge messaging protocol.
///
/// Messages are JSON dictionaries sent over the UDS bridge. Each message
/// has a `type` that describes its role in the request/response lifecycle,
/// along with routing fields (`plugin`, `method`) and a unique `callId`.
public struct TanoBridgeMessage {

    // MARK: - Keys

    /// Dictionary keys used in bridge messages.
    public enum Keys {
        /// The message type (see ``Types``).
        public static let type = "type"
        /// The method to invoke on the target plugin.
        public static let method = "method"
        /// Unique identifier for matching request/response pairs.
        public static let callId = "callId"
        /// The target plugin name for routing.
        public static let plugin = "plugin"
        /// Arbitrary parameters for the method call.
        public static let params = "params"
    }

    // MARK: - Types

    /// Message type constants.
    public enum Types {
        /// JS → Native method call.
        public static let request = "request"
        /// Native → JS single response.
        public static let response = "response"
        /// Native → JS streaming chunk.
        public static let responseStream = "responseStream"
        /// Native → JS final stream chunk (signals completion).
        public static let responseEnd = "responseEnd"
        /// Native → JS error response.
        public static let error = "error"
        /// Bidirectional event (fire-and-forget).
        public static let event = "event"
    }

    // MARK: - Builders

    /// Build a request message dictionary.
    public static func request(
        callId: String,
        plugin: String,
        method: String,
        params: [String: Any] = [:]
    ) -> [String: Any] {
        return [
            Keys.type: Types.request,
            Keys.callId: callId,
            Keys.plugin: plugin,
            Keys.method: method,
            Keys.params: params,
        ]
    }

    /// Build a response message dictionary.
    public static func response(
        callId: String,
        plugin: String,
        method: String,
        params: [String: Any] = [:]
    ) -> [String: Any] {
        return [
            Keys.type: Types.response,
            Keys.callId: callId,
            Keys.plugin: plugin,
            Keys.method: method,
            Keys.params: params,
        ]
    }

    /// Build a streaming response chunk.
    public static func responseStream(
        callId: String,
        plugin: String,
        method: String,
        params: [String: Any] = [:]
    ) -> [String: Any] {
        return [
            Keys.type: Types.responseStream,
            Keys.callId: callId,
            Keys.plugin: plugin,
            Keys.method: method,
            Keys.params: params,
        ]
    }

    /// Build a stream-end message.
    public static func responseEnd(
        callId: String,
        plugin: String,
        method: String,
        params: [String: Any] = [:]
    ) -> [String: Any] {
        return [
            Keys.type: Types.responseEnd,
            Keys.callId: callId,
            Keys.plugin: plugin,
            Keys.method: method,
            Keys.params: params,
        ]
    }

    /// Build an error message.
    public static func error(
        callId: String,
        plugin: String,
        method: String,
        errorMessage: String
    ) -> [String: Any] {
        return [
            Keys.type: Types.error,
            Keys.callId: callId,
            Keys.plugin: plugin,
            Keys.method: method,
            Keys.params: ["error": errorMessage],
        ]
    }

    /// Build an event message (fire-and-forget).
    public static func event(
        plugin: String,
        method: String,
        params: [String: Any] = [:]
    ) -> [String: Any] {
        return [
            Keys.type: Types.event,
            Keys.callId: "",
            Keys.plugin: plugin,
            Keys.method: method,
            Keys.params: params,
        ]
    }
}
