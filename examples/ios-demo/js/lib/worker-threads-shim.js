/**
 * Worker Threads Shim for iOS
 *
 * On macOS, @enconvo/api's Commander uses worker_threads.parentPort to
 * communicate with the main server thread. On iOS (EdgeJS/JSC), there are
 * no Worker threads — everything runs in a single runtime.
 *
 * This shim provides a fake parentPort that:
 *   - postMessage() → writes to the UDS socket via FrameEncoder
 *   - on('message', handler) → receives messages from the dispatcher
 *
 * Must be loaded BEFORE @enconvo/api is required.
 */

const { encode } = require('./framing');
const EventEmitter = require('events');

class FakeParentPort extends EventEmitter {
    constructor() {
        super();
        this._socket = null;
    }

    /**
     * Set the UDS socket for message transmission.
     */
    setSocket(socket) {
        this._socket = socket;
    }

    /**
     * Send a message to the parent (Swift) — mirrors Worker.parentPort.postMessage().
     * This is what @enconvo/api's Commander.send() calls internally.
     */
    postMessage(msg) {
        if (!this._socket || this._socket.destroyed) {
            console.log('[WorkerShim] Socket not available for postMessage');
            return;
        }
        const frame = encode(JSON.stringify(msg));
        this._socket.write(frame);
    }
}

// Singleton instance
const fakeParentPort = new FakeParentPort();

// Also provide workerData (the initial request sent to the worker)
let fakeWorkerData = null;

/**
 * Deliver a message to the fake parentPort as if it came from the parent.
 * Called by the server when a message arrives for a command.
 */
function deliverMessage(msg) {
    fakeParentPort.emit('message', msg);
}

/**
 * Set the worker data (initial request).
 */
function setWorkerData(data) {
    fakeWorkerData = data;
}

// Override the worker_threads module
const shimModule = {
    parentPort: fakeParentPort,
    get workerData() { return fakeWorkerData; },
    isMainThread: false,  // Extensions think they're in a Worker
    Worker: class FakeWorker {
        constructor() { throw new Error('Worker threads not supported on iOS'); }
    },
    threadId: 1,
};

module.exports = {
    shimModule,
    fakeParentPort,
    deliverMessage,
    setWorkerData,
};
