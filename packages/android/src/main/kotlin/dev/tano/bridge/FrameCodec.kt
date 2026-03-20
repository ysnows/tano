package dev.tano.bridge

import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Encode a payload into a length-prefixed frame.
 *
 * Wire format: `[4-byte big-endian UInt32 length][payload bytes]`
 *
 * Mirrors the iOS FrameEncoder.
 */
object FrameEncoder {

    /**
     * Encode a raw byte payload into a framed message.
     */
    fun encode(payload: ByteArray): ByteArray {
        val buffer = ByteBuffer.allocate(4 + payload.size)
        buffer.order(ByteOrder.BIG_ENDIAN)
        buffer.putInt(payload.size)
        buffer.put(payload)
        return buffer.array()
    }

    /**
     * Encode a UTF-8 string payload into a framed message.
     */
    fun encode(string: String): ByteArray {
        return encode(string.toByteArray(Charsets.UTF_8))
    }
}

/**
 * Maximum valid payload size — anything larger is treated as a protocol error.
 */
private const val MAX_PAYLOAD: Int = 64 * 1024 * 1024 // 64 MB

/**
 * Streaming length-prefixed frame decoder.
 *
 * Feed raw socket data via [feed]; the decoder reassembles complete frames
 * and returns them. Partial frames are buffered internally until enough
 * data arrives.
 *
 * Mirrors the iOS FrameDecoder.
 */
class FrameDecoder {

    private val buffer = ByteArrayOutputStream()

    /**
     * Feed a new data chunk into the decoder.
     *
     * @param data Raw bytes received from the socket.
     * @return Zero or more fully-reassembled payload byte arrays.
     */
    fun feed(data: ByteArray): List<ByteArray> {
        buffer.write(data)

        val frames = mutableListOf<ByteArray>()
        var raw = buffer.toByteArray()

        while (raw.size >= 4) {
            val payloadLength = ByteBuffer.wrap(raw, 0, 4)
                .order(ByteOrder.BIG_ENDIAN)
                .int

            // Guard against unreasonable sizes
            if (payloadLength < 0 || payloadLength > MAX_PAYLOAD) {
                println("[FrameDecoder] Unreasonable payload length: $payloadLength bytes. Resetting buffer.")
                buffer.reset()
                return frames
            }

            val totalLength = 4 + payloadLength
            if (raw.size < totalLength) break

            // Extract the payload (bytes 4 until 4+payloadLength)
            frames.add(raw.copyOfRange(4, totalLength))

            // Advance past this frame
            raw = raw.copyOfRange(totalLength, raw.size)
        }

        // Store remaining bytes back into the buffer
        buffer.reset()
        if (raw.isNotEmpty()) {
            buffer.write(raw)
        }

        return frames
    }

    /**
     * Reset the internal reassembly buffer.
     */
    fun reset() {
        buffer.reset()
    }
}
