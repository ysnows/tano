import Foundation

/// Base class for UDSClient and UDSServer — iOS-adapted (no SwiftyJSON, iOS sandbox paths).
class UDSocket: ObservableObject {
    var sockRefValid = false
    var sockConnected = false
    var sockRef: CFSocket?
    var sockUrl: NSURL?
    var sockRLSourceRef: CFRunLoopSource?
    var bufferSize: Int = 0

    struct UDSErr: Error {
        enum Kind {
            // Both Client and Server
            case systemFailedToCreateSocket
            case cannotConnectToNilSocket
            case cannotAccessAppSupportDir
            case cannotConnectToNilAddress
            case nested(identifier: String, underlying: Error)

            // Client only
            case receivedNonDictionary(typeReceived: String)
            case sendDataTimeout
            case sendDataUnspecifiedError
            case sendDataKnownUnknownError
            case connectToAddressTimeout
            case connectToAddressUnspecifiedError
            case connectToAddressKnownUnknownError
            case socketNotConnected
            case cannotCreateSocketAlreadyExists

            // Server only
            case socketAlreadyCreated
            case setSockAddressTimedOut
            case setAddressTimeout
            case setAddressUnspecifiedError
            case setAddressKnownUnknownError
        }

        let kind: Kind
    }

    func establishBufferSize(sock: Int32) {
        let value_p = UnsafeMutableRawPointer.allocate(
            byteCount: MemoryLayout<Int32>.size,
            alignment: MemoryLayout<Int32>.alignment)
        let sizeVal: Int = 0
        var sizeValSize = UInt32(MemoryLayout.size(ofValue: sizeVal))
        getsockopt(sock, SOL_SOCKET, SO_RCVBUF, value_p, &sizeValSize)
        let socketReceiveBufferSize = Int(value_p.load(as: Int32.self))
        getsockopt(sock, SOL_SOCKET, SO_SNDBUF, value_p, &sizeValSize)
        let socketSendBufferSize = Int(value_p.load(as: Int32.self))

        self.bufferSize = min(socketSendBufferSize, socketReceiveBufferSize)
    }

    func isSockRefValid() -> Bool {
        guard let ref = self.sockRef else { return false }
        return CFSocketIsValid(ref)
    }

    func sockAddress() -> Data? {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)

        let maxLen = MemoryLayout.size(ofValue: address.sun_path) // 104 on iOS
        guard let url = self.sockUrl else { return nil }

        var path = [Int8](repeating: 0, count: maxLen)
        guard url.getFileSystemRepresentation(&path, maxLength: maxLen) else { return nil }

        // Copy path into sun_path tuple using pointer rebinding
        withUnsafeMutablePointer(to: &address.sun_path) { ptr in
            ptr.withMemoryRebound(to: Int8.self, capacity: maxLen) { dst in
                for i in 0..<maxLen {
                    dst[i] = path[i]
                }
            }
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)

        return Data(bytes: &address, count: MemoryLayout.size(ofValue: address))
    }

    func sockLastError() -> String {
        return String(format: "%s (%d)", strerror(errno), errno)
    }

    /// Returns the socket path inside the iOS app's sandbox.
    /// Path: {AppSupport}/Enconvo/.enconvo.socket
    static func serviceUrl() -> NSURL {
        let urls = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask)
        guard let baseUrl = urls.first else {
            return NSURL(fileURLWithPath: "/tmp/.enconvo.socket")
        }

        let enconvoDir = baseUrl.appendingPathComponent("Enconvo")
        if !FileManager.default.fileExists(atPath: enconvoDir.path) {
            try? FileManager.default.createDirectory(
                at: enconvoDir,
                withIntermediateDirectories: true,
                attributes: nil)
        }

        let socketUrl = enconvoDir.appendingPathComponent(".enconvo.socket")

        // Validate path length (sockaddr_un.sun_path is 104 bytes)
        let pathLen = socketUrl.path.utf8CString.count
        if pathLen >= 104 {
            // Fallback to shorter tmp path — include bundle ID for uniqueness
            // (prevents collision between simulator app instances)
            let bundleId = Bundle.main.bundleIdentifier ?? "edgejs"
            let shortId = String(bundleId.suffix(20))
            print("[UDSocket] Socket path too long (\(pathLen) >= 104), using /tmp fallback")
            return NSURL(fileURLWithPath: "/tmp/.enconvo-\(shortId).socket")
        }

        return socketUrl as NSURL
    }
}
