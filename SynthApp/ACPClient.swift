import Foundation
import Observation

@MainActor
@Observable final class ACPClient: @unchecked Sendable {
    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var stdin: FileHandle?
    @ObservationIgnored private var requestId = 0
    @ObservationIgnored private var pendingRequests: [Int: (Result<AnyCodable?, Error>) -> Void] = [:]
    @ObservationIgnored private var buffer = Data()
    @ObservationIgnored private let queue = DispatchQueue(label: "com.synth.acp.\(UUID().uuidString)")
    @ObservationIgnored private var cwd: String = ""
    @ObservationIgnored private var agent: String?
    @ObservationIgnored private var lastToolCallDiff: [String: DiffContent] = [:]
    @ObservationIgnored private var lastToolCallLocations: [String: [String]] = [:]
    @ObservationIgnored private var pendingPromptRequest = false
    @ObservationIgnored var mcpServerManager: MCPServerManager?
    @ObservationIgnored private var isLoadingSession = false

    var isConnected = false
    var sessionId: String?
    var connectionFailed = false
    var toolCalls: [ACPToolCall] = []
    var pendingPermission: ACPPermissionRequest?
    var supportsLoadSession = false
    var availableCommands: [ACPSlashCommand] = []
    var availableModes: [ACPSessionMode] = []
    var currentModeId: String?

    // MARK: - Callbacks

    @ObservationIgnored var onUpdate: ((String) -> Void)?
    @ObservationIgnored var onTurnComplete: (() -> Void)?
    @ObservationIgnored var onFileWrite: ((String, String) -> Void)?
    @ObservationIgnored var onFileRead: ((String) -> String?)?
    @ObservationIgnored var onToolCall: ((ACPToolCall) -> Void)?
    @ObservationIgnored var onToolCallUpdate: ((String, String) -> Void)?
    @ObservationIgnored var onEditToolCompleted: ((String, [String]) -> Void)?
    @ObservationIgnored var onPermissionRequest: ((ACPPermissionRequest) -> Void)?
    @ObservationIgnored var onError: ((String) -> Void)?
    @ObservationIgnored var onUserMessageReplay: ((String) -> Void)?
    @ObservationIgnored var onSessionReady: ((String) -> Void)?
    @ObservationIgnored var onSessionLoadFailed: (() -> Void)?
    @ObservationIgnored var onOAuthRequest: ((URL) -> Void)?
    @ObservationIgnored var onCompactionStatus: ((String) -> Void)?
    @ObservationIgnored var onClearStatus: ((String) -> Void)?
    @ObservationIgnored var onMcpServerInitialized: ((String) -> Void)?

