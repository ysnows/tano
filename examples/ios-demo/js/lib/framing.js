/**
 * Length-prefixed frame codec for iOS IPC communication.
 *
 * Wire format: [4-byte big-endian uint32 length][<length> bytes of payload]
 *
 * Auto-detects legacy newline-delimited JSON: if the first byte is '{' (0x7B),
 * falls back to splitting on '\n'.
 */

const MAX_PAYLOAD = 64 * 1024 * 1024; // 64 MB

/**
 * Encode a payload (string or Buffer) into a length-prefixed frame.
 */
function encode(payload) {
    const body = typeof payload === 'string'
        ? Buffer.from(payload, 'utf8')
        : payload;

    const header = Buffer.allocUnsafe(4);
    header.writeUInt32BE(body.byteLength, 0);
    return Buffer.concat([header, body]);
}

/**
 * Extract newline-delimited JSON messages from a buffer.
 */
function extractLegacyMessages(buf) {
    const messages = [];
    let start = 0;
    for (let i = 0; i < buf.length; i++) {
        if (buf[i] === 0x0A) { // '\n'
            const line = buf.slice(start, i).toString('utf8').trim();
            if (line.length > 0) {
                messages.push(line);
            }
            start = i + 1;
        }
    }
    return { messages, remainder: buf.slice(start) };
}

/**
 * Streaming frame decoder with automatic legacy protocol detection.
 */
class FrameDecoder {
    constructor() {
        this.buffer = Buffer.alloc(0);
        this.mode = 'detect'; // 'detect' | 'frame' | 'legacy'
    }

    /**
     * Feed a new data chunk into the decoder.
     * @param {Buffer} chunk - Raw bytes received from the socket.
     * @returns {string[]} Array of fully-reassembled payload strings.
     */
    feed(chunk) {
        this.buffer = Buffer.concat([this.buffer, chunk]);

        // Auto-detect on first meaningful data
        if (this.mode === 'detect' && this.buffer.length > 0) {
            if (this.buffer[0] === 0x7B) { // '{'
                this.mode = 'legacy';
                console.log('[FrameDecoder] Detected legacy newline-delimited protocol');
            } else {
                this.mode = 'frame';
            }
        }

        if (this.mode === 'legacy') {
            const { messages, remainder } = extractLegacyMessages(this.buffer);
            this.buffer = remainder;
            return messages;
        }

        // Frame mode
        const frames = [];

        while (this.buffer.length >= 4) {
            const payloadLength = this.buffer.readUInt32BE(0);

            if (payloadLength > MAX_PAYLOAD) {
                console.error(`[FrameDecoder] Unreasonable payload length: ${payloadLength} bytes. Resetting buffer.`);
                this.buffer = Buffer.alloc(0);
                break;
            }

            const totalLength = 4 + payloadLength;

            if (this.buffer.length < totalLength) {
                break;
            }

            const payload = this.buffer.slice(4, totalLength).toString('utf8');
            frames.push(payload);
            this.buffer = this.buffer.slice(totalLength);
        }

        return frames;
    }

    /**
     * Reset the internal reassembly buffer.
     */
    reset() {
        this.buffer = Buffer.alloc(0);
        this.mode = 'detect';
    }
}

module.exports = { encode, FrameDecoder };
