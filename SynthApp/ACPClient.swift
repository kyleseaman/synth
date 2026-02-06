import Foundation

// swiftlint:disable:next type_body_length
class ACPClient: ObservableObject {
    private var process: Process?
    private var stdin: FileHandle?
    private var requestId = 0
    private var pendingRequests: [Int: (Result<AnyCodable?, Error>) -> Void] = [:]
    private var buffer = Data()
    private let queue = DispatchQueue(label: "com.synth.acp.\(UUID().uuidString)")
    private var cwd: String = ""
    private var agent: String?

    @Published var isConnected = false
    @Published var sessionId: String?
    @Published var connectionFailed = false
    @Published var toolCalls: [ACPToolCall] = []

    var onUpdate: ((String) -> Void)?
    var onTurnComplete: (() -> Void)?
    var onFileWrite: ((String, String) -> Void)?
    var onFileRead: ((String) -> String?)?
    var onToolCall: ((ACPToolCall) -> Void)?
    var onToolCallUpdate: ((String, String) -> Void)?

    // swiftlint:disable:next function_body_length
    func start(cwd: String, agent: String? = nil) {
        self.cwd = cwd
        self.agent = agent
        let proc = Process()

        if let path = KiroCliResolver.resolve() {
            print("[ACP] Using kiro-cli at: \(path)")
            proc.executableURL = URL(fileURLWithPath: path)
            proc.arguments = ["acp"]
        } else {
            print("[ACP] No kiro-cli found, falling back to /usr/bin/env")
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            proc.arguments = ["kiro-cli", "acp"]
        }

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardInput = stdinPipe
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        self.stdin = stdinPipe.fileHandleForWriting

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                print("[ACP] stdout EOF")
                return
            }
            if let str = String(data: data, encoding: .utf8) {
                print("[ACP] stdout: \(str.prefix(500))")
            }
            self?.handleData(data)
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                print("[ACP] stderr: \(str.prefix(500))")
            }
        }

        do {
            try proc.run()
            self.process = proc
            print("[ACP] Process launched, pid=\(proc.processIdentifier)")
            initialize()

            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                if self?.isConnected == false {
                    print("[ACP] Connection timeout — not connected after 8s")
                    self?.connectionFailed = true
                }
            }
        } catch {
            print("[ACP] Failed to launch process: \(error)")
            DispatchQueue.main.async { self.connectionFailed = true }
        }
    }

    func stop() {
        process?.terminate()
        process = nil
        stdin = nil
        DispatchQueue.main.async {
            self.isConnected = false
            self.sessionId = nil
        }
    }

    // MARK: - Data Handling

    private func handleData(_ data: Data) {
        queue.sync { buffer.append(data) }

        while true {
            let lineData: Data? = queue.sync {
                guard let idx = buffer.firstIndex(of: UInt8(ascii: "\n")) else { return nil }
                let line = Data(buffer[..<idx])
                buffer = buffer[(idx + 1)...]
                return line
            }
            guard let data = lineData,
                  let line = String(data: data, encoding: .utf8),
                  !line.isEmpty else { break }
            processMessage(line)
        }
    }

    private func processMessage(_ json: String) {
        guard let data = json.data(using: .utf8) else { return }

        // Try as incoming request from agent (bidirectional: has method + id)
        if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let method = dict["method"] as? String,
           let reqId = dict["id"] as? Int {
            handleIncomingRequest(id: reqId, method: method, params: dict["params"] as? [String: Any])
            return
        }

        // Try as notification (has method, no id)
        if let notification = try? JSONDecoder().decode(JsonRpcNotification.self, from: data),
           notification.method == "session/update" {
            handleSessionUpdate(notification.params)
            return
        }

        // Try as response to our request
        if let response = try? JSONDecoder().decode(JsonRpcResponse.self, from: data),
           let reqId = response.id {
            let handler = queue.sync { pendingRequests.removeValue(forKey: reqId) }
            if let handler = handler {
                if let error = response.error {
                    let nsError = NSError(
                        domain: "ACP", code: error.code,
                        userInfo: [NSLocalizedDescriptionKey: error.message]
                    )
                    DispatchQueue.main.async { handler(.failure(nsError)) }
                } else {
                    DispatchQueue.main.async { handler(.success(response.result)) }
                }
            }
        }
    }

    // MARK: - Incoming Requests from Agent

    private func handleIncomingRequest(id: Int, method: String, params: [String: Any]?) {
        switch method {
        case "fs/read_text_file":
            let path = params?["path"] as? String ?? ""
            let content = onFileRead?(path) ?? ""
            sendResponse(id: id, result: AnyCodable(["content": AnyCodable(content)]))

        case "fs/write_text_file":
            let path = params?["path"] as? String ?? ""
            let content = params?["content"] as? String ?? ""
            DispatchQueue.main.async { self.onFileWrite?(path, content) }
            sendResponse(id: id, result: nil)

        case "session/request_permission":
            // Auto-allow: find first allow option
            var optionId = "allow-once"
            if let options = params?["options"] as? [[String: Any]] {
                for option in options {
                    if let kind = option["kind"] as? String, kind.hasPrefix("allow"),
                       let oid = option["optionId"] as? String {
                        optionId = oid
                        break
                    }
                }
            }
            sendResponse(id: id, result: AnyCodable([
                "outcome": AnyCodable([
                    "outcome": AnyCodable("selected"),
                    "optionId": AnyCodable(optionId)
                ])
            ]))

        default:
            // Unknown method — respond with error
            sendErrorResponse(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    // MARK: - Session Update Handling

    private func handleSessionUpdate(_ params: [String: AnyCodable]?) {
        guard let update = params?["update"]?.dictValue,
              let kind = update["sessionUpdate"]?.stringValue else { return }

        switch kind {
        case "agent_message_chunk":
            if let content = update["content"]?.dictValue,
               let text = content["text"]?.stringValue {
                DispatchQueue.main.async { self.onUpdate?(text) }
            }

        case "tool_call":
            if let toolCallId = update["toolCallId"]?.stringValue,
               let title = update["title"]?.stringValue {
                let toolKind = update["kind"]?.stringValue ?? "other"
                let status = update["status"]?.stringValue ?? "pending"
                let call = ACPToolCall(id: toolCallId, title: title, kind: toolKind, status: status)
                DispatchQueue.main.async {
                    self.toolCalls.append(call)
                    self.onToolCall?(call)
                }
            }

        case "tool_call_update":
            if let toolCallId = update["toolCallId"]?.stringValue {
                let status = update["status"]?.stringValue ?? "in_progress"
                DispatchQueue.main.async {
                    if let idx = self.toolCalls.firstIndex(where: { $0.id == toolCallId }) {
                        self.toolCalls[idx].status = status
                    }
                    self.onToolCallUpdate?(toolCallId, status)
                }
            }

        default:
            break
        }
    }

    // MARK: - Send Helpers

    private func sendRequest(
        method: String,
        params: [String: AnyCodable]? = nil,
        completion: @escaping (Result<AnyCodable?, Error>) -> Void
    ) {
        let currentId = queue.sync { () -> Int in
            requestId += 1
            pendingRequests[requestId] = completion
            return requestId
        }

        queue.asyncAfter(deadline: .now() + 60) { [weak self] in
            guard let self = self else { return }
            let handler = self.pendingRequests.removeValue(forKey: currentId)
            if let handler = handler {
                let err = NSError(
                    domain: "ACP", code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "Request timed out"]
                )
                DispatchQueue.main.async { handler(.failure(err)) }
            }
        }

        let request = JsonRpcRequest(id: currentId, method: method, params: params)
        writeMessage(request)
    }

    private func sendResponse(id: Int, result: AnyCodable?) {
        var dict: [String: Any] = ["jsonrpc": "2.0", "id": id]
        if let result = result {
            dict["result"] = encodeAnyCodable(result)
        } else {
            dict["result"] = NSNull()
        }
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              var json = String(data: data, encoding: .utf8) else { return }
        json += "\n"
        if let writeData = json.data(using: .utf8) { stdin?.write(writeData) }
    }

    private func sendErrorResponse(id: Int, code: Int, message: String) {
        let dict: [String: Any] = [
            "jsonrpc": "2.0", "id": id,
            "error": ["code": code, "message": message]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              var json = String(data: data, encoding: .utf8) else { return }
        json += "\n"
        if let writeData = json.data(using: .utf8) { stdin?.write(writeData) }
    }

    private func sendNotification(method: String, params: [String: AnyCodable]) {
        let notification = JsonRpcNotification(jsonrpc: "2.0", method: method, params: params)
        guard let data = try? JSONEncoder().encode(notification),
              var json = String(data: data, encoding: .utf8) else { return }
        json += "\n"
        if let writeData = json.data(using: .utf8) { stdin?.write(writeData) }
    }

    private func writeMessage<T: Encodable>(_ message: T) {
        guard let data = try? JSONEncoder().encode(message),
              var json = String(data: data, encoding: .utf8) else { return }
        json += "\n"
        print("[ACP] >>> \(json.prefix(300))")
        if let writeData = json.data(using: .utf8) { stdin?.write(writeData) }
    }

    private func encodeAnyCodable(_ value: AnyCodable) -> Any {
        switch value.value {
        case let str as String: return str
        case let int as Int: return int
        case let dbl as Double: return dbl
        case let bool as Bool: return bool
        case let dict as [String: AnyCodable]:
            return dict.mapValues { encodeAnyCodable($0) }
        case let arr as [AnyCodable]:
            return arr.map { encodeAnyCodable($0) }
        default: return NSNull()
        }
    }

    // MARK: - ACP Protocol Methods

    private func initialize() {
        let params: [String: AnyCodable] = [
            "protocolVersion": AnyCodable(1),
            "version": AnyCodable(1),
            "clientCapabilities": AnyCodable([
                "fs": AnyCodable([
                    "readTextFile": AnyCodable(true),
                    "writeTextFile": AnyCodable(true)
                ]),
                "terminal": AnyCodable(false)
            ]),
            "clientInfo": AnyCodable([
                "name": AnyCodable("synth"),
                "title": AnyCodable("Synth"),
                "version": AnyCodable("1.0.0")
            ])
        ]

        print("[ACP] Sending initialize...")
        sendRequest(method: "initialize", params: params) { [weak self] result in
            switch result {
            case .success(let response):
                print("[ACP] Initialize succeeded: \(String(describing: response))")
                DispatchQueue.main.async { self?.isConnected = true }
                self?.createSession()
            case .failure(let error):
                print("[ACP] Initialize failed: \(error)")
                DispatchQueue.main.async { self?.connectionFailed = true }
            }
        }
    }

    private func createSession() {
        var params: [String: AnyCodable] = [
            "cwd": AnyCodable(cwd),
            "mcpServers": AnyCodable([AnyCodable]())
        ]
        if let agent = agent {
            params["agent"] = AnyCodable(agent)
        }

        print("[ACP] Sending session/new with cwd=\(cwd), agent=\(agent ?? "default")")
        sendRequest(method: "session/new", params: params) { [weak self] result in
            if case .success(let response) = result,
               let dict = response?.dictValue,
               let sid = dict["sessionId"]?.stringValue {
                print("[ACP] Session created: \(sid)")
                DispatchQueue.main.async { self?.sessionId = sid }
            } else {
                print("[ACP] session/new response: \(result)")
            }
        }
    }

    func sendPrompt(_ contentBlocks: [[String: AnyCodable]]) {
        guard let sid = sessionId else { return }

        let params: [String: AnyCodable] = [
            "sessionId": AnyCodable(sid),
            "prompt": AnyCodable(contentBlocks.map { AnyCodable($0) })
        ]

        toolCalls.removeAll()

        sendRequest(method: "session/prompt", params: params) { [weak self] _ in
            DispatchQueue.main.async { self?.onTurnComplete?() }
        }
    }

    func sendCancel() {
        guard let sid = sessionId else { return }
        sendNotification(method: "session/cancel", params: [
            "sessionId": AnyCodable(sid)
        ])
    }
}
