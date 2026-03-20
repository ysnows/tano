import Foundation

// MARK: - CFSocket Callback (Server)

/// CFSocket callback — fired when a client requests to open a connection.
func TanoSocketServerCallback(
    _ sock: CFSocket?,
    _ type: CFSocketCallBackType,
    _ address: CFData?,
    _ data: UnsafeRawPointer?,
    _ info: UnsafeMutableRawPointer?
) {
    guard let info = info else { return }
    let server = unsafeBitCast(info, to: UDSServer.self)

    if type == .acceptCallBack, let data = data {
        let handle = CFSocketNativeHandle(data.load(as: Int32.self))
        server.addConnectedClient(handle: handle)
    }
}

// MARK: - UDSServerDelegate

/// Delegate protocol for receiving UDS server events.
public protocol UDSServerDelegate: AnyObject {
    /// Called when the server has stopped.
    func handleServerStopped(_ server: UDSServer?)
    /// Called when a message is received from a connected client.
    func handleServerMessage(
        _ message: [String: Any]?,
        from client: UDSClient?,
        error: Error?)
    /// Called when a client connection error occurs.
    func handleConnectionError(_ error: Error?)
}

// MARK: - UDSServer

/// Unix Domain Socket server using CFSocket.
///
/// Listens on a file-system socket path and accepts client connections.
/// Runs its CFRunLoopSource on the main RunLoop (required for iOS —
/// cooperative thread pools do not have a RunLoop).
public class UDSServer: UDSocket, UDSClientDelegate {

    /// Server lifecycle state.
    public enum Status {
        case unknown
        case running
        case stopped
        case starting
        case stopping
    }

    /// Current server status.
    public private(set) var sockStatus: Status = .unknown

    /// Connected clients.
    private var sockClients = Set<UDSClient>()
    private let clientsLock = NSLock()

    /// Delegate for server events.
    public weak var delegate: UDSServerDelegate?

    // MARK: - Init

    public init?(socketUrl: NSURL) {
        super.init()
        self.sockUrl = socketUrl
        self.sockStatus = .stopped
    }

    deinit {
        self.stop()
    }

    // MARK: - Lifecycle

    /// Start listening for connections.
    public func start() throws {
        if self.sockStatus == .running { return }
        self.sockStatus = .starting

        do {
            try self.socketServerCreate()
        } catch {
            throw UDSError(kind: .nested(identifier: "server-create", underlying: error))
        }

        do {
            try self.socketServerBind()
        } catch {
            throw UDSError(kind: .nested(identifier: "server-bind", underlying: error))
        }

        let sourceRef = CFSocketCreateRunLoopSource(
            kCFAllocatorDefault,
            self.sockRef,
            0
        )
        // Must use main RunLoop — .task{} runs on cooperative thread pool which has no RunLoop
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            sourceRef,
            CFRunLoopMode.commonModes
        )
        self.sockRLSourceRef = sourceRef
        self.sockStatus = .running
    }

    /// Stop the server and disconnect all clients.
    public func stop() {
        self.sockStatus = .stopping
        self.disconnectClients()

        if let sockRef = self.sockRef {
            CFSocketInvalidate(sockRef)
            self.sockRef = nil
        }

        // Unlink the socket file
        var path = [Int8](repeating: 0, count: Int(PATH_MAX))
        if let url = self.sockUrl {
            if url.getFileSystemRepresentation(&path, maxLength: Int(PATH_MAX)) {
                unlink(path)
            }
        }

        self.delegate?.handleServerStopped(self)
        self.sockStatus = .stopped
    }

    /// Whether the server is currently running and the socket is valid.
    public func isSockConnected() -> Bool {
        return (self.sockStatus == .running) && self.isSockRefValid()
    }

    /// Send a message dictionary to all connected clients.
    public func broadcast(_ message: [String: Any]) {
        clientsLock.lock()
        let clients = Array(sockClients)
        clientsLock.unlock()

        for client in clients {
            try? client.sendMessageDict(message)
        }
    }

    /// Send a message dictionary to a specific client.
    public func send(_ message: [String: Any], to client: UDSClient) {
        try? client.sendMessageDict(message)
    }

    // MARK: - Client Management

    func addConnectedClient(handle: CFSocketNativeHandle) {
        clientsLock.lock()
        defer { clientsLock.unlock() }

        do {
            if let client = try UDSClient(handle: handle) {
                client.delegate = self
                client.establishBufferSize(sock: handle)

                if client.isSockConnected() {
                    self.sockClients.insert(client)
                }
            }
        } catch {
            self.delegate?.handleConnectionError(error)
        }
    }

    private func disconnectClients() {
        clientsLock.lock()
        let clients = Array(sockClients)
        sockClients.removeAll()
        clientsLock.unlock()

        for client in clients {
            client.stop()
        }
    }

    private func disconnectClient(_ client: UDSClient?) {
        clientsLock.lock()
        if let client = client {
            self.sockClients.remove(client)
        }
        clientsLock.unlock()
    }

    // MARK: - Socket Setup

    private func socketServerCreate() throws {
        if self.sockRef != nil {
            throw UDSError(kind: .socketAlreadyCreated)
        }

        let sock = socket(AF_UNIX, SOCK_STREAM, 0)

        establishBufferSize(sock: sock)

        var context = CFSocketContext(
            version: 0,
            info: unsafeBitCast(self, to: UnsafeMutableRawPointer.self),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let refSock = CFSocketCreateWithNative(
            nil,
            sock,
            UInt(CFSocketCallBackType.acceptCallBack.rawValue),
            TanoSocketServerCallback,
            &context
        )

        guard refSock != nil else {
            throw UDSError(kind: .systemFailedToCreateSocket)
        }

        var opt = 1
        let socklen = UInt32(MemoryLayout<UInt32>.size)
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &opt, socklen)
        setsockopt(sock, SOL_SOCKET, SO_NOSIGPIPE, &opt, socklen)

        self.sockRef = refSock
    }

    private func socketServerBind() throws {
        guard self.sockRef != nil else {
            throw UDSError(kind: .cannotConnectToNilSocket)
        }

        // Unlink any existing socket file
        var path = [Int8](repeating: 0, count: Int(PATH_MAX))
        if let url = self.sockUrl {
            if url.getFileSystemRepresentation(&path, maxLength: Int(PATH_MAX)) {
                unlink(path)
            }
        }

        guard let sockAddress = self.sockAddress() else {
            throw UDSError(kind: .cannotConnectToNilAddress)
        }

        let success = CFSocketSetAddress(self.sockRef, sockAddress as CFData?)

        switch success {
        case .timeout:
            throw UDSError(kind: .setSockAddressTimedOut)
        case .success:
            break
        case .error:
            throw UDSError(kind: .setAddressUnspecifiedError)
        @unknown default:
            throw UDSError(kind: .setAddressKnownUnknownError)
        }
    }

    // MARK: - UDSClientDelegate

    public func handleSocketClientDisconnect(_ client: UDSClient?) {
        self.disconnectClient(client)
    }

    public func handleSocketServerDisconnect(_ client: UDSClient?) {
        // May happen if client process terminates
    }

    public func handleSocketClientMessage(
        _ message: [String: Any]?,
        client: UDSClient?,
        error: Error?
    ) {
        delegate?.handleServerMessage(message, from: client, error: error)
    }
}