    func start(cwd: String, agent: String? = nil) {
        self.cwd = cwd
        self.agent = agent
        connectionFailed = false
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
            Task { @MainActor [weak self] in
                self?.handleData(data)
            }
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
            connectionFailed = true
        }
    }

    func stop() {
        process?.terminate()
        process = nil
        stdin = nil
        isConnected = false
        sessionId = nil
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
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        let method = dict["method"] as? String
        let hasId = dict["id"] != nil

        // Incoming request from agent (has method + id)
        if let method, hasId {
            let idString = "\(dict["id"]!)"
            handleIncomingRequest(
                id: idString,
                method: method,
                params: dict["params"] as? [String: Any]
            )
            return
        }

        // Notification (has method, no id)
        if let method, !hasId {
            handleNotification(method: method, data: data)
            return
        }

        // Response to our request (has id, no method)
        if let response = try? JSONDecoder().decode(JsonRpcResponse.self, from: data),
           let reqId = response.id {
            let handler = queue.sync { pendingRequests.removeValue(forKey: reqId) }
            if let handler = handler {
                if let error = response.error {
                    let nsError = NSError(
                        domain: "ACP", code: error.code,
                        userInfo: [NSLocalizedDescriptionKey: error.message]
                    )
                    handler(.failure(nsError))
                } else {
                    handler(.success(response.result))
                }
            }
        }
    }

    // MARK: - Notification Router

    private func handleNotification(method: String, data: Data) {
        switch method {
        case "session/update", "session/notification":
            if let notification = try? JSONDecoder().decode(JsonRpcNotification.self, from: data) {
                handleSessionUpdate(notification.params)
            }

        case "_kiro.dev/mcp/oauth_request":
            if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let params = dict["params"] as? [String: Any],
               let urlString = params["url"] as? String,
               let url = URL(string: urlString) {
                print("[ACP] OAuth request: \(urlString)")
                onOAuthRequest?(url)
            }

        case "_kiro.dev/mcp/server_initialized":
            if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let params = dict["params"] as? [String: Any] {
                let name = params["name"] as? String
                    ?? params["serverName"] as? String
                    ?? params["server_name"] as? String
                    ?? "MCP Server"
                print("[ACP] MCP server initialized: \(name)")
                onMcpServerInitialized?(name)
            }

        case "_kiro.dev/compaction/status":
            if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let params = dict["params"] as? [String: Any] {
                let status = params["status"] as? String ?? "in_progress"
                print("[ACP] Compaction status: \(status)")
                onCompactionStatus?(status)
            }

        case "_kiro.dev/clear/status":
            if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let params = dict["params"] as? [String: Any] {
                let status = params["status"] as? String ?? "in_progress"
                print("[ACP] Clear status: \(status)")
                onClearStatus?(status)
            }

        case "_session/terminate":
            print("[ACP] Session terminate received")
            stop()

        default:
            if method.hasPrefix("_kiro.dev/") || method.hasPrefix("_session/") {
                print("[ACP] Unhandled extension notification: \(method)")
            }
        }
    }

    // MARK: - Incoming Requests from Agent

    private func handleIncomingRequest(id: String, method: String, params: [String: Any]?) {
        switch method {
        case "fs/read_text_file":
            let path = params?["path"] as? String ?? ""
            let content = onFileRead?(path) ?? ""
            sendResponse(id: id, result: AnyCodable(["content": AnyCodable(content)]))

        case "fs/write_text_file":
            let path = params?["path"] as? String ?? ""
            let content = params?["content"] as? String ?? ""
            onFileWrite?(path, content)
            sendResponse(id: id, result: nil)

        case "session/request_permission":
            print("[ACP] Permission request received, id=\(id)")
            let toolCall = params?["toolCall"] as? [String: Any]
            let toolCallId = toolCall?["toolCallId"] as? String ?? ""
            let title = toolCall?["title"] as? String ?? "Permission requested"
            var opts: [PermissionOption] = []
            if let options = params?["options"] as? [[String: Any]] {
                for opt in options {
                    if let oid = opt["optionId"] as? String,
                       let name = opt["name"] as? String {
                        let kind = opt["kind"] as? String ?? "other"
                        opts.append(PermissionOption(id: oid, label: name, kind: kind))
                    }
                }
            }
            var request = ACPPermissionRequest(
                id: id, toolCallId: toolCallId, title: title, options: opts, diffContent: nil
            )
            request.diffContent = self.lastToolCallDiff[toolCallId]
            print("[ACP] Setting pendingPermission: \(title), hasDiff=\(request.diffContent != nil)")
            pendingPermission = request
            onPermissionRequest?(request)

        default:
            sendErrorResponse(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    func respondToPermission(optionId: String) {
        guard let req = pendingPermission else { return }
        sendResponse(id: req.id, result: AnyCodable([
            "outcome": AnyCodable([
                "outcome": AnyCodable("selected"),
                "optionId": AnyCodable(optionId)
            ])
        ]))
        pendingPermission = nil
    }

    // MARK: - Session Update Handling

    private func handleSessionUpdate(_ params: [String: AnyCodable]?) {
        guard let update = params?["update"]?.dictValue,
              let rawKind = update["sessionUpdate"]?.stringValue ?? update["type"]?.stringValue,
              let kind = ACPProtocolAdapter.parseUpdateKind(rawKind) else { return }

        switch kind {
        case .agentMessageChunk:
            if let content = update["content"]?.dictValue,
               let text = content["text"]?.stringValue {
                onUpdate?(text)
            } else if let text = update["text"]?.stringValue {
                onUpdate?(text)
            }

        case .userMessageChunk:
            if let content = update["content"]?.dictValue,
               let text = content["text"]?.stringValue {
                onUserMessageReplay?(text)
            } else if let text = update["text"]?.stringValue {
                onUserMessageReplay?(text)
            }

        case .toolCall:
            if let toolCallId = update["toolCallId"]?.stringValue,
               let title = update["title"]?.stringValue {
                let toolKind = update["kind"]?.stringValue ?? "other"
                let status = update["status"]?.stringValue ?? "pending"
                let call = ACPToolCall(id: toolCallId, title: title, kind: toolKind, status: status)
                if let content = update["content"]?.arrayValue,
                   let first = content.first?.dictValue,
                   first["type"]?.stringValue == "diff",
                   let path = first["path"]?.stringValue,
                   let oldText = first["oldText"]?.stringValue,
                   let newText = first["newText"]?.stringValue {
                    self.lastToolCallDiff[toolCallId] = DiffContent(
                        oldText: oldText, newText: newText, path: path
                    )
                }
                let locationPaths = Self.locationPaths(from: update)
                if !locationPaths.isEmpty {
                    self.lastToolCallLocations[toolCallId] = locationPaths
                }
                toolCalls.append(call)
                onToolCall?(call)
            }

        case .toolCallUpdate:
            if let toolCallId = update["toolCallId"]?.stringValue {
                let status = update["status"]?.stringValue ?? "in_progress"
                let updateLocationPaths = Self.locationPaths(from: update)
                if !updateLocationPaths.isEmpty {
                    let previousPaths = lastToolCallLocations[toolCallId] ?? []
                    lastToolCallLocations[toolCallId] = Self.mergeUniquePaths(
                        previousPaths + updateLocationPaths
                    )
                }
                if let idx = toolCalls.firstIndex(where: { $0.id == toolCallId }) {
                    toolCalls[idx].status = status
                }
                onToolCallUpdate?(toolCallId, status)

                let toolKind = update["kind"]?.stringValue
                    ?? toolCalls.first(where: { $0.id == toolCallId })?.kind
                    ?? "other"
                if status == "completed", toolKind == "edit" {
                    let locationPaths = lastToolCallLocations[toolCallId] ?? updateLocationPaths
                    if !locationPaths.isEmpty {
                        onEditToolCompleted?(toolCallId, locationPaths)
                    }
                }

                let isTerminalStatus = status == "completed"
                    || status == "failed"
                    || status == "cancelled"
                if isTerminalStatus {
                    lastToolCallLocations.removeValue(forKey: toolCallId)
                    lastToolCallDiff.removeValue(forKey: toolCallId)
                    if pendingPermission?.toolCallId == toolCallId {
                        pendingPermission = nil
                    }
                }
            }

        case .turnEnd:
            finishTurnIfNeeded()

        case .availableCommandsUpdate:
            if let commands = update["availableCommands"]?.arrayValue {
                availableCommands = commands.compactMap { entry in
                    guard let dict = entry.dictValue,
                          let name = dict["name"]?.stringValue,
                          let desc = dict["description"]?.stringValue else { return nil }
                    let hint = dict["input"]?.dictValue?["hint"]?.stringValue
                    return ACPSlashCommand(name: name, description: desc, inputHint: hint)
                }
                print("[ACP] Available commands updated: \(availableCommands.map(\.name))")
            }

        case .currentModeUpdate:
            if let modeId = update["modeId"]?.stringValue {
                currentModeId = modeId
                print("[ACP] Mode updated to: \(modeId)")
            }
        }
    }

    nonisolated static func locationPaths(from update: [String: AnyCodable]) -> [String] {
        guard let locations = update["locations"]?.arrayValue else { return [] }
        var parsedPaths: [String] = []
        var seenPaths: Set<String> = []
        for locationEntry in locations {
            guard let locationDict = locationEntry.dictValue,
                  let filePath = locationDict["path"]?.stringValue,
                  !filePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            if seenPaths.insert(filePath).inserted {
                parsedPaths.append(filePath)
            }
        }
        return parsedPaths
    }

    nonisolated private static func mergeUniquePaths(_ paths: [String]) -> [String] {
        var uniquePaths: [String] = []
        var seenPaths: Set<String> = []
        for filePath in paths where seenPaths.insert(filePath).inserted {
            uniquePaths.append(filePath)
        }
        return uniquePaths
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

        Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard let self = self else { return }
            let handler = self.queue.sync { self.pendingRequests.removeValue(forKey: currentId) }
            if let handler = handler {
                let err = NSError(
                    domain: "ACP", code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "Request timed out"]
                )
                handler(.failure(err))
            }
        }

        let request = JsonRpcRequest(id: currentId, method: method, params: params)
        writeMessage(request)
    }

    private func sendResponse(id: String, result: AnyCodable?) {
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

    private func sendErrorResponse(id: String, code: Int, message: String) {
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
                if let caps = response?.dictValue?["agentCapabilities"]?.dictValue {
                    self?.supportsLoadSession = caps["loadSession"]?.value as? Bool ?? false
                }
                self?.isConnected = true
            case .failure(let error):
                print("[ACP] Initialize failed: \(error)")
                self?.connectionFailed = true
            }
        }
    }

    func createSession() {
        var params: [String: AnyCodable] = [
            "cwd": AnyCodable(cwd),
            "mcpServers": AnyCodable(buildMcpServerConfigs())
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
                self?.sessionId = sid
                self?.parseModes(from: dict)
                self?.onSessionReady?(sid)
            } else {
                print("[ACP] session/new response: \(result)")
                self?.connectionFailed = true
                self?.onError?("Failed to create session with kiro-cli.")
            }
        }
    }

    func loadSession(sessionId: String) {
        isLoadingSession = true
        let params: [String: AnyCodable] = [
            "sessionId": AnyCodable(sessionId),
            "cwd": AnyCodable(cwd),
            "mcpServers": AnyCodable(buildMcpServerConfigs())
        ]

        print("[ACP] Sending session/load for \(sessionId)")
        sendRequest(method: "session/load", params: params) { [weak self] result in
            guard let self = self else { return }
            self.isLoadingSession = false
            switch result {
            case .success:
                print("[ACP] Session loaded: \(sessionId)")
                self.sessionId = sessionId
                self.onSessionReady?(sessionId)
            case .failure(let error):
                print("[ACP] session/load failed: \(error), falling back to new session")
                self.onSessionLoadFailed?()
            }
        }
    }

    func setMode(_ modeId: String) {
        guard let sid = sessionId else { return }
        let params: [String: AnyCodable] = [
            "sessionId": AnyCodable(sid),
            "modeId": AnyCodable(modeId)
        ]
        print("[ACP] Sending session/set_mode: \(modeId)")
        sendRequest(method: "session/set_mode", params: params) { result in
            if case .failure(let error) = result {
                print("[ACP] set_mode failed: \(error)")
            }
        }
    }

    private func parseModes(from dict: [String: AnyCodable]) {
        guard let modes = dict["modes"]?.dictValue else { return }
        currentModeId = modes["currentModeId"]?.stringValue
        if let available = modes["availableModes"]?.arrayValue {
            availableModes = available.compactMap { entry in
                guard let modeDict = entry.dictValue,
                      let modeId = modeDict["id"]?.stringValue,
                      let name = modeDict["name"]?.stringValue else { return nil }
                let desc = modeDict["description"]?.stringValue
                return ACPSessionMode(id: modeId, name: name, description: desc)
            }
            print("[ACP] Available modes: \(availableModes.map(\.name))")
        }
    }

    private func buildMcpServerConfigs() -> [AnyCodable] {
        mcpServerManager?.mcpServerConfig(workspace: cwd)?.map { AnyCodable($0) } ?? []
    }

    func sendPrompt(_ contentBlocks: [[String: AnyCodable]]) {
        guard let sid = sessionId else {
            onError?("Kiro session is not ready yet.")
            return
        }

        let params = ACPProtocolAdapter.promptParams(
            sessionId: sid,
            contentBlocks: contentBlocks
        )
        queue.sync { pendingPromptRequest = true }
        toolCalls.removeAll()

        sendRequest(method: "session/prompt", params: params) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success:
                self.finishTurnIfNeeded()
            case .failure(let error):
                self.onError?("Kiro request failed: \(error.localizedDescription)")
                self.finishTurnIfNeeded()
            }
        }
    }

    func sendCancel() {
        guard let sid = sessionId else { return }
        queue.sync { pendingPromptRequest = false }
        sendNotification(method: "session/cancel", params: [
            "sessionId": AnyCodable(sid)
        ])
    }

    private func finishTurnIfNeeded() {
        let shouldFinish = queue.sync { () -> Bool in
            guard pendingPromptRequest else { return false }
            pendingPromptRequest = false
            return true
        }
        guard shouldFinish else { return }
        for idx in toolCalls.indices where toolCalls[idx].status != "completed"
            && toolCalls[idx].status != "failed" {
            toolCalls[idx].status = "completed"
        }
        onTurnComplete?()
    }
}
