import Foundation

// MARK: - Data Extension

extension Data {
    mutating func append(data: Data, offset: Int, size: Int) {
        let safeSize = Swift.min(data.count - offset, size)
        let start = Int(data.startIndex) + Int(offset)
        let end = Int(start) + Int(safeSize)
        self.append(data[start..<end])
    }
}

// MARK: - CFSocket Callback (Client)

/// CFSocket callback — fired when data is received from the server/peer.
func TanoSocketClientCallback(
    _ sock: CFSocket?,
    _ type: CFSocketCallBackType,
    _ address: CFData?,
    _ data: UnsafeRawPointer?,
    _ info: UnsafeMutableRawPointer?
) {
    guard let info = info, let data = data else { return }
    let client = unsafeBitCast(info, to: UDSClient.self)

    if type == .dataCallBack {
        let cfData = unsafeBitCast(data, to: CFData.self)
        let nsData = cfData as NSData
        let swiftData = nsData as Data
        client.messageReceived(data: swiftData)
    }
}

// MARK: - UDSClientDelegate

/// Delegate protocol for receiving UDS client events.
public protocol UDSClientDelegate: AnyObject {
    /// Called when the client disconnects.
    func handleSocketClientDisconnect(_ client: UDSClient?)
    /// Called when the remote server disconnects.
    func handleSocketServerDisconnect(_ client: UDSClient?)
    /// Called when a message dictionary is received.
    func handleSocketClientMessage(
        _ message: [String: Any]?,
        client: UDSClient?,
        error: Error?)
}

// MARK: - UDSClient

/// Unix Domain Socket client using CFSocket.
///
/// Can operate in two modes:
/// 1. **Client-side**: Connect to a server via ``start()``.
/// 2. **Server-side**: Wrap an accepted connection handle via ``init(handle:)``.
///
/// Uses ``FrameDecoder`` to reassemble length-prefixed frames from the stream.
public class UDSClient: UDSocket, Hashable {

    /// Client connection state.
    public enum Status {
        case unknown
        case linked
        case disconnected
        case linking
        case disconnecting
    }

    /// Current connection status.
    public private(set) var sockStatus: Status?

    private let frameDecoder = FrameDecoder()
    private let writeLock = NSLock()

    /// Connection timeout in seconds.
    public var timeout: CFTimeInterval = 5.0

    /// Delegate for client events.
    public weak var delegate: UDSClientDelegate?

    // MARK: - Init (Client-Side)

    /// Create a client that will connect to the given server socket.
    public init(socketUrl: NSURL) {
        super.init()
        self.sockUrl = socketUrl
        self.sockStatus = .disconnected
    }

    // MARK: - Init (Server-Side)

    /// Wrap an accepted connection handle from the server.
    public init?(handle: CFSocketNativeHandle) throws {
        super.init()
        self.sockStatus = .linking

        do {
            try socketClientCreate(sock: handle)
            let sourceRef = CFSocketCreateRunLoopSource(
                kCFAllocatorDefault,
                sockRef,
                CFIndex(0))
            CFRunLoopAddSource(
                CFRunLoopGetMain(),
                sourceRef,
                CFRunLoopMode.commonModes
            )
            self.sockRLSourceRef = sourceRef
            sockStatus = .linked
        } catch {
            self.stop()
            throw UDSocket.UDSError(
                kind: .nested(identifier: "UDSClient.init(handle:)", underlying: error))
        }
    }

    deinit {
        self.stop()
    }

    // MARK: - Lifecycle

