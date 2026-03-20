import Foundation

// MARK: - BridgeManager

/// Coordinates the UDS server and plugin routing for the Tano bridge.
///
/// `BridgeManager` is the main entry point for native code that needs to:
/// - Start/stop the UDS bridge server.
/// - Register plugins that handle JS → Native calls.
/// - Send events from Native → JS.
/// - Process incoming messages from the JS runtime.
public class BridgeManager: UDSServerDelegate {

    /// The UDS server instance.
    private var server: UDSServer?

    /// Plugin router for dispatching incoming messages.
    public let router: PluginRouter

    /// The socket path used by this manager.
    public private(set) var socketPath: String = ""

    // MARK: - Init

    public init() {
        self.router = PluginRouter()
    }

    // MARK: - Lifecycle

    /// Start the UDS bridge server at the default socket path.
    public func start() {
        let socketUrl = UDSocket.serviceUrl()
        start(socketUrl: socketUrl)
    }

    /// Start the UDS bridge server at a specific socket URL.
    public func start(socketUrl: NSURL) {
        self.socketPath = socketUrl.path ?? ""
        print("[BridgeManager] Starting UDS server at: \(self.socketPath)")

        self.server = UDSServer(socketUrl: socketUrl)
        self.server?.delegate = self

        do {
            try self.server?.start()
            print("[BridgeManager] UDS server started successfully")
        } catch {
            print("[BridgeManager] Failed to start UDS server: \(error)")
        }
    }

    /// Stop the UDS bridge server and clean up.
    public func stop() {
        self.server?.stop()
        self.server = nil
        self.socketPath = ""
    }

    /// Whether the bridge server is currently running.
    public var isRunning: Bool {
        return server?.isSockConnected() ?? false
    }

    // MARK: - Plugin Management

    /// Register a plugin to handle bridge calls from JS.
    public func register(plugin: TanoPlugin) {
        router.register(plugin: plugin)
    }

    /// Unregister a plugin by name.
    public func unregister(pluginName: String) {
        router.unregister(pluginName: pluginName)
    }

    // MARK: - Native → JS Communication

    /// Send an event to all connected JS clients.
    ///
    /// Events are fire-and-forget messages that don't expect a response.
    public func sendToJS(event: String, data: [String: Any] = [:]) {
        let message = TanoBridgeMessage.event(
            plugin: "",
            method: event,
            params: data
        )
        server?.broadcast(message)
    }

    /// Send a response to a specific client for a given call.
    public func sendResponse(
        callId: String,
        plugin: String,
        method: String,
        params: [String: Any] = [:],
        to client: UDSClient
    ) {
        let message = TanoBridgeMessage.response(
            callId: callId,
            plugin: plugin,
            method: method,
            params: params
        )
        server?.send(message, to: client)
    }

    /// Send an error response to a specific client.
    public func sendError(
        callId: String,
        plugin: String,
        method: String,
        errorMessage: String,
        to client: UDSClient
    ) {
        let message = TanoBridgeMessage.error(
            callId: callId,
            plugin: plugin,
            method: method,
            errorMessage: errorMessage
        )
        server?.send(message, to: client)
    }

    // MARK: - UDSServerDelegate

    public func handleServerStopped(_ server: UDSServer?) {
        print("[BridgeManager] Server stopped")
    }

    public func handleServerMessage(
        _ message: [String: Any]?,
        from client: UDSClient?,
        error: Error?
    ) {
        if let error = error {
            print("[BridgeManager] Received error: \(error)")
            return
        }

        guard let message = message else { return }

        let msgType = message[TanoBridgeMessage.Keys.type] as? String ?? ""
        let callId = message[TanoBridgeMessage.Keys.callId] as? String ?? ""
        let pluginName = message[TanoBridgeMessage.Keys.plugin] as? String ?? ""
        let method = message[TanoBridgeMessage.Keys.method] as? String ?? ""

        switch msgType {
        case TanoBridgeMessage.Types.request:
            // Route to plugin
            router.handle(message: message) { [weak self] result in
                guard let client = client else { return }

                if let result = result {
                    let responseParams: [String: Any]
                    if let dict = result as? [String: Any] {
                        responseParams = dict
                    } else {
                        responseParams = ["result": result]
                    }
                    self?.sendResponse(
                        callId: callId,
                        plugin: pluginName,
                        method: method,
                        params: responseParams,
                        to: client
                    )
                } else {
                    self?.sendError(
                        callId: callId,
                        plugin: pluginName,
                        method: method,
                        errorMessage: "Plugin '\(pluginName)' failed to handle '\(method)'",
                        to: client
                    )
                }
            }

        case TanoBridgeMessage.Types.response,
             TanoBridgeMessage.Types.responseStream,
             TanoBridgeMessage.Types.responseEnd:
            // Responses from JS — could be handled by pending request callbacks.
            // For now, log them.
            print("[BridgeManager] Received \(msgType) for callId: \(callId)")

        case TanoBridgeMessage.Types.event:
            // Events from JS — route through plugin system
            router.handle(message: message) { _ in
                // Events are fire-and-forget
            }

        default:
            print("[BridgeManager] Unknown message type: \(msgType)")
        }
    }

    public func handleConnectionError(_ error: Error?) {
        if let error = error {
            print("[BridgeManager] Connection error: \(error)")
        }
    }
}
