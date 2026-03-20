import Foundation

extension Data {
    mutating func append(data: Data, offset: Int, size: Int) {
        let safeSize = Swift.min(data.count - offset, size)
        let start = Int(data.startIndex) + Int(offset)
        let end = Int(start) + Int(safeSize)
        self.append(data[start..<end])
    }
}

/// CFSocket callback — fired when data is received from the server/peer.
func SocketClientCallback(
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

protocol UDSClientDelegate: AnyObject {
    func handleSocketClientDisconnect(_ client: UDSClient?)
    func handleSocketServerDisconnect(_ client: UDSClient?)
    func handleSocketClientMsgDict(_ aDict: [String: Any]?, client: UDSClient?, error: Error?)
}

class UDSClient: UDSocket, Hashable {
    enum Status {
        case unknown
        case linked
        case disconnected
        case linking
        case disconnecting
    }

    var sockStatus: Status?
    private let frameDecoder = FrameDecoder()
    var timeout: CFTimeInterval = 5.0
    var delegate: UDSClientDelegate?
    private let writeLock = NSLock()

    /// Client-side initializer: connect to a server.
    init(socketUrl: NSURL) {
        super.init()
        self.sockUrl = socketUrl
        self.sockStatus = .disconnected
    }

    /// Server-side initializer: wrap an accepted connection handle.
    init?(handle: CFSocketNativeHandle) throws {
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
            throw UDSClient.UDSErr(kind: .nested(identifier: "UDSClient.init(handle:)", underlying: error))
        }
    }

    deinit {
        self.stop()
    }

    func socketClientCreate(sock: CFSocketNativeHandle) throws {
        if self.sockRef != nil {
            throw Self.UDSErr(kind: .cannotCreateSocketAlreadyExists)
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
            SocketClientCallback,
            &context
        )

        guard refSock != nil else {
            throw Self.UDSErr(kind: .systemFailedToCreateSocket)
        }

        var opt = 1
        let socklen = UInt32(MemoryLayout<UInt32>.size)
        setsockopt(sock, SOL_SOCKET, SO_NOSIGPIPE, &opt, socklen)

        self.sockRef = refSock
    }

    func socketClientConnect() throws {
        guard self.sockRef != nil else {
            throw Self.UDSErr(kind: .cannotConnectToNilSocket)
        }
        guard let sockAddressData = self.sockAddress() else {
            throw Self.UDSErr(kind: .cannotConnectToNilAddress)
        }

        let connectError = CFSocketConnectToAddress(
            self.sockRef,
            sockAddressData as CFData,
            self.timeout
        )
        switch connectError {
        case .timeout:
            throw Self.UDSErr(kind: .connectToAddressTimeout)
        case .error:
            throw Self.UDSErr(kind: .connectToAddressUnspecifiedError)
        case .success:
            break
        @unknown default:
            throw Self.UDSErr(kind: .connectToAddressKnownUnknownError)
        }
    }

    func messageReceived(data: Data) {
        guard data.count > 0 else {
            self.delegate?.handleSocketServerDisconnect(self)
            self.stop()
            return
        }

        let frames = frameDecoder.feed(data)
        for frameData in frames {
            do {
                let jsonObject = try JSONSerialization.jsonObject(with: frameData, options: .allowFragments)
                if let dict = jsonObject as? [String: Any] {
                    delegate?.handleSocketClientMsgDict(dict, client: self, error: nil)
                } else {
                    delegate?.handleSocketClientMsgDict(
                        nil, client: self,
                        error: Self.UDSErr(kind: .receivedNonDictionary(typeReceived: "\(type(of: jsonObject))")))
                }
            } catch {
                print("[UDSClient] Frame JSON parse error: \(error)")
                delegate?.handleSocketClientMsgDict(
                    nil, client: self,
                    error: Self.UDSErr(kind: .nested(identifier: #function, underlying: error)))
            }
        }
    }

    func sendMessageData(data: Data) throws {
        writeLock.lock()
        defer { writeLock.unlock() }

        guard self.isSockConnected() else {
            throw Self.UDSErr(kind: .socketNotConnected)
        }

        let payloadLimit = self.bufferSize > 0 ? self.bufferSize : 8192
        var offset = 0
        repeat {
            let payloadBytesInThisChunk = min(payloadLimit, data.count - offset)
            let subData = data.subdata(in: offset..<(offset + payloadBytesInThisChunk))

            let socketErr = CFSocketSendData(self.sockRef, nil, subData as CFData, self.timeout)
            switch socketErr {
            case .timeout:
                throw Self.UDSErr(kind: .sendDataTimeout)
            case .error:
                throw Self.UDSErr(kind: .sendDataUnspecifiedError)
            case .success:
                break
            @unknown default:
                throw Self.UDSErr(kind: .sendDataKnownUnknownError)
            }
            offset += payloadBytesInThisChunk
        } while offset < data.count
    }

    func sendMessageDict(_ dictionary: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: dictionary)
        let framedData = FrameEncoder.encode(data)
        try sendMessageData(data: framedData)
    }

    func start() throws {
        if self.sockStatus == .linked { return }
        self.sockStatus = .linking

        let sock = socket(AF_UNIX, SOCK_STREAM, 0)
        guard sock > 0 else {
            self.stop()
            throw Self.UDSErr(kind: .systemFailedToCreateSocket)
        }

        establishBufferSize(sock: sock)

        do {
            try self.socketClientCreate(sock: sock)
        } catch {
            self.stop()
            throw Self.UDSErr(kind: .nested(identifier: "startCl1", underlying: error))
        }

        do {
            try self.socketClientConnect()
        } catch {
            self.stop()
            throw Self.UDSErr(kind: .nested(identifier: "startCl2", underlying: error))
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

    func stop() {
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

    func isSockConnected() -> Bool {
        return (self.sockStatus == .linked) && self.isSockRefValid()
    }

    // MARK: - Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }

    // MARK: - Equatable
    static func ==(lhs: UDSClient, rhs: UDSClient) -> Bool {
        return lhs === rhs
    }
}
