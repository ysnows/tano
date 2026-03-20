import Foundation

/// Encode a payload into a length-prefixed frame.
///
/// Wire format: [4-byte big-endian UInt32 length][payload bytes]
struct FrameEncoder {
    /// Encode a raw `Data` payload.
    static func encode(_ payload: Data) -> Data {
        var length = UInt32(payload.count).bigEndian
        var header = Data(bytes: &length, count: 4)
        header.append(payload)
        return header
    }

    /// Encode a UTF-8 string payload.
    static func encode(_ string: String) -> Data {
        encode(string.data(using: .utf8) ?? Data())
    }
}

/// Maximum valid payload — anything larger is treated as protocol mismatch.
private let maxPayload: UInt32 = 64 * 1024 * 1024 // 64 MB

/// Streaming frame decoder with automatic legacy protocol detection.
///
/// On the first chunk, if the leading byte is '{' (0x7B), the decoder switches
/// to newline-delimited mode for the rest of the connection. Otherwise it uses
/// length-prefixed framing.
class FrameDecoder {
    private enum Mode {
        case detect
        case frame
        case legacy
    }

    private var buffer = Data()
    private var mode: Mode = .detect

    /// Feed a new data chunk into the decoder.
    ///
    /// - Parameter data: Raw bytes received from the socket.
    /// - Returns: Zero or more fully-reassembled payload `Data` values.
    func feed(_ data: Data) -> [Data] {
        buffer.append(data)

        // Auto-detect on first meaningful data
        if mode == .detect && !buffer.isEmpty {
            if buffer[buffer.startIndex] == 0x7B { // '{'
                mode = .legacy
                print("[FrameDecoder] Detected legacy newline-delimited protocol (first byte is '{')")
            } else {
                mode = .frame
            }
        }

        if mode == .legacy {
            return extractLegacyMessages()
        }

        // Frame mode
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

    /// Extract newline-delimited JSON messages from the legacy buffer.
    private func extractLegacyMessages() -> [Data] {
        var frames: [Data] = []
        var start = buffer.startIndex

        for i in buffer.startIndex..<buffer.endIndex {
            if buffer[i] == 0x0A { // '\n'
                let lineData = buffer.subdata(in: start..<i)
                if !lineData.isEmpty {
                    frames.append(lineData)
                }
                start = i + 1
            }
        }

        buffer = buffer.subdata(in: start..<buffer.endIndex)
        return frames
    }

    /// Reset the internal reassembly buffer.
    func reset() {
        buffer = Data()
        mode = .detect
    }
}
