import SwiftUI

struct DocumentChatTray: View {
    @ObservedObject var chatState: DocumentChatState
    @EnvironmentObject var store: DocumentStore
    let documentURL: URL
    let documentContent: String
    var selectedText: String?
    var selectedLineRange: String?

    @State private var input = ""
    @State private var trayHeight: CGFloat = 220
    @State private var selectedAgent: String?
    @FocusState private var isInputFocused: Bool

    private let minHeight: CGFloat = 150
    private let maxHeight: CGFloat = 500

    var body: some View {
        VStack(spacing: 0) {
            dragHandle
            Divider()
            messageList
            toolCallList
            Divider()
            selectionIndicator
            inputBar
        }
        .frame(height: trayHeight)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            isInputFocused = true
            wireFileCallbacks()
        }
    }

    // MARK: - Drag Handle

    private var dragHandle: some View {
        HStack {
            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 40, height: 4)
                .cornerRadius(2)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 14)
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
                    if !chatState.currentResponse.isEmpty || chatState.isLoading {
                        StreamingBubble(
                            text: chatState.currentResponse,
                            isLoading: chatState.isLoading
                        ).id("streaming")
                    }
                }.padding(12)
            }
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
        }
    }

    // MARK: - Tool Calls

    @ViewBuilder
    private var toolCallList: some View {
        let activeCalls = chatState.toolCalls.filter { $0.status != "completed" }
        if !activeCalls.isEmpty {
            VStack(spacing: 4) {
                ForEach(activeCalls) { call in
                    ToolCallBubble(toolCall: call)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
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

    // MARK: - Input Bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            TextField("Reply...", text: $input, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($isInputFocused)
                .onSubmit { sendMessage() }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

            HStack(spacing: 8) {
                agentPicker
                Spacer()
                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(input.isEmpty ? Color.secondary.opacity(0.4) : Color.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(input.isEmpty)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.15), lineWidth: 1)
        )
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var agentPicker: some View {
        Menu {
            Button {
                selectedAgent = nil
            } label: {
                if selectedAgent == nil {
                    Label("Default", systemImage: "checkmark")
                } else {
                    Text("Default")
                }
            }
            if !store.customAgents.isEmpty {
                Divider()
                ForEach(store.customAgents, id: \.name) { agent in
                    Button {
                        selectedAgent = agent.name
                    } label: {
                        if selectedAgent == agent.name {
                            Label(agent.name, systemImage: "checkmark")
                        } else {
                            Text(agent.name)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                if let agent = selectedAgent {
                    Text(agent)
                        .font(.system(size: 11))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.tint)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
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
        chatState.startIfNeeded(cwd: cwdPath, filePath: documentURL.path, agent: selectedAgent)
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