    /// Connect to the server (client-side mode).
    public func start() throws {
        if self.sockStatus == .linked { return }
        self.sockStatus = .linking

        let sock = socket(AF_UNIX, SOCK_STREAM, 0)
        guard sock > 0 else {
            self.stop()
            throw UDSocket.UDSError(kind: .systemFailedToCreateSocket)
        }

        establishBufferSize(sock: sock)

        do {
            try self.socketClientCreate(sock: sock)
        } catch {
            self.stop()
            throw UDSocket.UDSError(kind: .nested(identifier: "client-create", underlying: error))
        }

        do {
            try self.socketClientConnect()
        } catch {
            self.stop()
            throw UDSocket.UDSError(kind: .nested(identifier: "client-connect", underlying: error))
        }

        let sourceRef = CFSocketCreateRunLoopSource(
            kCFAllocatorDefault,
            self.sockRef,
            0
        )
        // Must use main RunLoop — cooperative thread pool has no RunLoop
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            sourceRef,
            CFRunLoopMode.commonModes
        )
        self.sockRLSourceRef = sourceRef
        self.sockStatus = .linked
    }

    /// Disconnect the client.
    public func stop() {
        self.sockStatus = .disconnecting

        if let sockRef = self.sockRef {
            if let sourceRef = self.sockRLSourceRef {
                CFRunLoopSourceInvalidate(sourceRef)
                self.sockRLSourceRef = nil
            }
            CFSocketInvalidate(sockRef)
            self.sockRef = nil
        }

        self.delegate?.handleSocketClientDisconnect(self)
        self.sockStatus = .disconnected
    }

    /// Whether the client is currently connected.
    public func isSockConnected() -> Bool {
        return (self.sockStatus == .linked) && self.isSockRefValid()
    }

    // MARK: - Sending

    /// Send raw framed data over the socket.
    ///
    /// The data is chunked to stay within the kernel buffer size.
    public func sendMessageData(data: Data) throws {
        writeLock.lock()
        defer { writeLock.unlock() }

        guard self.isSockConnected() else {
            throw UDSocket.UDSError(kind: .socketNotConnected)
        }

        let payloadLimit = self.bufferSize > 0 ? self.bufferSize : 8192
        var offset = 0
        repeat {
            let chunkSize = min(payloadLimit, data.count - offset)
            let subData = data.subdata(in: offset..<(offset + chunkSize))

            let socketErr = CFSocketSendData(self.sockRef, nil, subData as CFData, self.timeout)
            switch socketErr {
            case .timeout:
                throw UDSocket.UDSError(kind: .sendDataTimeout)
            case .error:
                throw UDSocket.UDSError(kind: .sendDataUnspecifiedError)
            case .success:
                break
            @unknown default:
                throw UDSocket.UDSError(kind: .sendDataKnownUnknownError)
            }
            offset += chunkSize
        } while offset < data.count
    }

    /// Serialize a dictionary to JSON and send it as a length-prefixed frame.
    public func sendMessageDict(_ dictionary: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: dictionary)
        let framedData = FrameEncoder.encode(data)
        try sendMessageData(data: framedData)
    }

    // MARK: - Receiving

    func messageReceived(data: Data) {
        guard data.count > 0 else {
            self.delegate?.handleSocketServerDisconnect(self)
            self.stop()
            return
        }

        let frames = frameDecoder.feed(data)
        for frameData in frames {
            do {
                let jsonObject = try JSONSerialization.jsonObject(
                    with: frameData, options: .allowFragments)
                if let dict = jsonObject as? [String: Any] {
                    delegate?.handleSocketClientMessage(dict, client: self, error: nil)
                } else {
                    delegate?.handleSocketClientMessage(
                        nil, client: self,
                        error: UDSocket.UDSError(
                            kind: .receivedNonDictionary(
                                typeReceived: "\(type(of: jsonObject))")))
                }
            } catch {
                print("[UDSClient] Frame JSON parse error: \(error)")
                delegate?.handleSocketClientMessage(
                    nil, client: self,
                    error: UDSocket.UDSError(
                        kind: .nested(identifier: #function, underlying: error)))
            }
        }
    }

    // MARK: - Socket Setup

    private func socketClientCreate(sock: CFSocketNativeHandle) throws {
        if self.sockRef != nil {
            throw UDSocket.UDSError(kind: .cannotCreateSocketAlreadyExists)
        }

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
            UInt(CFSocketCallBackType.dataCallBack.rawValue),
            TanoSocketClientCallback,
            &context
        )

        guard refSock != nil else {
            throw UDSocket.UDSError(kind: .systemFailedToCreateSocket)
        }

        var opt = 1
        let socklen = UInt32(MemoryLayout<UInt32>.size)
        setsockopt(sock, SOL_SOCKET, SO_NOSIGPIPE, &opt, socklen)

        self.sockRef = refSock
    }

    private func socketClientConnect() throws {
        guard self.sockRef != nil else {
            throw UDSocket.UDSError(kind: .cannotConnectToNilSocket)
        }
        guard let sockAddressData = self.sockAddress() else {
            throw UDSocket.UDSError(kind: .cannotConnectToNilAddress)
        }

        let connectError = CFSocketConnectToAddress(
            self.sockRef,
            sockAddressData as CFData,
            self.timeout
        )
        switch connectError {
        case .timeout:
            throw UDSocket.UDSError(kind: .connectToAddressTimeout)
        case .error:
            throw UDSocket.UDSError(kind: .connectToAddressUnspecifiedError)
        case .success:
            break
        @unknown default:
            throw UDSocket.UDSError(kind: .connectToAddressKnownUnknownError)
        }
    }

    // MARK: - Hashable / Equatable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }

    public static func ==(lhs: UDSClient, rhs: UDSClient) -> Bool {
        return lhs === rhs
    }
}
