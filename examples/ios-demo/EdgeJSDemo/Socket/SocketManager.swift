import Foundation

class SocketManager {
    static let shared = SocketManager()
    var server: UDSServer?
    var producer: Producer?

    private var delegates: [String: OnTaskMessageDelegate] = [:]
    private let delegatesQueue = DispatchQueue(
        label: "com.enconvo.ios.socket_manager.delegates.queue", attributes: .concurrent)

    /// The socket path used by this manager
    private(set) var socketPath: String = ""

    func addDelegate(delegate: @escaping OnTaskMessageDelegate) -> String {
        let key = UUID().uuidString
        delegatesQueue.async(flags: .barrier) {
            self.delegates[key] = delegate
        }
        return key
    }

    func getDelegates() -> [OnTaskMessageDelegate] {
        var result: [OnTaskMessageDelegate] = []
        delegatesQueue.sync {
            result = self.delegates.values.map { $0 }
        }
        return result
    }

    func getDelegate(for key: String) -> OnTaskMessageDelegate? {
        var delegate: OnTaskMessageDelegate?
        delegatesQueue.sync {
            delegate = self.delegates[key]
        }
        return delegate
    }

    func removeDelegate(_ key: String?) {
        guard let key = key else { return }
        delegatesQueue.async(flags: .barrier) {
            self.delegates.removeValue(forKey: key)
        }
    }

    /// Start the UDS server at the default socket path.
    func start() {
        let socketUrl = UDSocket.serviceUrl()
        self.socketPath = socketUrl.path ?? ""
        print("[SocketManager] Starting UDS server at: \(self.socketPath)")

        self.server = UDSServer(socketUrl: socketUrl)
        do {
            try self.server?.start()
            print("[SocketManager] UDS server started successfully")
        } catch {
            print("[SocketManager] Failed to start UDS server: \(error)")
        }

        if let server = self.server {
            self.producer = Producer()
            server.delegate = producer
        }
    }

    /// Stop the UDS server and clean up.
    func stop() {
        self.server?.stop()
        self.server = nil
        self.producer = nil
    }
}
