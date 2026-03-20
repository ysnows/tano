import Foundation

// MARK: - TanoPlugin

/// Protocol for native plugins that handle bridge calls from JavaScript.
///
/// Each plugin has a unique ``name`` used for routing. When JS sends a
/// message with `{ plugin: "myPlugin", method: "doThing", params: {...} }`,
/// the ``PluginRouter`` looks up the plugin by name and calls ``handle(method:params:)``.
///
/// Plugins declare their required ``permissions`` (evaluated in Phase 4).
public protocol TanoPlugin: AnyObject {
    /// Unique plugin identifier used for message routing.
    static var name: String { get }

    /// Permissions this plugin requires (e.g., "clipboard", "network").
    static var permissions: [String] { get }

    /// Handle an incoming method call from JavaScript.
    ///
    /// - Parameters:
    ///   - method: The method name to invoke.
    ///   - params: Arbitrary parameters from the JS caller.
    /// - Returns: An optional result that will be serialized back to JS.
    /// - Throws: Any error, which will be sent back as an error message.
    func handle(method: String, params: [String: Any]) async throws -> Any?
}
