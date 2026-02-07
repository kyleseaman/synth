import Foundation
import Network

enum HTTPTransportError: Error {
    case invalidPort(UInt16)
}

class HTTPTransport {
    let handler: MCPProtocolHandler
    let port: UInt16
    private var listener: NWListener?
    private var sessions: [String: SSESession] = [:]
    private let sessionsLock = NSLock()

    init(handler: MCPProtocolHandler, port: UInt16) {
        self.handler = handler
        self.port = port
    }

    func start() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw HTTPTransportError.invalidPort(port)
        }
        listener = try NWListener(using: params, on: nwPort)
        listener?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                log("HTTP transport listening on localhost:\(self.port)")
            case .failed(let error):
                log("HTTP listener failed: \(error)")
            default:
                break
            }
        }
        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }
        listener?.start(queue: .global(qos: .userInitiated))
    }

    func stop() {
        listener?.cancel()
        sessionsLock.lock()
        sessions.values.forEach { $0.close() }
        sessions.removeAll()
        sessionsLock.unlock()
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        receiveHTTPRequest(connection)
    }

    private func receiveHTTPRequest(_ connection: NWConnection) {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 65536
        ) { [weak self] content, _, isComplete, error in
            guard let self = self, let data = content else {
                connection.cancel()
                return
            }

            guard let request = HTTPRequest.parse(data) else {
                self.sendHTTPResponse(
                    connection, status: 400, body: "Bad Request"
                )
                return
            }

            let keepReceiving = self.routeRequest(
                connection, request: request
            )

            if keepReceiving && !isComplete {
                self.receiveHTTPRequest(connection)
            }
        }
    }

    /// Routes the request and returns whether the connection
    /// should continue receiving (false for SSE long-lived
    /// connections).
    @discardableResult
    private func routeRequest(
        _ connection: NWConnection,
        request: HTTPRequest
    ) -> Bool {
        // CORS preflight
        if request.method == "OPTIONS" {
            sendCORSPreflight(connection)
            return true
        }

        switch (request.method, request.path) {
        case ("POST", "/mcp"):
            handlePost(connection, request: request)
            return true
        case ("GET", "/mcp"):
            handleSSE(connection, request: request)
            return false // SSE keeps the connection alive
        case ("DELETE", "/mcp"):
            handleDelete(connection, request: request)
            return true
        case ("GET", "/health"):
            sendHTTPResponse(
                connection, status: 200, body: "{\"status\":\"ok\"}"
            )
            return true
        default:
            sendHTTPResponse(
                connection, status: 404, body: "Not Found"
            )
            return true
        }
    }

    // MARK: - POST /mcp (JSON-RPC requests)

    private func handlePost(_ connection: NWConnection, request: HTTPRequest) {
        guard let bodyData = request.body, !bodyData.isEmpty else {
            sendHTTPResponse(connection, status: 400, body: "No body")
            return
        }

        let sessionId = request.headers["mcp-session-id"]

        if let responseData = handler.handleMessage(bodyData) {
            let responseBody = String(data: responseData, encoding: .utf8) ?? "{}"
            var headers = "Content-Type: application/json\r\n"
            headers += corsHeaders()

            // Detect initialize request to generate a session ID
            let parsed = try? JSONSerialization.jsonObject(
                with: bodyData
            ) as? [String: Any]
            let isInitialize = parsed?["method"] as? String
                == "initialize"
            if isInitialize {
                let newSessionId = UUID().uuidString
                headers += "Mcp-Session-Id: \(newSessionId)\r\n"
            } else if let existingId = sessionId {
                headers += "Mcp-Session-Id: \(existingId)\r\n"
            }

            sendHTTPResponse(connection, status: 200, body: responseBody, extraHeaders: headers)
        } else {
            sendHTTPResponse(connection, status: 202, body: "", extraHeaders: corsHeaders())
        }
    }

    // MARK: - GET /mcp (SSE stream)

    private func handleSSE(_ connection: NWConnection, request: HTTPRequest) {
        let sessionId = request.headers["mcp-session-id"] ?? UUID().uuidString

        let session = SSESession(connection: connection, sessionId: sessionId)
        sessionsLock.lock()
        sessions[sessionId] = session
        sessionsLock.unlock()

        let headers = "HTTP/1.1 200 OK\r\n"
            + "Content-Type: text/event-stream\r\n"
            + "Cache-Control: no-cache\r\n"
            + "Connection: keep-alive\r\n"
            + corsHeaders()
            + "\r\n"

        if let data = headers.data(using: .utf8) {
            connection.send(content: data, completion: .contentProcessed { _ in })
        }

        // Keep connection alive — will be cleaned up on disconnect
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            if case .cancelled = state {
                self.sessionsLock.lock()
                self.sessions.removeValue(forKey: sessionId)
                self.sessionsLock.unlock()
            }
        }
    }

    // MARK: - DELETE /mcp (session cleanup)

    private func handleDelete(_ connection: NWConnection, request: HTTPRequest) {
        if let sessionId = request.headers["mcp-session-id"] {
            sessionsLock.lock()
            sessions.removeValue(forKey: sessionId)?.close()
            sessionsLock.unlock()
        }
        sendHTTPResponse(connection, status: 200, body: "{\"status\":\"closed\"}", extraHeaders: corsHeaders())
    }

    // MARK: - HTTP Helpers

    private func sendHTTPResponse(
        _ connection: NWConnection,
        status: Int,
        body: String,
        extraHeaders: String = ""
    ) {
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 202: statusText = "Accepted"
        case 400: statusText = "Bad Request"
        case 404: statusText = "Not Found"
        default: statusText = "Unknown"
        }

        let response = "HTTP/1.1 \(status) \(statusText)\r\n"
            + "Content-Length: \(body.utf8.count)\r\n"
            + extraHeaders
            + "\r\n"
            + body

        if let data = response.data(using: .utf8) {
            connection.send(content: data, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private func sendCORSPreflight(_ connection: NWConnection) {
        let response = "HTTP/1.1 204 No Content\r\n"
            + corsHeaders()
            + "Access-Control-Max-Age: 86400\r\n"
            + "\r\n"
        if let data = response.data(using: .utf8) {
            connection.send(content: data, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private func corsHeaders() -> String {
        "Access-Control-Allow-Origin: http://localhost\r\n"
            + "Access-Control-Allow-Methods: GET, POST, DELETE, OPTIONS\r\n"
            + "Access-Control-Allow-Headers: Content-Type, Mcp-Session-Id\r\n"
            + "Vary: Origin\r\n"
    }
}

// MARK: - SSE Session

class SSESession {
    let connection: NWConnection
    let sessionId: String

    init(connection: NWConnection, sessionId: String) {
        self.connection = connection
        self.sessionId = sessionId
    }

    func sendEvent(data: String, event: String? = nil) {
        var message = ""
        if let event = event {
            message += "event: \(event)\n"
        }
        message += "data: \(data)\n\n"
        if let eventData = message.data(using: .utf8) {
            connection.send(content: eventData, completion: .contentProcessed { _ in })
        }
    }

    func close() {
        connection.cancel()
    }
}
