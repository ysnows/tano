import Foundation
import JavaScriptCore

/// Bridges the Web-standard `WebSocket` API to `URLSessionWebSocketTask` on the native side.
///
/// Architecture:
/// 1. A native `_nativeWebSocketCreate(url, protocols, callbackObj)` is registered on
///    the JSContext.
/// 2. The native function creates a `URLSessionWebSocketTask` from the URL.
/// 3. All JSC callbacks go through `jscPerform` to ensure thread safety.
/// 4. A JS polyfill wraps the native bridge into the standard `WebSocket` constructor.
enum TanoWebSocket {

    /// Active WebSocket connections keyed by a unique ID.
    /// This retains the delegate and task so they are not deallocated while in use.
    private static var connections: [Int: WebSocketConnection] = [:]
    private static var nextID = 1
    private static let lock = NSLock()

    static func inject(into context: JSContext, jscPerform: @escaping (@escaping () -> Void) -> Void) {

        // 1. Register the native bridge function
        let nativeCreate: @convention(block) (JSValue, JSValue, JSValue) -> Int = {
            urlVal, protocolsVal, callbackObjVal in

            guard let ctx = JSContext.current() else { return -1 }

            let urlString = urlVal.toString() ?? ""

            // Parse sub-protocols
            var protocols: [String] = []
            if !protocolsVal.isUndefined && !protocolsVal.isNull {
                if protocolsVal.isArray {
                    let length = protocolsVal.forProperty("length")?.toInt32() ?? 0
                    for i in 0..<length {
                        if let p = protocolsVal.atIndex(Int(i))?.toString() {
                            protocols.append(p)
                        }
                    }
                } else if let p = protocolsVal.toString(), !p.isEmpty {
                    protocols.append(p)
                }
            }

            // Prevent GC of the callback object while the connection is alive
            let managed = JSManagedValue(value: callbackObjVal)!
            ctx.virtualMachine.addManagedReference(managed, withOwner: TanoWebSocket.self as AnyObject)

            guard let url = URL(string: urlString) else {
                jscPerform {
                    guard let cb = managed.value, !cb.isUndefined else { return }
                    cb.invokeMethod("onerror", withArguments: [["error": "Invalid URL: \(urlString)"]])
                    ctx.virtualMachine.removeManagedReference(managed, withOwner: TanoWebSocket.self as AnyObject)
                }
                return -1
            }

            // Assign an ID for this connection
            lock.lock()
            let connID = nextID
            nextID += 1
            lock.unlock()

            // Create the URLSession delegate and task
            let delegate = WebSocketDelegate(
                connID: connID,
                jscPerform: jscPerform,
                managed: managed,
                context: ctx
            )

            let session = URLSession(
                configuration: .default,
                delegate: delegate,
                delegateQueue: nil
            )

            var request = URLRequest(url: url)
            if !protocols.isEmpty {
                request.setValue(protocols.joined(separator: ", "),
                                forHTTPHeaderField: "Sec-WebSocket-Protocol")
            }

            let task = session.webSocketTask(with: request)

            let connection = WebSocketConnection(
                task: task,
                session: session,
                delegate: delegate,
                managed: managed,
                context: ctx
            )

            lock.lock()
            connections[connID] = connection
            lock.unlock()

            // Start receiving messages
            delegate.receiveLoop(task: task)

            // Connect
            task.resume()

            return connID
        }

        context.setObject(nativeCreate, forKeyedSubscript: "_nativeWebSocketCreate" as NSString)

        // 2. Native send function
        let nativeSend: @convention(block) (Int, JSValue) -> Void = { connID, dataVal in
            lock.lock()
            let conn = connections[connID]
            lock.unlock()

            guard let conn = conn else { return }

            let data = dataVal.toString() ?? ""
            let message = URLSessionWebSocketTask.Message.string(data)

            conn.task.send(message) { error in
                if let error = error {
                    jscPerform {
                        guard let cb = conn.managed.value, !cb.isUndefined else { return }
                        cb.invokeMethod("onerror", withArguments: [["error": error.localizedDescription]])
                    }
                }
            }
        }

        context.setObject(nativeSend, forKeyedSubscript: "_nativeWebSocketSend" as NSString)

        // 3. Native close function
        let nativeClose: @convention(block) (Int, Int, JSValue) -> Void = { connID, code, reasonVal in
            lock.lock()
            let conn = connections[connID]
            lock.unlock()

            guard let conn = conn else { return }

            let reason = reasonVal.isUndefined || reasonVal.isNull ? "" : (reasonVal.toString() ?? "")
            let closeCode = URLSessionWebSocketTask.CloseCode(rawValue: code) ?? .normalClosure
            let reasonData = reason.data(using: .utf8)

            conn.task.cancel(with: closeCode, reason: reasonData)
        }

        context.setObject(nativeClose, forKeyedSubscript: "_nativeWebSocketClose" as NSString)

        // 4. JS polyfill that wraps native functions into standard WebSocket constructor
        JSCHelpers.evaluate(context, script: webSocketPolyfill, sourceURL: "tano://globals/websocket.js")
    }

