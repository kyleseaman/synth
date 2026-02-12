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

    var isConnected = false
    var sessionId: String?
    var connectionFailed = false
    var toolCalls: [ACPToolCall] = []
    var pendingPermission: ACPPermissionRequest?
    var slashCommands: [ACPSlashCommand] = []
    var modeOptions: [ACPModeOption] = []
    var modelOptions: [ACPModelOption] = []
    var currentModeId: String?
    var currentModelId: String?

    @ObservationIgnored var onUpdate: ((String) -> Void)?
    @ObservationIgnored var onTurnComplete: (() -> Void)?
    @ObservationIgnored var onFileWrite: ((String, String) -> Void)?
    @ObservationIgnored var onFileRead: ((String) -> String?)?
    @ObservationIgnored var onToolCall: ((ACPToolCall) -> Void)?
    @ObservationIgnored var onToolCallUpdate: ((String, String) -> Void)?
    @ObservationIgnored var onEditToolCompleted: ((String, [String]) -> Void)?
    @ObservationIgnored var onPermissionRequest: ((ACPPermissionRequest) -> Void)?
    @ObservationIgnored var onSlashCommandsUpdate: (([ACPSlashCommand]) -> Void)?
    @ObservationIgnored var onModesUpdate: (([ACPModeOption], String?) -> Void)?
    @ObservationIgnored var onModelsUpdate: (([ACPModelOption], String?) -> Void)?
    @ObservationIgnored var onError: ((String) -> Void)?

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
        slashCommands = []
        modeOptions = []
        modelOptions = []
        currentModeId = nil
        currentModelId = nil
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
           let reqId = dict["id"] {
            let idString = "\(reqId)"  // Handle both Int and String IDs
            handleIncomingRequest(id: idString, method: method, params: dict["params"] as? [String: Any])
            return
        }

        // Try as notification (has method, no id)
        if let notification = try? JSONDecoder().decode(JsonRpcNotification.self, from: data),
           ACPProtocolAdapter.isSessionUpdateMethod(notification.method) {
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
                    handler(.failure(nsError))
                } else {
                    handler(.success(response.result))
                }
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
            // Unknown method — respond with error
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
        guard let rawUpdate = params?["update"]?.dictValue ?? params else { return }
        let update = rawUpdate["update"]?.dictValue ?? rawUpdate
        guard let rawKind = update["sessionUpdate"]?.stringValue ?? update["type"]?.stringValue,
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
            // Client-originated chunk updates do not need rendering in the assistant stream.
            break

        case .toolCall:
            if let toolCallId = update["toolCallId"]?.stringValue,
               let title = update["title"]?.stringValue {
                let toolKind = update["kind"]?.stringValue ?? "other"
                let status = update["status"]?.stringValue ?? "pending"
                let call = ACPToolCall(id: toolCallId, title: title, kind: toolKind, status: status)
                // Capture diff content if present
                if let content = update["content"]?.arrayValue,
                   let first = content.first?.dictValue,
                   first["type"]?.stringValue == "diff",
                   let path = first["path"]?.stringValue,
                   let oldText = first["oldText"]?.stringValue,
                   let newText = first["newText"]?.stringValue {
                    self.lastToolCallDiff[toolCallId] = DiffContent(oldText: oldText, newText: newText, path: path)
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

        case .availableCommandsUpdate:
            let commands = Self.parseSlashCommands(from: AnyCodable(update))
            slashCommands = commands
            onSlashCommandsUpdate?(commands)

        case .currentModeUpdate:
            let modeIdentifier = update["modeId"]?.stringValue
                ?? update["currentModeId"]?.stringValue
                ?? update["mode"]?.stringValue
            if let modeIdentifier {
                currentModeId = modeIdentifier
                onModesUpdate?(modeOptions, currentModeId)
            }

        case .currentModelUpdate:
            let modelIdentifier = update["modelId"]?.stringValue
                ?? update["currentModelId"]?.stringValue
                ?? update["model"]?.stringValue
            if let modelIdentifier {
                currentModelId = modelIdentifier
                onModelsUpdate?(modelOptions, currentModelId)
            }

        case .mcpServersInitialized, .mcpServerUpdate, .mcpServerResponse:
            // Kiro extension updates are informational for now.
            break

        case .turnEnd:
            finishTurnIfNeeded()
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

    nonisolated static func parseSlashCommands(from result: AnyCodable?) -> [ACPSlashCommand] {
        let root = result?.dictValue
        let commandEntries = root?["commands"]?.arrayValue ?? result?.arrayValue ?? []
        var parsedCommands: [ACPSlashCommand] = []
        var seenIdentifiers: Set<String> = []

        for commandEntry in commandEntries {
            guard let commandDict = commandEntry.dictValue else { continue }
            let commandName = Self.firstString(
                in: commandDict,
                keys: ["name", "command", "id"]
            )
            guard let commandName, !commandName.isEmpty else { continue }
            let commandId = commandDict["id"]?.stringValue ?? commandName
            guard seenIdentifiers.insert(commandId).inserted else { continue }
            parsedCommands.append(
                ACPSlashCommand(
                    id: commandId,
                    name: commandName,
                    description: Self.firstString(in: commandDict, keys: ["description", "detail"]),
                    inputHint: Self.firstString(in: commandDict, keys: ["inputHint", "hint"])
                )
            )
        }

        return parsedCommands
    }

    nonisolated static func parseModes(
        from result: AnyCodable?
    ) -> (options: [ACPModeOption], currentModeId: String?) {
        let root = result?.dictValue
        let modeEntries = root?["modes"]?.arrayValue
            ?? root?["options"]?.arrayValue
            ?? result?.arrayValue
            ?? []
        var parsedOptions: [ACPModeOption] = []
        var seenIdentifiers: Set<String> = []
        var activeModeId = root?["currentModeId"]?.stringValue
            ?? root?["modeId"]?.stringValue

        for modeEntry in modeEntries {
            guard let modeDict = modeEntry.dictValue else { continue }
            let modeId = Self.firstString(in: modeDict, keys: ["id", "modeId", "name", "title"])
            guard let modeId, !modeId.isEmpty else { continue }
            guard seenIdentifiers.insert(modeId).inserted else { continue }

            let modeTitle = Self.firstString(
                in: modeDict,
                keys: ["title", "displayName", "name", "id", "modeId"]
            ) ?? modeId
            parsedOptions.append(ACPModeOption(id: modeId, title: modeTitle))

            if activeModeId == nil, modeDict["current"]?.value as? Bool == true {
                activeModeId = modeId
            }
        }

        return (parsedOptions, activeModeId)
    }

    nonisolated static func parseModels(
        from result: AnyCodable?
    ) -> (options: [ACPModelOption], currentModelId: String?) {
        let root = result?.dictValue
        let modelEntries = root?["models"]?.arrayValue
            ?? root?["options"]?.arrayValue
            ?? result?.arrayValue
            ?? []
        var parsedOptions: [ACPModelOption] = []
        var seenIdentifiers: Set<String> = []
        var activeModelId = root?["currentModelId"]?.stringValue
            ?? root?["modelId"]?.stringValue

        for modelEntry in modelEntries {
            guard let modelDict = modelEntry.dictValue else { continue }
            let modelId = Self.firstString(
                in: modelDict,
                keys: ["id", "modelId", "name", "title", "displayName"]
            )
            guard let modelId, !modelId.isEmpty else { continue }
            guard seenIdentifiers.insert(modelId).inserted else { continue }

            let modelTitle = Self.firstString(
                in: modelDict,
                keys: ["displayName", "title", "name", "id", "modelId"]
            ) ?? modelId
            parsedOptions.append(ACPModelOption(id: modelId, title: modelTitle))

            if activeModelId == nil, modelDict["current"]?.value as? Bool == true {
                activeModelId = modelId
            }
        }

        return (parsedOptions, activeModelId)
    }

    nonisolated private static func firstString(
        in dictionary: [String: AnyCodable],
        keys: [String]
    ) -> String? {
        for key in keys {
            if let rawValue = dictionary[key]?.stringValue {
                let normalizedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !normalizedValue.isEmpty {
                    return normalizedValue
                }
            }
        }
        return nil
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
                self?.isConnected = true
                self?.createSession()
            case .failure(let error):
                print("[ACP] Initialize failed: \(error)")
                self?.connectionFailed = true
            }
        }
    }

    private func createSession() {
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
                self?.refreshSessionInterfaces()
            } else {
                print("[ACP] session/new response: \(result)")
                self?.connectionFailed = true
                self?.onError?("Failed to create session with kiro-cli.")
            }
        }
    }

    private func buildMcpServerConfigs() -> [AnyCodable] {
        mcpServerManager?.mcpServerConfig(workspace: cwd)?.map { AnyCodable($0) } ?? []
    }

    func refreshSessionInterfaces() {
        requestSlashCommands()
        requestModes()
        requestModels()
    }

    func setMode(_ modeId: String) {
        guard let sessionParams = buildSessionParams([
            "modeId": AnyCodable(modeId),
            "mode": AnyCodable(modeId)
        ]) else { return }
        sendRequest(method: "_kiro.dev/set_mode", params: sessionParams) { [weak self] result in
            switch result {
            case .success:
                self?.currentModeId = modeId
                self?.onModesUpdate?(self?.modeOptions ?? [], self?.currentModeId)
            case .failure(let error):
                self?.onError?("Failed to set mode: \(error.localizedDescription)")
            }
        }
    }

    func setModel(_ modelId: String) {
        guard let sessionParams = buildSessionParams([
            "modelId": AnyCodable(modelId),
            "model": AnyCodable(modelId)
        ]) else { return }
        sendRequest(method: "_kiro.dev/set_model", params: sessionParams) { [weak self] result in
            switch result {
            case .success:
                self?.currentModelId = modelId
                self?.onModelsUpdate?(self?.modelOptions ?? [], self?.currentModelId)
            case .failure(let error):
                self?.onError?("Failed to set model: \(error.localizedDescription)")
            }
        }
    }

    func compactSession(completion: ((Bool) -> Void)? = nil) {
        guard let sessionParams = buildSessionParams() else {
            completion?(false)
            return
        }
        sendRequest(method: "_kiro.dev/compact", params: sessionParams) { [weak self] result in
            switch result {
            case .success:
                completion?(true)
            case .failure(let error):
                self?.onError?("Failed to compact session: \(error.localizedDescription)")
                completion?(false)
            }
        }
    }

    func clearSession(completion: ((Bool) -> Void)? = nil) {
        guard let sessionParams = buildSessionParams() else {
            completion?(false)
            return
        }
        sendRequest(method: "_kiro.dev/clear", params: sessionParams) { [weak self] result in
            switch result {
            case .success:
                completion?(true)
            case .failure(let error):
                self?.onError?("Failed to clear session: \(error.localizedDescription)")
                completion?(false)
            }
        }
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

    private func requestSlashCommands() {
        guard let sessionParams = buildSessionParams() else { return }
        sendRequest(method: "_kiro.dev/list_commands", params: sessionParams) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let response):
                let commands = Self.parseSlashCommands(from: response)
                self.slashCommands = commands
                self.onSlashCommandsUpdate?(commands)
            case .failure(let error):
                print("[ACP] list_commands unavailable: \(error.localizedDescription)")
            }
        }
    }

    private func requestModes() {
        guard let sessionParams = buildSessionParams() else { return }
        sendRequest(method: "_kiro.dev/get_modes", params: sessionParams) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let response):
                let parsedModes = Self.parseModes(from: response)
                self.modeOptions = parsedModes.options
                self.currentModeId = parsedModes.currentModeId
                self.onModesUpdate?(parsedModes.options, parsedModes.currentModeId)
            case .failure(let error):
                print("[ACP] get_modes unavailable: \(error.localizedDescription)")
            }
        }
    }

    private func requestModels() {
        guard let sessionParams = buildSessionParams() else { return }
        sendRequest(method: "_kiro.dev/get_models", params: sessionParams) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let response):
                let parsedModels = Self.parseModels(from: response)
                self.modelOptions = parsedModels.options
                self.currentModelId = parsedModels.currentModelId
                self.onModelsUpdate?(parsedModels.options, parsedModels.currentModelId)
            case .failure(let error):
                print("[ACP] get_models unavailable: \(error.localizedDescription)")
            }
        }
    }

    private func buildSessionParams(_ extras: [String: AnyCodable] = [:]) -> [String: AnyCodable]? {
        guard let sessionId else {
            onError?("Kiro session is not ready yet.")
            return nil
        }
        var params: [String: AnyCodable] = ["sessionId": AnyCodable(sessionId)]
        for (key, value) in extras {
            params[key] = value
        }
        return params
    }

    private func finishTurnIfNeeded() {
        let shouldFinish = queue.sync { () -> Bool in
            guard pendingPromptRequest else { return false }
            pendingPromptRequest = false
            return true
        }
        guard shouldFinish else { return }
        onTurnComplete?()
    }
}
