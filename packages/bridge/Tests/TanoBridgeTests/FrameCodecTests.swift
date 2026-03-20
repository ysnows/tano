import XCTest
@testable import TanoBridge

final class FrameCodecTests: XCTestCase {

    // MARK: - Encode / Decode Round-Trip

    func testEncodeDecode() {
        let original = "Hello, Tano Bridge!".data(using: .utf8)!
        let encoded = FrameEncoder.encode(original)

        let decoder = FrameDecoder()
        let frames = decoder.feed(encoded)

        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames.first, original)
    }

    func testEncodeDecodeString() {
        let message = "{\"type\":\"request\",\"method\":\"test\"}"
        let encoded = FrameEncoder.encode(message)

        let decoder = FrameDecoder()
        let frames = decoder.feed(encoded)

        XCTAssertEqual(frames.count, 1)
        let decoded = String(data: frames[0], encoding: .utf8)
        XCTAssertEqual(decoded, message)
    }

    // MARK: - Multiple Frames

    func testMultipleFrames() {
        let messages = ["first", "second", "third"]
        var allData = Data()
        for msg in messages {
            allData.append(FrameEncoder.encode(msg))
        }

        let decoder = FrameDecoder()
        let frames = decoder.feed(allData)

        XCTAssertEqual(frames.count, 3)
        for (i, frame) in frames.enumerated() {
            let decoded = String(data: frame, encoding: .utf8)
            XCTAssertEqual(decoded, messages[i])
        }
    }

    func testMultipleFramesFedSeparately() {
        let decoder = FrameDecoder()

        let frame1 = FrameEncoder.encode("alpha")
        let frame2 = FrameEncoder.encode("beta")

        let results1 = decoder.feed(frame1)
        XCTAssertEqual(results1.count, 1)
        XCTAssertEqual(String(data: results1[0], encoding: .utf8), "alpha")

        let results2 = decoder.feed(frame2)
        XCTAssertEqual(results2.count, 1)
        XCTAssertEqual(String(data: results2[0], encoding: .utf8), "beta")
    }

    // MARK: - Partial Frame

    func testPartialFrame() {
        let original = "partial frame test".data(using: .utf8)!
        let encoded = FrameEncoder.encode(original)

        let decoder = FrameDecoder()

        // Feed only the header (4 bytes)
        let headerOnly = encoded.subdata(in: 0..<4)
        let result1 = decoder.feed(headerOnly)
        XCTAssertEqual(result1.count, 0, "Should not produce a frame from header only")

        // Feed first half of payload
        let mid = 4 + original.count / 2
        let part1 = encoded.subdata(in: 4..<mid)
        let result2 = decoder.feed(part1)
        XCTAssertEqual(result2.count, 0, "Should not produce a frame from partial payload")

        // Feed the rest
        let part2 = encoded.subdata(in: mid..<encoded.count)
        let result3 = decoder.feed(part2)
        XCTAssertEqual(result3.count, 1)
        XCTAssertEqual(result3.first, original)
    }

    func testPartialFrameOneByteAtATime() {
        let original = "byte by byte".data(using: .utf8)!
        let encoded = FrameEncoder.encode(original)

        let decoder = FrameDecoder()
        var frames: [Data] = []

        for i in 0..<encoded.count {
            let byte = encoded.subdata(in: i..<(i + 1))
            let result = decoder.feed(byte)
            frames.append(contentsOf: result)
        }

        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames.first, original)
    }

    // MARK: - Empty Payload

    func testEmptyPayload() {
        let empty = Data()
        let encoded = FrameEncoder.encode(empty)

        // Should be exactly 4 bytes (header with length 0)
        XCTAssertEqual(encoded.count, 4)

        let decoder = FrameDecoder()
        let frames = decoder.feed(encoded)

        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames.first, empty)
    }

    // MARK: - Large Payload

    func testLargePayload() {
        // 1 MB payload
        let size = 1024 * 1024
        var largeData = Data(count: size)
        for i in 0..<size {
            largeData[i] = UInt8(i % 256)
        }

        let encoded = FrameEncoder.encode(largeData)
        XCTAssertEqual(encoded.count, 4 + size)

        let decoder = FrameDecoder()
        let frames = decoder.feed(encoded)

        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames.first, largeData)
    }

    // MARK: - Reset

    func testReset() {
        let decoder = FrameDecoder()

        // Feed partial data
        let encoded = FrameEncoder.encode("test reset")
        let partial = encoded.subdata(in: 0..<6)
        _ = decoder.feed(partial)

        // Reset clears the buffer
        decoder.reset()

        // Feed a complete new frame
        let newEncoded = FrameEncoder.encode("fresh")
        let frames = decoder.feed(newEncoded)

        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(String(data: frames[0], encoding: .utf8), "fresh")
    }

    // MARK: - Frame Header Encoding

    func testFrameHeaderIsBigEndian() {
        let payload = Data([0x01, 0x02, 0x03]) // 3 bytes
        let encoded = FrameEncoder.encode(payload)

        // First 4 bytes should be big-endian UInt32 of value 3
        XCTAssertEqual(encoded[0], 0x00)
        XCTAssertEqual(encoded[1], 0x00)
        XCTAssertEqual(encoded[2], 0x00)
        XCTAssertEqual(encoded[3], 0x03)

        // Followed by the payload
        XCTAssertEqual(encoded[4], 0x01)
        XCTAssertEqual(encoded[5], 0x02)
        XCTAssertEqual(encoded[6], 0x03)
    }

    // MARK: - Oversized Payload Protection

    func testOversizedPayloadResetsBuffer() {
        let decoder = FrameDecoder()

        // Craft a header claiming 100MB payload (over the 64MB limit)
        var badLength = UInt32(100 * 1024 * 1024).bigEndian
        var badFrame = Data(bytes: &badLength, count: 4)
        badFrame.append(Data([0x00, 0x01, 0x02])) // some garbage bytes

        let frames = decoder.feed(badFrame)
        XCTAssertEqual(frames.count, 0, "Should produce no frames for oversized payload")

        // Buffer should be reset — feeding a valid frame should work
        let validEncoded = FrameEncoder.encode("recovery")
        let validFrames = decoder.feed(validEncoded)

        XCTAssertEqual(validFrames.count, 1)
        XCTAssertEqual(String(data: validFrames[0], encoding: .utf8), "recovery")
    }
}