    /// Clean up a connection after close.
    fileprivate static func removeConnection(_ connID: Int, context: JSContext, managed: JSManagedValue) {
        lock.lock()
        connections.removeValue(forKey: connID)
        lock.unlock()
        context.virtualMachine.removeManagedReference(managed, withOwner: TanoWebSocket.self as AnyObject)
    }

    // MARK: - WebSocketConnection

    private class WebSocketConnection {
        let task: URLSessionWebSocketTask
        let session: URLSession
        let delegate: WebSocketDelegate
        let managed: JSManagedValue
        let context: JSContext

        init(task: URLSessionWebSocketTask,
             session: URLSession,
             delegate: WebSocketDelegate,
             managed: JSManagedValue,
             context: JSContext) {
            self.task = task
            self.session = session
            self.delegate = delegate
            self.managed = managed
            self.context = context
        }
    }

    // MARK: - WebSocketDelegate

    private class WebSocketDelegate: NSObject, URLSessionWebSocketDelegate {
        let connID: Int
        let jscPerform: (@escaping () -> Void) -> Void
        let managed: JSManagedValue
        let context: JSContext

        init(connID: Int,
             jscPerform: @escaping (@escaping () -> Void) -> Void,
             managed: JSManagedValue,
             context: JSContext) {
            self.connID = connID
            self.jscPerform = jscPerform
            self.managed = managed
            self.context = context
        }

        func urlSession(_ session: URLSession,
                        webSocketTask: URLSessionWebSocketTask,
                        didOpenWithProtocol protocol: String?) {
            jscPerform { [self] in
                guard let cb = managed.value, !cb.isUndefined else { return }
                cb.invokeMethod("onopen", withArguments: [])
            }
        }

        func urlSession(_ session: URLSession,
                        webSocketTask: URLSessionWebSocketTask,
                        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                        reason: Data?) {
            let code = closeCode.rawValue
            let reasonStr = reason.flatMap { String(data: $0, encoding: .utf8) } ?? ""

            jscPerform { [self] in
                guard let cb = managed.value, !cb.isUndefined else { return }
                cb.invokeMethod("onclose", withArguments: [["code": code, "reason": reasonStr]])
                TanoWebSocket.removeConnection(connID, context: context, managed: managed)
            }
        }

        func urlSession(_ session: URLSession,
                        task: URLSessionTask,
                        didCompleteWithError error: Error?) {
            guard let error = error else { return }

            jscPerform { [self] in
                guard let cb = managed.value, !cb.isUndefined else { return }
                cb.invokeMethod("onerror", withArguments: [["error": error.localizedDescription]])
                cb.invokeMethod("onclose", withArguments: [["code": 1006, "reason": error.localizedDescription]])
                TanoWebSocket.removeConnection(connID, context: context, managed: managed)
            }
        }

