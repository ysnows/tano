import Foundation

// MARK: - UDSocket

/// Base class for ``UDSServer`` and ``UDSClient``.
///
/// Provides shared socket address construction, buffer-size detection,
/// and error types. Adapted for iOS sandbox paths.
public class UDSocket {

    var sockRef: CFSocket?
    var sockUrl: NSURL?
    var sockRLSourceRef: CFRunLoopSource?
    var bufferSize: Int = 0

    // MARK: - Errors

    /// Errors specific to UDS operations.
    public struct UDSError: Error, CustomStringConvertible {
        public enum Kind {
            // Shared
            case systemFailedToCreateSocket
            case cannotConnectToNilSocket
            case cannotConnectToNilAddress
            case nested(identifier: String, underlying: Error)

            // Client
            case receivedNonDictionary(typeReceived: String)
            case sendDataTimeout
            case sendDataUnspecifiedError
            case sendDataKnownUnknownError
            case connectToAddressTimeout
            case connectToAddressUnspecifiedError
            case connectToAddressKnownUnknownError
            case socketNotConnected
            case cannotCreateSocketAlreadyExists

            // Server
            case socketAlreadyCreated
            case setSockAddressTimedOut
            case setAddressUnspecifiedError
            case setAddressKnownUnknownError
        }

        public let kind: Kind

        public var description: String {
            return "UDSError(\(kind))"
        }
    }

    // MARK: - Buffer Size

    /// Query the kernel for the socket's send/receive buffer sizes and
    /// store the smaller value in ``bufferSize``.
    func establishBufferSize(sock: Int32) {
        let valuePtr = UnsafeMutableRawPointer.allocate(
            byteCount: MemoryLayout<Int32>.size,
            alignment: MemoryLayout<Int32>.alignment)
        defer { valuePtr.deallocate() }

        var sizeValSize = UInt32(MemoryLayout<Int32>.size)
        getsockopt(sock, SOL_SOCKET, SO_RCVBUF, valuePtr, &sizeValSize)
        let recvBuf = Int(valuePtr.load(as: Int32.self))
        getsockopt(sock, SOL_SOCKET, SO_SNDBUF, valuePtr, &sizeValSize)
        let sendBuf = Int(valuePtr.load(as: Int32.self))

        self.bufferSize = min(sendBuf, recvBuf)
    }

    // MARK: - Validation

    /// Whether the underlying CFSocket reference is still valid.
    func isSockRefValid() -> Bool {
        guard let ref = self.sockRef else { return false }
        return CFSocketIsValid(ref)
    }

    // MARK: - Address Construction

    /// Build a `sockaddr_un` data blob for the socket URL.
    func sockAddress() -> Data? {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)

        let maxLen = MemoryLayout.size(ofValue: address.sun_path) // 104 on iOS
        guard let url = self.sockUrl else { return nil }

        var path = [Int8](repeating: 0, count: maxLen)
        guard url.getFileSystemRepresentation(&path, maxLength: maxLen) else { return nil }

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

    // MARK: - Socket Path

    /// Returns the default socket URL inside the app's sandbox.
    ///
    /// Path: `{ApplicationSupport}/Tano/.tano.socket`
    ///
    /// If the resulting path exceeds `sockaddr_un.sun_path` (104 bytes),
    /// falls back to a shorter `/tmp` path.
    public static func serviceUrl() -> NSURL {
        let urls = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask)
        guard let baseUrl = urls.first else {
            return NSURL(fileURLWithPath: "/tmp/.tano.socket")
        }

        let tanoDir = baseUrl.appendingPathComponent("Tano")
        if !FileManager.default.fileExists(atPath: tanoDir.path) {
            try? FileManager.default.createDirectory(
                at: tanoDir,
                withIntermediateDirectories: true,
                attributes: nil)
        }

        let socketUrl = tanoDir.appendingPathComponent(".tano.socket")

        // Validate path length (sockaddr_un.sun_path is 104 bytes)
        let pathLen = socketUrl.path.utf8CString.count
        if pathLen >= 104 {
            let bundleId = Bundle.main.bundleIdentifier ?? "tano"
            let shortId = String(bundleId.suffix(20))
            print("[UDSocket] Socket path too long (\(pathLen) >= 104), using /tmp fallback")
            return NSURL(fileURLWithPath: "/tmp/.tano-\(shortId).socket")
        }

        return socketUrl as NSURL
    }
}
