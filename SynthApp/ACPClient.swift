import Foundation

// MARK: - JSON-RPC Types

struct JsonRpcRequest: Codable {
    let jsonrpc: String
    let id: Int
    let method: String
    let params: [String: AnyCodable]?

    init(id: Int, method: String, params: [String: AnyCodable]? = nil) {
        self.jsonrpc = "2.0"
        self.id = id
        self.method = method
        self.params = params
    }
}

struct JsonRpcNotification: Codable {
    let jsonrpc: String
    let method: String
    let params: [String: AnyCodable]?
}

struct JsonRpcResponse: Codable {
    let jsonrpc: String
    let id: Int?
    let result: AnyCodable?
    let error: JsonRpcError?
}

struct JsonRpcError: Codable {
    let code: Int
    let message: String
}

// MARK: - ACP Types

struct SessionUpdate: Codable {
    let kind: String
    let content: AnyCodable?
}

// MARK: - AnyCodable Helper

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            value = str
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict
        } else if let arr = try? container.decode([AnyCodable].self) {
            value = arr
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let str as String: try container.encode(str)
        case let int as Int: try container.encode(int)
        case let bool as Bool: try container.encode(bool)
        case let dict as [String: AnyCodable]: try container.encode(dict)
        case let arr as [AnyCodable]: try container.encode(arr)
        default: try container.encodeNil()
        }
    }

    var stringValue: String? { value as? String }
    var dictValue: [String: AnyCodable]? { value as? [String: AnyCodable] }
}

// MARK: - ACP Client

class ACPClient: ObservableObject {
    private var process: Process?
    private var stdin: FileHandle?
    private var stdout: FileHandle?
    private var requestId = 0
    private var pendingRequests: [Int: (Result<AnyCodable?, Error>) -> Void] = [:]
    private var buffer = Data()

    @Published var isConnected = false
    @Published var sessionId: String?
    @Published var connectionFailed = false

    var onUpdate: ((String) -> Void)?
    var onFileWrite: ((String, String) -> Void)?

    func start() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["kiro-cli", "acp"]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice

        self.stdin = stdinPipe.fileHandleForWriting
        self.stdout = stdoutPipe.fileHandleForReading

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.handleData(data)
        }

        do {
            try process.run()
            self.process = process
            initialize()

            // Timeout after 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                if self?.isConnected == false {
                    self?.connectionFailed = true
                }
            }
        } catch {
            print("Failed to start kiro-cli: \(error)")
            DispatchQueue.main.async {
                self.connectionFailed = true
            }
        }
    }

    func stop() {
        process?.terminate()
        process = nil
        stdin = nil
        stdout = nil
        isConnected = false
        sessionId = nil
    }

    private func handleData(_ data: Data) {
        buffer.append(data)

        while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = buffer[..<newlineIndex]
            buffer = buffer[(newlineIndex + 1)...]

            guard let line = String(data: lineData, encoding: .utf8), !line.isEmpty else { continue }
            processMessage(line)
        }
    }

    private func processMessage(_ json: String) {
        guard let data = json.data(using: .utf8) else { return }

        // Try as notification first
        if let notification = try? JSONDecoder().decode(JsonRpcNotification.self, from: data) {
            handleNotification(notification)
            return
        }

        // Try as response
        if let response = try? JSONDecoder().decode(JsonRpcResponse.self, from: data),
           let id = response.id,
           let handler = pendingRequests.removeValue(forKey: id) {
            if let error = response.error {
                handler(.failure(NSError(domain: "ACP", code: error.code, userInfo: [NSLocalizedDescriptionKey: error.message])))
            } else {
                handler(.success(response.result))
            }
        }
    }

    private func handleNotification(_ notification: JsonRpcNotification) {
        switch notification.method {
        case "session/update":
            if let params = notification.params,
               let kind = params["kind"]?.stringValue {
                handleSessionUpdate(kind: kind, params: params)
            }
        default:
            break
        }
    }

    private func handleSessionUpdate(kind: String, params: [String: AnyCodable]) {
        switch kind {
        case "message_chunk":
            if let chunk = params["chunk"]?.dictValue,
               let text = chunk["text"]?.stringValue {
                DispatchQueue.main.async {
                    self.onUpdate?(text)
                }
            }
        case "tool_call":
            // Could show tool calls in UI
            break
        default:
            break
        }
    }

    private func sendRequest(method: String, params: [String: AnyCodable]? = nil, completion: @escaping (Result<AnyCodable?, Error>) -> Void) {
        requestId += 1
        let request = JsonRpcRequest(id: requestId, method: method, params: params)
        pendingRequests[requestId] = completion

        guard let data = try? JSONEncoder().encode(request),
              var json = String(data: data, encoding: .utf8) else {
            completion(.failure(NSError(domain: "ACP", code: -1, userInfo: [NSLocalizedDescriptionKey: "Encoding failed"])))
            return
        }

        json += "\n"
        stdin?.write(json.data(using: .utf8)!)
    }

    // MARK: - ACP Methods

    private func initialize() {
        let params: [String: AnyCodable] = [
            "client_info": AnyCodable([
                "name": AnyCodable("Synth"),
                "version": AnyCodable("1.0.0")
            ]),
            "capabilities": AnyCodable([
                "fs": AnyCodable([
                    "readTextFile": AnyCodable(true),
                    "writeTextFile": AnyCodable(true)
                ])
            ])
        ]

        sendRequest(method: "initialize", params: params) { [weak self] result in
            switch result {
            case .success:
                DispatchQueue.main.async {
                    self?.isConnected = true
                }
                self?.createSession()
            case .failure(let error):
                print("Initialize failed: \(error)")
            }
        }
    }

    private func createSession() {
        sendRequest(method: "session/new") { [weak self] result in
            if case .success(let response) = result,
               let dict = response?.dictValue,
               let id = dict["session_id"]?.stringValue {
                DispatchQueue.main.async {
                    self?.sessionId = id
                }
            }
        }
    }

    func sendPrompt(_ text: String, filePath: String? = nil) {
        var content = text
        if let path = filePath {
            content = "Working on file: \(path)\n\n\(text)"
        }

        let params: [String: AnyCodable] = [
            "session_id": AnyCodable(sessionId ?? ""),
            "content": AnyCodable([
                AnyCodable([
                    "type": AnyCodable("text"),
                    "text": AnyCodable(content)
                ])
            ])
        ]

        sendRequest(method: "session/prompt", params: params) { _ in
            // Response indicates turn complete
        }
    }
}