        /// Continuously receive messages from the WebSocket task.
        func receiveLoop(task: URLSessionWebSocketTask) {
            task.receive { [weak self] result in
                guard let self = self else { return }

                switch result {
                case .success(let message):
                    let data: String
                    switch message {
                    case .string(let text):
                        data = text
                    case .data(let binary):
                        data = String(data: binary, encoding: .utf8) ?? ""
                    @unknown default:
                        data = ""
                    }

                    self.jscPerform {
                        guard let cb = self.managed.value, !cb.isUndefined else { return }
                        cb.invokeMethod("onmessage", withArguments: [["data": data]])
                    }

                    // Continue receiving
                    self.receiveLoop(task: task)

                case .failure(let error):
                    self.jscPerform {
                        guard let cb = self.managed.value, !cb.isUndefined else { return }
                        cb.invokeMethod("onerror", withArguments: [["error": error.localizedDescription]])
                    }
                }
            }
        }
    }

    // MARK: - JS Polyfill

    private static let webSocketPolyfill = """
    (function() {
        var CONNECTING = 0;
        var OPEN = 1;
        var CLOSING = 2;
        var CLOSED = 3;

        function WebSocket(url, protocols) {
            if (!(this instanceof WebSocket)) {
                throw new TypeError("Failed to construct 'WebSocket': Please use the 'new' operator");
            }

            if (!url) {
                throw new SyntaxError("Failed to construct 'WebSocket': The URL must not be empty");
            }

            this.url = String(url);
            this.readyState = CONNECTING;
            this.bufferedAmount = 0;
            this.extensions = '';
            this.protocol = '';
            this.binaryType = 'blob';

            // Event handlers
            this.onopen = null;
            this.onmessage = null;
            this.onerror = null;
            this.onclose = null;

            // Internal callbacks object passed to native
            var self = this;
            var callbacks = {
                onopen: function() {
                    self.readyState = OPEN;
                    if (typeof self.onopen === 'function') {
                        self.onopen({ type: 'open', target: self });
                    }
                },
                onmessage: function(event) {
                    if (typeof self.onmessage === 'function') {
                        self.onmessage({ type: 'message', data: event.data, target: self });
                    }
                },
                onerror: function(event) {
                    if (typeof self.onerror === 'function') {
                        self.onerror({ type: 'error', error: event.error, message: event.error, target: self });
                    }
                },
                onclose: function(event) {
                    self.readyState = CLOSED;
                    if (typeof self.onclose === 'function') {
                        self.onclose({
                            type: 'close',
                            code: event.code || 1000,
                            reason: event.reason || '',
                            wasClean: (event.code || 1000) === 1000,
                            target: self
                        });
                    }
                }
            };

            // Normalize protocols argument
            var protoArg = null;
            if (protocols !== undefined && protocols !== null) {
                if (typeof protocols === 'string') {
                    protoArg = protocols;
                } else if (Array.isArray(protocols)) {
                    protoArg = protocols;
                }
            }

            this._nativeID = _nativeWebSocketCreate(this.url, protoArg, callbacks);
        }

        WebSocket.CONNECTING = CONNECTING;
        WebSocket.OPEN = OPEN;
        WebSocket.CLOSING = CLOSING;
        WebSocket.CLOSED = CLOSED;

        WebSocket.prototype.CONNECTING = CONNECTING;
        WebSocket.prototype.OPEN = OPEN;
        WebSocket.prototype.CLOSING = CLOSING;
        WebSocket.prototype.CLOSED = CLOSED;

        WebSocket.prototype.send = function(data) {
            if (this.readyState === CONNECTING) {
                throw new Error("Failed to execute 'send' on 'WebSocket': Still in CONNECTING state");
            }
            if (this.readyState !== OPEN) {
                return;
            }
            _nativeWebSocketSend(this._nativeID, String(data));
        };

        WebSocket.prototype.close = function(code, reason) {
            if (this.readyState === CLOSING || this.readyState === CLOSED) {
                return;
            }
            this.readyState = CLOSING;
            var closeCode = (code !== undefined) ? code : 1000;
            var closeReason = (reason !== undefined) ? reason : '';
            _nativeWebSocketClose(this._nativeID, closeCode, closeReason);
        };

        globalThis.WebSocket = WebSocket;
    })();
    """
}
