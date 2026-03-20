import Foundation
import Network

/// A lightweight HTTP/1.1 server built on `NWListener` (Network.framework).
///
/// Each incoming TCP connection is read, parsed as an HTTP request, passed
/// to `fetchHandler`, and a response is written back before closing the
/// connection (Connection: close semantics).
final class TanoHTTPServer {

    // MARK: - Types

    /// Called with the HTTP request details. The `respond` closure MUST be
    /// called exactly once with (statusCode, headers, body) to send the
    /// response back to the client.
    typealias FetchHandler = (
        _ method: String,
        _ url: String,
        _ headers: [(String, String)],
        _ body: String,
        _ respond: @escaping (Int, [(String, String)], String) -> Void
    ) -> Void

    // MARK: - Properties

    var fetchHandler: FetchHandler?
    private(set) var port: UInt16 = 0
    private(set) var hostname: String = "127.0.0.1"

    private var listener: NWListener?
    private let serverQueue = DispatchQueue(label: "dev.tano.http-server", qos: .userInitiated)

    // MARK: - Lifecycle

    /// Start listening for TCP connections.
    ///
    /// - Parameters:
    ///   - port: TCP port to bind to (0 = let the OS assign).
    ///   - hostname: Interface to bind to (default 127.0.0.1).
    ///   - ready: Called on the server queue once the listener is ready,
    ///            with the actual port the server is bound to.
    func start(port: UInt16, hostname: String, ready: @escaping (UInt16) -> Void) throws {
        self.hostname = hostname

        let params = NWParameters.tcp
        // Allow address reuse for quick restart
        params.allowLocalEndpointReuse = true

        let nwPort: NWEndpoint.Port = port == 0
            ? .any
            : NWEndpoint.Port(rawValue: port)!

        let nwListener = try NWListener(using: params, on: nwPort)
        self.listener = nwListener

        nwListener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                let actualPort = nwListener.port?.rawValue ?? port
                self?.port = actualPort
                ready(actualPort)
            case .failed(let error):
                print("[TanoHTTPServer] Listener failed: \(error)")
                nwListener.cancel()
            default:
                break
            }
        }

        nwListener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        nwListener.start(queue: serverQueue)
    }

    /// Stop the server and cancel all connections.
    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connection handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: serverQueue)
        receiveData(on: connection, accumulated: Data())
    }

    private func receiveData(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self = self else {
                connection.cancel()
                return
            }

            if let error = error {
                print("[TanoHTTPServer] Receive error: \(error)")
                connection.cancel()
                return
            }

            var buffer = accumulated
            if let content = content {
                buffer.append(content)
            }

            // Try to parse the accumulated data
            if let parsed = TanoHTTPParser.parse(buffer) {
                self.handleRequest(parsed, connection: connection)
            } else if isComplete {
                // Connection closed before a complete request — just close
                connection.cancel()
            } else {
                // Need more data
                self.receiveData(on: connection, accumulated: buffer)
            }
        }
    }

    private func handleRequest(_ request: ParsedHTTPRequest, connection: NWConnection) {
        let bodyString = String(data: request.body, encoding: .utf8) ?? ""

        // Construct a full URL for the handler
        let url = "http://\(hostname):\(port)\(request.rawURL)"

        guard let handler = fetchHandler else {
            sendResponse(
                connection: connection,
                statusCode: 500,
                headers: [("Content-Type", "text/plain")],
                body: "No fetch handler registered"
            )
            return
        }

        handler(request.method, url, request.headers, bodyString) { [weak self] statusCode, headers, body in
            self?.sendResponse(
                connection: connection,
                statusCode: statusCode,
                headers: headers,
                body: body
            )
        }
    }

    private func sendResponse(
        connection: NWConnection,
        statusCode: Int,
        headers: [(String, String)],
        body: String
    ) {
        var builder = TanoHTTPResponseBuilder()
        builder.statusCode = statusCode
        builder.statusText = TanoHTTPResponseBuilder.statusText(for: statusCode)
        builder.body = Data(body.utf8)

        for (name, value) in headers {
            builder.setHeader(name, value)
        }

        let data = builder.build()

        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
