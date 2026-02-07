import SwiftUI

// swiftlint:disable:next type_body_length
struct DocumentChatTray: View {
    @ObservedObject var chatState: DocumentChatState
    @EnvironmentObject var store: DocumentStore
    let documentURL: URL
    let documentContent: String
    var selectedText: String?
    var selectedLineRange: String?

    @State private var input = ""
    @State private var trayHeight: CGFloat = 250
    @State private var selectedAgent: String?
    @FocusState private var isInputFocused: Bool

    private let minHeight: CGFloat = 150
    private let maxHeight: CGFloat = 600

    var body: some View {
        VStack(spacing: 0) {
            dragHandle
            messageList
            permissionBar
            selectionIndicator
            inputBar
        }
        .frame(height: trayHeight)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            Button {
                NotificationCenter.default.post(name: .toggleChat, object: nil)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .background(Color.primary.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(6)
        }
        .shadow(color: .black.opacity(0.1), radius: 8, y: -2)
        .onAppear {
            isInputFocused = true
            wireFileCallbacks()
        }
    }

    // MARK: - Drag Handle

    private var dragHandle: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.3))
            .frame(width: 36, height: 3)
            .cornerRadius(1.5)
            .frame(maxWidth: .infinity)
            .frame(height: 10)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { gesture in
                        let newHeight = trayHeight - gesture.translation.height
                        trayHeight = min(max(newHeight, minHeight), maxHeight)
                    }
            )
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
    }

    // MARK: - Messages

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(chatState.messages) { msg in
                        ChatBubble(message: msg).id(msg.id)
                    }
                    ForEach(chatState.toolCalls.filter { $0.status != "completed" }) { call in
                        ToolCallBubble(toolCall: call).id(call.id)
                    }
                    if !chatState.currentResponse.isEmpty || chatState.isLoading {
                        let showSpinner = chatState.isLoading &&
                            chatState.toolCalls.allSatisfy { $0.status == "completed" }
                        StreamingBubble(
                            text: chatState.currentResponse,
                            isLoading: showSpinner
                        ).id("streaming")
                    }
                }
                .padding(.leading, 38)
                .padding(.trailing, 56)
                .padding(.vertical, 6)
            }
            .scrollIndicators(.hidden)
            .onChange(of: chatState.messages.count) {
                if let last = chatState.messages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: chatState.currentResponse) {
                proxy.scrollTo("streaming", anchor: .bottom)
            }
            .onChange(of: chatState.toolCalls.count) {
                if let last = chatState.toolCalls.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Selection Indicator

    @ViewBuilder
    private var selectionIndicator: some View {
        if let range = selectedLineRange, selectedText != nil {
            HStack(spacing: 4) {
                Image(systemName: "text.line.first.and.arrowtriangle.forward")
                    .font(.system(size: 10))
                Text("Sending selection: \(range)")
                    .font(.system(size: 11))
                Spacer()
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 6)
        }
    }

    // MARK: - Permission Bar

    @ViewBuilder
    private var permissionBar: some View {
        if let perm = chatState.pendingPermission {
            VStack(alignment: .leading, spacing: 6) {
                Text(perm.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2)
                if let diff = perm.diffContent {
                    ScrollView {
                        permissionDiffView(diff)
                    }
                    .frame(height: 120)
                    .padding(6)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(4)
                }
                HStack(spacing: 8) {
                    Spacer()
                    Button {
                        denyPermission()
                    } label: {
                        HStack(spacing: 4) {
                            Text("Deny")
                            Text("[esc]").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.escape, modifiers: [])
                    Button {
                        allowPermission()
                    } label: {
                        HStack(alignment: .center, spacing: 4) {
                            Text("Allow")
                            Text("[↩]").font(.system(size: 11)).baselineOffset(-2.5)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [])
                    Button {
                        alwaysAllowPermission()
                    } label: {
                        HStack(alignment: .center, spacing: 4) {
                            Text("Always Allow")
                            Text("[⌘↩]").font(.system(size: 10)).baselineOffset(-2)
                        }
                    }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.return, modifiers: .command)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)
            .padding(.leading, 38)
            .padding(.trailing, 56)
            .padding(.top, 6)
        }
    }

    private func allowPermission() {
        chatState.respondToPermission(optionId: "allow_once")
    }

    private func alwaysAllowPermission() {
        chatState.respondToPermission(optionId: "allow_always")
    }

    private func denyPermission() {
        chatState.respondToPermission(optionId: "reject_once")
    }

    @ViewBuilder
    private func permissionDiffView(_ diff: DiffContent) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Add:")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(diff.newText.prefix(300) + (diff.newText.count > 300 ? "..." : ""))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.green)
            }
            if !diff.oldText.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Remove:")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(diff.oldText.prefix(300) + (diff.oldText.count > 300 ? "..." : ""))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.red)
                        .strikethrough()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        ChatInputBar(
            input: $input,
            onSend: sendMessage,
            isInputFocused: $isInputFocused,
            isDisabled: chatState.isLoading
        )
    }

    // MARK: - Actions

    private func wireFileCallbacks() {
        chatState.acpClient?.onFileRead = { [weak store] path in
            guard let store = store else { return nil }
            if let idx = store.openFiles.firstIndex(where: { $0.url.path == path }) {
                return store.openFiles[idx].content.string
            }
            return try? String(contentsOfFile: path, encoding: .utf8)
        }

        chatState.acpClient?.onFileWrite = { [weak store, weak chatState] path, content in
            guard let store = store, let chatState = chatState else { return }
            if let idx = store.openFiles.firstIndex(where: { $0.url.path == path }) {
                let snapshot = UndoSnapshot(
                    url: store.openFiles[idx].url,
                    content: store.openFiles[idx].content.string,
                    timestamp: Date()
                )
                chatState.undoSnapshot = snapshot
                store.openFiles[idx].content = NSAttributedString(string: content)
                store.openFiles[idx].isDirty = true
                store.objectWillChange.send()

                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    if chatState.undoSnapshot?.timestamp == snapshot.timestamp {
                        chatState.undoSnapshot = nil
                    }
                }
            }
        }
    }

    private func sendMessage() {
        let prompt = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        chatState.messages.append(ChatMessage(role: .user, content: prompt))
        input = ""
        chatState.currentResponse = ""
        chatState.isLoading = true
        chatState.toolCalls.removeAll()

        let cwdPath = store.workspace?.path ?? documentURL.deletingLastPathComponent().path
        chatState.startIfNeeded(
            cwd: cwdPath,
            filePath: documentURL.path,
            agent: selectedAgent,
            mcpServerManager: store.mcpServer
        )
        wireFileCallbacks()

        guard chatState.acpClient?.isConnected == true else {
            // Wait for connection then send
            waitAndSend(prompt: prompt, retries: 10)
            return
        }

        chatState.acpClient?.sendPrompt(buildContentBlocks(prompt: prompt))
    }

    private func waitAndSend(prompt: String, retries: Int) {
        guard retries > 0 else {
            chatState.isLoading = false
            chatState.messages.append(
                ChatMessage(role: .assistant, content: "Failed to connect to Kiro.")
            )
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if self.chatState.acpClient?.isConnected == true,
               self.chatState.acpClient?.sessionId != nil {
                self.chatState.acpClient?.sendPrompt(self.buildContentBlocks(prompt: prompt))
            } else {
                self.waitAndSend(prompt: prompt, retries: retries - 1)
            }
        }
    }

    private func buildContentBlocks(prompt: String) -> [[String: AnyCodable]] {
        var blocks: [[String: AnyCodable]] = []

        // Add document context as text (agent doesn't support embeddedContext)
        if let selection = selectedText, !selection.isEmpty {
            let label = selectedLineRange ?? "selection"
            blocks.append([
                "type": AnyCodable("text"),
                "text": AnyCodable("[Selected \(label) from \(documentURL.lastPathComponent)]:\n\(selection)")
            ])
        } else {
            blocks.append([
                "type": AnyCodable("text"),
                "text": AnyCodable(
                    "[Current file: \(documentURL.path)]\n\n\(documentContent)"
                )
            ])
        }

        // Add user prompt
        blocks.append([
            "type": AnyCodable("text"),
            "text": AnyCodable(prompt)
        ])

        return blocks
    }
}
