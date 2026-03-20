import Foundation

/// CFSocket callback — fired when a client requests to open a connection.
func SocketServerCallback(
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

protocol UDSServerDelegate: AnyObject {
    func handleSocketServerStopped(_ server: UDSServer?)
    func handleSocketServerMsgDict(
        _ aDict: [String: Any]?,
        from client: UDSClient?,
        error: Error?)
    func handleConnectionError(_ error: Error?)
}

class UDSServer: UDSocket, UDSClientDelegate {
    enum Status {
        case unknown
        case running
        case stopped
        case starting
        case stopping
    }

    var sockStatus: UDSServer.Status = .unknown
    @Published var sockClients = Set<UDSClient>()

    var delegate: UDSServerDelegate?

    func socketServerCreate() throws {
        if self.sockRef != nil {
            throw Self.UDSErr(kind: .socketAlreadyCreated)
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
            SocketServerCallback,
            &context
        )

        guard refSock != nil else {
            throw Self.UDSErr(kind: .systemFailedToCreateSocket)
        }

        var opt = 1
        let socklen = UInt32(MemoryLayout<UInt32>.size)
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &opt, socklen)
        setsockopt(sock, SOL_SOCKET, SO_NOSIGPIPE, &opt, socklen)

        self.sockRef = refSock
    }

    func socketServerBind() throws {
        guard self.sockRef != nil else {
            throw Self.UDSErr(kind: .cannotConnectToNilSocket)
        }

        // Unlink any existing socket file
        var path = [Int8](repeating: 0, count: Int(PATH_MAX))
        if let url = self.sockUrl {
            if url.getFileSystemRepresentation(&path, maxLength: Int(PATH_MAX)) {
                unlink(path)
            }
        }

        guard let sockAddress = self.sockAddress() else {
            throw Self.UDSErr(kind: .cannotConnectToNilAddress)
        }

        let success = CFSocketSetAddress(self.sockRef, sockAddress as CFData?)

        switch success {
        case .timeout:
            throw Self.UDSErr(kind: .setSockAddressTimedOut)
        case .success:
            break
        case .error:
            throw Self.UDSErr(kind: .setAddressUnspecifiedError)
        @unknown default:
            throw Self.UDSErr(kind: .setAddressKnownUnknownError)
        }
    }

    func disconnectClients() {
        self.sockClients.forEach { client in
            self.disconnectClient(client)
        }
    }

    func disconnectClient(_ client: UDSClient?) {
        objc_sync_enter(self)
        if let client = client {
            self.sockClients.remove(client)
        }
        objc_sync_exit(self)
    }

    func addConnectedClient(handle: CFSocketNativeHandle) {
        objc_sync_enter(self)
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
        objc_sync_exit(self)
    }

    func handleSocketClientDisconnect(_ client: UDSClient?) {
        self.disconnectClient(client)
    }

    func handleSocketServerDisconnect(_ client: UDSClient?) {
        // Protocol conformance — may happen if client process terminates
    }

    func handleSocketClientMsgDict(
        _ aDict: [String: Any]?,
        client: UDSClient?,
        error: Error?
    ) {
        delegate?.handleSocketServerMsgDict(aDict, from: client, error: error)
    }

    func start() throws {
        if self.sockStatus == .running { return }
        self.sockStatus = .starting

        do {
            try self.socketServerCreate()
        } catch {
            throw Self.UDSErr(kind: .nested(identifier: "strtSrvr-create", underlying: error))
        }

        do {
            try self.socketServerBind()
        } catch {
            throw Self.UDSErr(kind: .nested(identifier: "strtSrvr-bind", underlying: error))
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

    func stop() {
        self.sockStatus = .stopping
        self.disconnectClients()
        if let sockRef = self.sockRef {
            CFSocketInvalidate(sockRef)
            self.sockRef = nil
        }

        var path = [Int8](repeating: 0, count: Int(PATH_MAX))
        if let url = self.sockUrl {
            if url.getFileSystemRepresentation(&path, maxLength: Int(PATH_MAX)) {
                unlink(path)
            }
        }

        self.delegate?.handleSocketServerStopped(self)
        self.sockStatus = .stopped
    }

    func isSockConnected() -> Bool {
        return (self.sockStatus == .running) && self.isSockRefValid()
    }

    init?(socketUrl: NSURL) {
        super.init()
        self.sockUrl = socketUrl
        self.sockStatus = .stopped
        self.sockClients = Set<UDSClient>()
    }

    deinit {
        self.stop()
    }
}
