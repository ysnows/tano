import Foundation

// MARK: - PluginRouter

/// Routes incoming bridge messages to registered ``TanoPlugin`` handlers.
///
/// Messages are dispatched based on the `plugin` and `method` fields.
/// If no matching plugin is found, or the plugin does not handle the
/// given method, an error is returned through the respond callback.
public class PluginRouter {

    /// Registered plugins keyed by their name.
    private var plugins: [String: TanoPlugin] = [:]
    private let lock = NSLock()

    public init() {}

    // MARK: - Registration

    /// Register a plugin for handling bridge messages.
    ///
    /// If a plugin with the same name is already registered, it will be replaced.
    public func register(plugin: TanoPlugin) {
        lock.lock()
        defer { lock.unlock() }
        plugins[type(of: plugin).name] = plugin
    }

    /// Unregister a plugin by name.
    public func unregister(pluginName: String) {
        lock.lock()
        defer { lock.unlock() }
        plugins.removeValue(forKey: pluginName)
    }

    // MARK: - Routing

    /// Route an incoming message to the appropriate plugin.
    ///
    /// - Parameters:
    ///   - message: The decoded bridge message dictionary.
    ///   - respond: Callback to send a result (or `nil`) back to the caller.
    ///              On error, the callback receives `nil` and an error response
    ///              should be sent separately.
    ///
    /// The method extracts `plugin`, `method`, and `params` from the message,
    /// looks up the registered plugin, and calls its `handle` method.
    public func handle(
        message: [String: Any],
        respond: @escaping (Any?) -> Void
    ) {
        guard let pluginName = message[TanoBridgeMessage.Keys.plugin] as? String,
              !pluginName.isEmpty else {
            print("[PluginRouter] Message missing 'plugin' field")
            respond(nil)
            return
        }

        guard let method = message[TanoBridgeMessage.Keys.method] as? String,
              !method.isEmpty else {
            print("[PluginRouter] Message missing 'method' field")
            respond(nil)
            return
        }

        lock.lock()
        let plugin = plugins[pluginName]
        lock.unlock()

        guard let plugin = plugin else {
            print("[PluginRouter] No plugin registered for '\(pluginName)'")
            respond(nil)
            return
        }

        let params = message[TanoBridgeMessage.Keys.params] as? [String: Any] ?? [:]

        Task {
            do {
                let result = try await plugin.handle(method: method, params: params)
                respond(result)
            } catch {
                print("[PluginRouter] Plugin '\(pluginName)' method '\(method)' threw: \(error)")
                respond(nil)
            }
        }
    }

    /// Check whether a plugin is registered for the given name.
    public func hasPlugin(named name: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return plugins[name] != nil
    }
}
