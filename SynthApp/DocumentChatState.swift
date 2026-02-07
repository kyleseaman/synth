import SwiftUI
import Combine

// MARK: - Chat Message

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    let content: String
    enum Role { case user, assistant }
}

// MARK: - Undo Snapshot

struct UndoSnapshot: Equatable {
    let url: URL
    let content: String
    let timestamp: Date
}

// MARK: - Document Chat State

class DocumentChatState: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var currentResponse = ""
    @Published var isLoading = false
    @Published var undoSnapshot: UndoSnapshot?
    @Published var toolCalls: [ACPToolCall] = []
    @Published var pendingPermission: ACPPermissionRequest?

    private(set) var acpClient: ACPClient?
    private(set) var isStarted = false

    // swiftlint:disable:next function_parameter_count
    func startIfNeeded(
        cwd: String,
        filePath: String,
        agent: String? = nil,
        mcpServerManager: MCPServerManager? = nil
    ) {
        guard !isStarted else { return }
        isStarted = true

        let client = ACPClient()
        client.mcpServerManager = mcpServerManager
        self.acpClient = client

        client.onUpdate = { [weak self] chunk in
            DispatchQueue.main.async {
                self?.currentResponse += chunk
            }
        }

        client.onTurnComplete = { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if !self.currentResponse.isEmpty {
                    self.messages.append(ChatMessage(role: .assistant, content: self.currentResponse))
                    self.currentResponse = ""
                }
                self.isLoading = false
            }
        }

        client.onToolCall = { [weak self] call in
            DispatchQueue.main.async {
                self?.toolCalls.append(call)
            }
        }

        client.onToolCallUpdate = { [weak self] callId, status in
            DispatchQueue.main.async {
                if let idx = self?.toolCalls.firstIndex(where: { $0.id == callId }) {
                    self?.toolCalls[idx].status = status
                }
            }
        }

        client.onPermissionRequest = { [weak self] request in
            DispatchQueue.main.async {
                self?.pendingPermission = request
            }
        }

        client.start(cwd: cwd, agent: agent)
    }

    func respondToPermission(optionId: String) {
        acpClient?.respondToPermission(optionId: optionId)
        pendingPermission = nil
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
    }

    func dismissUndo() {
        undoSnapshot = nil
    }
}
