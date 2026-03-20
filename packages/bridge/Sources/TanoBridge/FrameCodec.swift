import Foundation

// MARK: - FrameEncoder

/// Encode a payload into a length-prefixed frame.
///
/// Wire format: `[4-byte big-endian UInt32 length][payload bytes]`
public struct FrameEncoder {

    /// Encode a raw `Data` payload into a framed message.
    public static func encode(_ payload: Data) -> Data {
        var length = UInt32(payload.count).bigEndian
        var frame = Data(bytes: &length, count: 4)
        frame.append(payload)
        return frame
    }

    /// Encode a UTF-8 string payload into a framed message.
    public static func encode(_ string: String) -> Data {
        encode(string.data(using: .utf8) ?? Data())
    }
}

// MARK: - FrameDecoder

/// Maximum valid payload size — anything larger is treated as a protocol error.
private let maxPayload: UInt32 = 64 * 1024 * 1024 // 64 MB

/// Streaming length-prefixed frame decoder.
///
/// Feed raw socket data via ``feed(_:)``; the decoder reassembles
/// complete frames and returns them. Partial frames are buffered
/// internally until enough data arrives.
public class FrameDecoder {

    private var buffer = Data()

    public init() {}

    /// Feed a new data chunk into the decoder.
    ///
    /// - Parameter data: Raw bytes received from the socket.
    /// - Returns: Zero or more fully-reassembled payload `Data` values.
    public func feed(_ data: Data) -> [Data] {
        buffer.append(data)

        var frames: [Data] = []

        while buffer.count >= 4 {
            let payloadLength = buffer.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }

            if payloadLength > maxPayload {
                print("[FrameDecoder] Unreasonable payload length: \(payloadLength) bytes. Resetting buffer.")
                buffer = Data()
                break
            }

            let totalLength = 4 + Int(payloadLength)
            guard buffer.count >= totalLength else { break }

            frames.append(buffer.subdata(in: 4..<totalLength))
            buffer = buffer.subdata(in: totalLength..<buffer.count)
        }

        return frames
    }

    /// Reset the internal reassembly buffer.
    public func reset() {
        buffer = Data()
    }
}
