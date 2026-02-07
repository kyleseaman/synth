import Foundation

// MARK: - JSON-RPC 2.0 Types

struct JsonRpcRequest: Codable {
    let jsonrpc: String
    let id: JsonRpcId?
    let method: String
    let params: AnyCodableValue?
}

struct JsonRpcResponse: Codable {
    let jsonrpc: String
    let id: JsonRpcId?
    let result: AnyCodableValue?
    let error: JsonRpcError?

    init(id: JsonRpcId?, result: AnyCodableValue) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = result
        self.error = nil
    }

    init(id: JsonRpcId?, error: JsonRpcError) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = nil
        self.error = error
    }
}

struct JsonRpcError: Codable {
    let code: Int
    let message: String
}

enum JsonRpcId: Codable, Equatable {
    case int(Int)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) {
            self = .int(intVal)
        } else if let strVal = try? container.decode(String.self) {
            self = .string(strVal)
        } else {
            throw DecodingError.typeMismatch(
                JsonRpcId.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected Int or String")
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let val): try container.encode(val)
        case .string(let val): try container.encode(val)
        }
    }
}

// MARK: - Flexible JSON Value

enum AnyCodableValue: Codable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([AnyCodableValue])
    case object([String: AnyCodableValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let val = try? container.decode(Bool.self) {
            self = .bool(val)
        } else if let val = try? container.decode(Int.self) {
            self = .int(val)
        } else if let val = try? container.decode(Double.self) {
            self = .double(val)
        } else if let val = try? container.decode(String.self) {
            self = .string(val)
        } else if let val = try? container.decode([AnyCodableValue].self) {
            self = .array(val)
        } else if let val = try? container.decode([String: AnyCodableValue].self) {
            self = .object(val)
        } else {
            throw DecodingError.typeMismatch(
                AnyCodableValue.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported type")
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let val): try container.encode(val)
        case .int(let val): try container.encode(val)
        case .double(let val): try container.encode(val)
        case .string(let val): try container.encode(val)
        case .array(let val): try container.encode(val)
        case .object(let val): try container.encode(val)
        }
    }

    var stringValue: String? {
        if case .string(let val) = self { return val }
        return nil
    }

    var intValue: Int? {
        if case .int(let val) = self { return val }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let val) = self { return val }
        return nil
    }

    var arrayValue: [AnyCodableValue]? {
        if case .array(let val) = self { return val }
        return nil
    }

    var objectValue: [String: AnyCodableValue]? {
        if case .object(let val) = self { return val }
        return nil
    }

    subscript(key: String) -> AnyCodableValue? {
        if case .object(let dict) = self { return dict[key] }
        return nil
    }
}

// MARK: - MCP Protocol Handler

class MCPProtocolHandler {
    let toolRouter: ToolRouter

    init(toolRouter: ToolRouter) {
        self.toolRouter = toolRouter
    }

    func handleMessage(_ data: Data) -> Data? {
        guard let request = try? JSONDecoder().decode(JsonRpcRequest.self, from: data) else {
            let errorResponse = JsonRpcResponse(
                id: nil,
                error: JsonRpcError(code: -32700, message: "Parse error")
            )
            return try? JSONEncoder().encode(errorResponse)
        }

        // Notifications (no id) don't get responses
        if request.id == nil {
            handleNotification(request)
            return nil
        }

        let response = handleRequest(request)
        return try? JSONEncoder().encode(response)
    }

    private func handleNotification(_ request: JsonRpcRequest) {
        // Handle notifications like initialized, cancelled, etc.
        switch request.method {
        case "notifications/initialized":
            log("Client initialized")
        default:
            break
        }
    }

    private func handleRequest(_ request: JsonRpcRequest) -> JsonRpcResponse {
        switch request.method {
        case "initialize":
            return handleInitialize(id: request.id)
        case "tools/list":
            return handleToolsList(id: request.id)
        case "tools/call":
            return handleToolsCall(id: request.id, params: request.params)
        case "ping":
            return JsonRpcResponse(id: request.id, result: .object([:]))
        default:
            return JsonRpcResponse(
                id: request.id,
                error: JsonRpcError(code: -32601, message: "Method not found: \(request.method)")
            )
        }
    }

    private func handleInitialize(id: JsonRpcId?) -> JsonRpcResponse {
        let result: AnyCodableValue = .object([
            "protocolVersion": .string("2024-11-05"),
            "capabilities": .object([
                "tools": .object([:])
            ]),
            "serverInfo": .object([
                "name": .string("synth-mcp-server"),
                "version": .string("0.1.0")
            ])
        ])
        return JsonRpcResponse(id: id, result: result)
    }

    private func handleToolsList(id: JsonRpcId?) -> JsonRpcResponse {
        let tools = toolRouter.listTools()
        let result: AnyCodableValue = .object([
            "tools": .array(tools)
        ])
        return JsonRpcResponse(id: id, result: result)
    }

    private func handleToolsCall(id: JsonRpcId?, params: AnyCodableValue?) -> JsonRpcResponse {
        guard let params = params?.objectValue,
              let name = params["name"]?.stringValue else {
            return JsonRpcResponse(
                id: id,
                error: JsonRpcError(code: -32602, message: "Missing tool name")
            )
        }

        let arguments = params["arguments"]?.objectValue ?? [:]
        let result = toolRouter.callTool(name: name, arguments: arguments)
        return JsonRpcResponse(id: id, result: result)
    }
}
