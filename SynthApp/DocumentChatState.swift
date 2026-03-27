import SwiftUI

// MARK: - Chat Message

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    let content: String
    enum Role { case user, assistant }
}

// MARK: - Chat Image

struct ChatImage: Identifiable {
    let id = UUID()
    let image: NSImage
    let label: String?
}

// MARK: - Undo Snapshot

struct UndoSnapshot: Equatable {
    let url: URL
    let content: String
    let timestamp: Date
}

// MARK: - Document Chat State

@MainActor
@Observable class DocumentChatState {
    var messages: [ChatMessage] = []
    var currentResponse = ""
    var isLoading = false
    var undoSnapshot: UndoSnapshot?
    var toolCalls: [ACPToolCall] = []
    var pendingPermission: ACPPermissionRequest?
    var statusMessage: String?
    var pendingImages: [ChatImage] = []

    @ObservationIgnored private(set) var acpClient: ACPClient?
    @ObservationIgnored private(set) var isStarted = false
    @ObservationIgnored private var documentURL: URL?
    @ObservationIgnored var onEditToolCompleted: (([String]) -> Void)?
    @ObservationIgnored var onOAuthRequest: ((URL) -> Void)?

    var availableCommands: [ACPSlashCommand] {
        acpClient?.availableCommands ?? []
    }

    var availableModes: [ACPSessionMode] {
        acpClient?.availableModes ?? []
    }

    var currentModeId: String? {
        acpClient?.currentModeId
    }

    func startIfNeeded(
        cwd: String,
        filePath: String,
        agent: String? = nil,
        mcpServerManager: MCPServerManager? = nil,
        documentURL: URL? = nil
    ) {
        guard !isStarted else { return }
        isStarted = true
        self.documentURL = documentURL

        let client = ACPClient()
        client.mcpServerManager = mcpServerManager
        self.acpClient = client

        client.onUpdate = { [weak self] chunk in
            self?.currentResponse += chunk
        }

        client.onTurnComplete = { [weak self] in
            guard let self = self else { return }
            if !self.currentResponse.isEmpty {
                self.messages.append(ChatMessage(role: .assistant, content: self.currentResponse))
                self.currentResponse = ""
            }
            for idx in self.toolCalls.indices where self.toolCalls[idx].status != "completed"
                && self.toolCalls[idx].status != "failed" {
                self.toolCalls[idx].status = "completed"
            }
            self.isLoading = false
        }

        client.onToolCall = { [weak self] call in
            self?.toolCalls.append(call)
        }

        client.onToolCallUpdate = { [weak self] callId, status in
            if let idx = self?.toolCalls.firstIndex(where: { $0.id == callId }) {
                self?.toolCalls[idx].status = status
            }
        }

        client.onEditToolCompleted = { [weak self] _, locationPaths in
            self?.onEditToolCompleted?(locationPaths)
        }

        client.onPermissionRequest = { [weak self] request in
            self?.pendingPermission = request
        }

        client.onError = { [weak self] message in
            self?.isLoading = false
            self?.messages.append(ChatMessage(role: .assistant, content: message))
        }

        // Session persistence: replay user messages during session/load
        client.onUserMessageReplay = { [weak self] text in
            self?.messages.append(ChatMessage(role: .user, content: text))
        }

        client.onAssistantMessageReplay = { [weak self] text in
            self?.messages.append(ChatMessage(role: .assistant, content: text))
        }

        // Session ready: persist the session ID
        client.onSessionReady = { [weak self] sessionId in
            guard let self = self, let docURL = self.documentURL else { return }
            ACPSessionStore.save(sessionId: sessionId, for: docURL)
        }

        // Session load failed: fall back to new session
        client.onSessionLoadFailed = { [weak self] in
            guard let self = self, let docURL = self.documentURL else { return }
            ACPSessionStore.remove(for: docURL)
            self.acpClient?.createSession()
        }

        // Kiro extension callbacks
        client.onOAuthRequest = { [weak self] url in
            self?.onOAuthRequest?(url)
        }

        client.onCompactionStatus = { [weak self] status in
            if status == "completed" || status == "done" {
                self?.statusMessage = nil
            } else {
                self?.statusMessage = "Compacting context…"
            }
        }

        client.onClearStatus = { [weak self] status in
            if status == "completed" || status == "done" {
                self?.statusMessage = nil
            } else {
                self?.statusMessage = "Clearing history…"
            }
        }

        client.onMcpServerInitialized = { _ in }

        client.start(cwd: cwd, agent: agent)

        // After connection, try to load existing session or create new
        let storedSessionId = documentURL.flatMap { ACPSessionStore.sessionId(for: $0) }
        Task { [weak self] in
            await self?.waitForConnection(client: client, storedSessionId: storedSessionId)
        }
    }

    private func waitForConnection(
        client: ACPClient,
        storedSessionId: String?,
        maxAttempts: Int = 20,
        intervalSeconds: Double = 0.3
    ) async {
        for attempt in 1...maxAttempts {
            if client.isConnected {
                print("[ACP] Connected after \(attempt) attempt(s)")
                if let storedId = storedSessionId, client.supportsLoadSession {
                    client.loadSession(sessionId: storedId)
                } else {
                    if storedSessionId != nil, !client.supportsLoadSession {
                        if let docURL = documentURL {
                            ACPSessionStore.remove(for: docURL)
                        }
                    }
                    client.createSession()
                }
                return
            }
            try? await Task.sleep(for: .milliseconds(Int(intervalSeconds * 1000)))
        }
        print("[ACP] Connection timed out after \(maxAttempts) attempts — creating fresh session")
        if let docURL = documentURL, storedSessionId != nil {
            ACPSessionStore.remove(for: docURL)
        }
        client.createSession()
    }

    func setMode(_ modeId: String) {
        acpClient?.setMode(modeId)
    }

    func respondToPermission(optionId: String) {
        acpClient?.respondToPermission(optionId: optionId)
        pendingPermission = nil
    }

    func newChat() {
        if let docURL = documentURL {
            ACPSessionStore.remove(for: docURL)
        }
        messages.removeAll()
        currentResponse = ""
        toolCalls.removeAll()
        pendingPermission = nil
        statusMessage = nil
        pendingImages.removeAll()
        acpClient?.createSession()
    }

    func stop() {
        acpClient?.stop()
        acpClient = nil
        isStarted = false
        messages.removeAll()
        currentResponse = ""
        isLoading = false
        undoSnapshot = nil
        toolCalls.removeAll()
        pendingImages.removeAll()
        // Note: do NOT remove stored session ID — it persists for reload
    }

    func dismissUndo() {
        undoSnapshot = nil
    }

    func addImage(_ image: NSImage, label: String? = nil) {
        pendingImages.append(ChatImage(image: image, label: label))
    }

    func removeImage(id: UUID) {
        pendingImages.removeAll { $0.id == id }
    }
}
