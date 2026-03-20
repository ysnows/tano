/**
 * iOS Commander API — replaces macOS Worker-based Commander.
 *
 * Instead of communicating via parentPort (Worker threads), this Commander
 * writes directly to the UDS socket connection.
 *
 * Maintains the same API surface as macOS Commander for extension compatibility.
 */

const { encode } = require('./framing');

// Global socket reference — set by server/index.js after connecting
let _socket = null;
let _requestHandlers = new Map();
let _clickHandler = null;
let _requestId = null;
let _callId = null;
let _stateId = null;

const REQUEST_TIMEOUT = 5 * 60 * 1000; // 5 minutes

/**
 * Composite key for matching request/response pairs.
 */
function compositeKey(stateId, callId, requestId, method, sendId) {
    return `${stateId || ''}_${callId || ''}_${requestId || ''}_${method || ''}_${sendId || ''}`;
}

const Commander = {
    /**
     * Initialize the Commander with a connected socket.
     * Called by server/index.js after UDS connection is established.
     */
    init(socket) {
        _socket = socket;
    },

    /**
     * Fire-and-forget message to Swift.
     * Accepts optional context override for concurrent safety.
     */
    send(method, payloads = {}, context = null) {
        if (!_socket || _socket.destroyed) {
            console.log('[Commander] Socket not available for send:', method);
            return;
        }

        const ctx = context || { callId: _callId, requestId: _requestId, stateId: _stateId };
        const msg = {
            type: 'request',
            method: method,
            callId: ctx.callId || '',
            requestId: ctx.requestId || '',
            stateId: ctx.stateId || '',
            payloads: payloads,
            needResult: false,
        };

        const frame = encode(JSON.stringify(msg));
        _socket.write(frame);
    },

    /**
     * Request/response pattern — sends a message and waits for a matching response.
     * Matched by composite key: stateId_callId_requestId_method_sendId
     */
    sendRequest(params) {
        return new Promise((resolve, reject) => {
            if (!_socket || _socket.destroyed) {
                reject(new Error('Socket not available'));
                return;
            }

            const sendId = Math.random().toString(36).substring(2, 15);
            const method = params.method || 'request';
            const callId = params.callId || _callId || '';
            const requestId = params.requestId || _requestId || '';
            const stateId = params.stateId || _stateId || '';

            const key = compositeKey(stateId, callId, requestId, method, sendId);

            // Timeout
            const timer = setTimeout(() => {
                _requestHandlers.delete(key);
                reject(new Error(`Request timeout: ${method}`));
            }, REQUEST_TIMEOUT);

            _requestHandlers.set(key, { resolve, reject, timer });

            const msg = {
                type: 'request',
                method: method,
                callId: callId,
                requestId: requestId,
                stateId: stateId,
                sendId: sendId,
                payloads: params.payloads || {},
                needResult: true,
            };

            const frame = encode(JSON.stringify(msg));
            _socket.write(frame);
        });
    },

    /**
     * Resolve a pending request with a response.
     * Called by the message handler when a response is received.
     */
    resolveRequest(msg) {
        const key = compositeKey(
            msg.stateId, msg.callId, msg.requestId, msg.method, msg.sendId
        );

        const handler = _requestHandlers.get(key);
        if (!handler && _requestHandlers.size > 0) {
            // Debug: log key mismatch
            console.log(`[Commander] Key miss: ${key}`);
            console.log(`[Commander] Pending keys: ${[..._requestHandlers.keys()].join(' | ')}`);
        }
        if (handler) {
            clearTimeout(handler.timer);
            _requestHandlers.delete(key);
            handler.resolve(msg.payloads || {});
            return true;
        }
        return false;
    },

    /**
     * Register the command entry point handler.
     */
    addClickListener(handler) {
        _clickHandler = handler;
    },

    /**
     * Get the registered click handler.
     */
    getClickHandler() {
        return _clickHandler;
    },

    /**
     * Set the current context for this command execution.
     */
    setContext(callId, requestId, stateId) {
        _callId = callId;
        _requestId = requestId;
        _stateId = stateId;
    },

    /**
     * Send a stream chunk back to Swift.
     * Accepts optional context override for concurrent safety.
     */
    sendStream(payloads = {}, context = null) {
        this.send('responseStream', payloads, context);
    },

    /**
     * Send context update back to Swift.
     */
    sendContext(payloads = {}, context = null) {
        this.send('responseContext', payloads, context);
    },

    /**
     * Signal command completion.
     */
    sendExit(code = 0, context = null) {
        this.send('exit', { code }, context);
    },

    /**
     * Send the final result and exit.
     * Accepts optional context override for concurrent safety.
     */
    sendResult(payloads = {}, status = 0, context = null) {
        if (!_socket || _socket.destroyed) {
            console.log('[Commander] Socket not available for sendResult');
            return;
        }

        const ctx = context || { callId: _callId, requestId: _requestId, stateId: _stateId };
        const msg = {
            type: 'response',
            method: 'start',
            callId: ctx.callId || '',
            requestId: ctx.requestId || '',
            stateId: ctx.stateId || '',
            payloads: {
                ...payloads,
                status: status,
            },
        };

        const frame = encode(JSON.stringify(msg));
        _socket.write(frame);
    },
};

module.exports = Commander;
