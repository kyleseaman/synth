import SwiftUI
import AppKit

struct DocumentChatTray: View {
    var chatState: DocumentChatState
    @Environment(DocumentStore.self) var store
    @Environment(\.openURL) private var openURL
    let documentURL: URL
    let documentContent: String
    var selectedText: String?
    var selectedLineRange: String?
    var selectedImageURL: URL?

    @State private var input = ""
    @State private var trayHeight: CGFloat = 300
    @State private var selectedAgent: String?
    @FocusState private var isInputFocused: Bool

    private let minHeight: CGFloat = 180
    private let maxHeight: CGFloat = 720
    private let minWidth: CGFloat = 280
    private let maxWidth: CGFloat = 640
    private static let preferredAgentIdentifier = "synth-writer"
    private static let preferredAgentSymbolName = "person.crop.circle"
    private static let fallbackAgentSymbolName = "person"
    private static let maxQuickPromptCount = 3
    private let quickPrompts = [
        "Summarize this document into key points",
        "Rewrite this section for clarity and flow",
        "Improve headings and overall structure",
        "Find gaps, ambiguities, or inconsistencies"
    ]

    static func preferredAgentName(from agents: [AgentInfo]) -> String? {
        if agents.contains(where: { $0.name == preferredAgentIdentifier }) {
            return preferredAgentIdentifier
        }
        return agents.first(where: { $0.name.localizedCaseInsensitiveContains("writer") })?.name
    }

    static func shouldShowChatHints(
        messageCount: Int,
        currentResponse: String,
        isLoading: Bool
    ) -> Bool {
        messageCount == 0 && currentResponse.isEmpty && !isLoading
    }

    static func agentSymbolName(
        symbolExists: (String) -> Bool = { symbolName in
            NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) != nil
        }
    ) -> String {
        if symbolExists(preferredAgentSymbolName) {
            return preferredAgentSymbolName
        }
        return fallbackAgentSymbolName
    }

    static func displayedQuickPrompts(from prompts: [String]) -> [String] {
        Array(prompts.prefix(maxQuickPromptCount))
    }

    static func displayedPermissionDiffText(_ text: String) -> String {
        text
    }

    private var isTrailing: Bool { store.chatPlacement == .trailing }
    private let glassCornerRadius: CGFloat = 18

    var body: some View {
        HStack(spacing: 0) {
            if isTrailing { sideDragHandle }
            VStack(spacing: 0) {
                if !isTrailing { dragHandle }
                headerBar
                Divider().opacity(0.3)
                messageList
                statusBanner
                permissionBar
                selectionIndicator
                quickPromptBar
                inputBar
            }
        }
        .frame(height: isTrailing ? nil : trayHeight)
        .frame(maxHeight: isTrailing ? .infinity : nil)
        .background {
            if isTrailing {
                Color.clear
            } else {
                backgroundGradient
            }
        }
        .glassEffect(
            isTrailing ? .regular : .identity,
            in: RoundedRectangle(cornerRadius: glassCornerRadius)
        )
        .clipShape(RoundedRectangle(cornerRadius: isTrailing ? glassCornerRadius : 14))
        .overlay(
            RoundedRectangle(cornerRadius: isTrailing ? glassCornerRadius : 14)
                .stroke(
                    Color.white.opacity(isTrailing ? 0 : 0.12),
                    lineWidth: isTrailing ? 0 : 1
                )
        )
        .shadow(
            color: .black.opacity(isTrailing ? 0.18 : 0.22),
            radius: isTrailing ? 12 : 16,
            y: isTrailing ? 0 : -3
        )
        .onAppear {
            refocusInputIfNeeded()
            if selectedAgent == nil {
                selectedAgent = Self.preferredAgentName(from: store.customAgents)
            }
            wireFileCallbacks()
            wireOAuthCallback()
            attachEditorImage()
            autoConnect()
        }
        .onChange(of: store.customAgents.map(\.name)) {
            if selectedAgent == nil {
                selectedAgent = Self.preferredAgentName(from: store.customAgents)
            }
        }
        .onChange(of: chatState.messages.count) {
            refocusInputIfNeeded()
        }
        .onChange(of: chatState.currentResponse) {
            refocusInputIfNeeded()
        }
        .onChange(of: chatState.isLoading) {
            refocusInputIfNeeded()
            if !chatState.isLoading {
                _ = store.reloadOpenDocumentFromDisk(documentURL)
            }
        }
        .onChange(of: selectedImageURL) {
            attachEditorImage()
        }
        .onChange(of: selectedAgent) {
            guard chatState.isStarted else { return }
            chatState.stop()
            let workspacePath = store.workspace?.path ?? documentURL.deletingLastPathComponent().path
            chatState.startIfNeeded(
                cwd: workspacePath,
                filePath: documentURL.path,
                agent: selectedAgent,
                mcpServerManager: store.mcpServer,
                documentURL: documentURL
            )
            wireFileCallbacks()
            wireOAuthCallback()
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Assistant")
                    .font(.system(size: 13, weight: .semibold))
                connectionBadge
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        store.chatPlacement = store.chatPlacement == .bottom ? .trailing : .bottom
                    }
                } label: {
                    Image(systemName: store.chatPlacement == .bottom
                          ? "rectangle.righthalf.inset.filled"
                          : "rectangle.bottomhalf.inset.filled")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .background(Color.primary.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help(store.chatPlacement == .bottom ? "Move to Side" : "Move to Bottom")

                Button {
                    store.toggleChatForCurrentTab()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .background(Color.primary.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 8) {
                Label(documentURL.lastPathComponent, systemImage: "doc.text")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                modePicker
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var modePicker: some View {
        let modes = chatState.availableModes
        if !modes.isEmpty {
            Menu {
                ForEach(modes) { mode in
                    Button {
                        chatState.setMode(mode.id)
                    } label: {
                        HStack {
                            Text(mode.name)
                            if chatState.currentModeId == mode.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: Self.agentSymbolName())
                        .font(.system(size: 11))
                    Text(currentModeName)
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.07))
                .clipShape(Capsule())
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.plain)
        } else {
            Menu {
                Button("Auto (Workspace Default)") { selectedAgent = nil }
                if !store.customAgents.isEmpty {
                    Divider()
                    ForEach(store.customAgents, id: \.name) { agentInfo in
                        Button(agentInfo.name) {
                            selectedAgent = agentInfo.name
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: Self.agentSymbolName())
                        .font(.system(size: 11))
                    Text(selectedAgent ?? "Auto Agent")
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.07))
                .clipShape(Capsule())
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.plain)
        }
    }

    private var currentModeName: String {
        if let modeId = chatState.currentModeId,
           let mode = chatState.availableModes.first(where: { $0.id == modeId }) {
            return mode.name
        }
        return "Agent"
    }

    private var connectionBadge: some View {
        Text(connectionTitle)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(connectionColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(connectionColor.opacity(0.15))
            .clipShape(Capsule())
    }

    private var connectionTitle: String {
        if chatState.acpClient?.connectionFailed == true {
            return "Disconnected"
        }
        if chatState.acpClient?.isConnected == true, chatState.acpClient?.sessionId != nil {
            return "Connected"
        }
        if chatState.isLoading || chatState.acpClient != nil {
            return "Connecting"
        }
        return "Ready"
    }

    private var connectionColor: Color {
        switch connectionTitle {
        case "Connected":
            return .green
        case "Disconnected":
            return .red
        case "Connecting":
            return .orange
        default:
            return .secondary
        }
    }

    // MARK: - Drag Handle

    private var dragHandle: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.35))
            .frame(width: 42, height: 3)
            .cornerRadius(1.5)
            .frame(maxWidth: .infinity)
            .frame(height: 11)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { gesture in
                        let nextHeight = trayHeight - gesture.translation.height
                        trayHeight = min(max(nextHeight, minHeight), maxHeight)
                    }
            )
            .onHover { isHovering in
                if isHovering {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
    }

    private var sideDragHandle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 6)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { gesture in
                        let nextWidth = store.chatWidth - gesture.translation.width
                        store.chatWidth = min(max(nextWidth, minWidth), maxWidth)
                    }
            )
            .onHover { isHovering in
                if isHovering {
                    NSCursor.resizeLeftRight.push()
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
                    if Self.shouldShowChatHints(
                        messageCount: chatState.messages.count,
                        currentResponse: chatState.currentResponse,
                        isLoading: chatState.isLoading
                    ) {
                        emptyStateView
                    }

                    ForEach(chatState.messages) { message in
                        ChatBubble(message: message).id(message.id)
                    }
                    ForEach(chatState.toolCalls.filter { $0.status != "completed" }) { call in
                        ToolCallBubble(toolCall: call).id(call.id)
                    }
                    if !chatState.currentResponse.isEmpty || chatState.isLoading {
                        let showSpinner = chatState.isLoading &&
                            chatState.toolCalls.allSatisfy { $0.status == "completed" }
                        StreamingBubble(
                            text: chatState.currentResponse,
                            isLoading: showSpinner,
                            latestToolCall: chatState.toolCalls.last
                        )
                        .id("streaming")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
            .onChange(of: chatState.messages.count) {
                if let lastMessage = chatState.messages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: chatState.currentResponse) {
                proxy.scrollTo("streaming", anchor: .bottom)
            }
            .onChange(of: chatState.toolCalls.count) {
                if let lastCall = chatState.toolCalls.last {
                    proxy.scrollTo(lastCall.id, anchor: .bottom)
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Start a collaborative turn")
                .font(.system(size: 13, weight: .semibold))
            Text("I can read, edit, and reason over this workspace with your approval.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Selection Indicator

    @ViewBuilder
    private var selectionIndicator: some View {
        if let selectedLineRange, selectedText != nil {
            HStack(spacing: 5) {
                Image(systemName: "text.line.first.and.arrowtriangle.forward")
                    .font(.system(size: 10))
                Text("Using selection context: \(selectedLineRange)")
                    .font(.system(size: 11))
                Spacer()
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.top, 5)
        }
    }

    // MARK: - Quick Prompts

    private var quickPromptBar: some View {
        Group {
            if Self.shouldShowChatHints(
                messageCount: chatState.messages.count,
                currentResponse: chatState.currentResponse,
                isLoading: chatState.isLoading
            ) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Self.displayedQuickPrompts(from: quickPrompts), id: \.self) { prompt in
                        Button(prompt) {
                            input = prompt
                            sendMessage()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10.5))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                        .disabled(chatState.isLoading)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Permission Bar

    @ViewBuilder
    private var permissionBar: some View {
        if let permission = chatState.pendingPermission {
            VStack(alignment: .leading, spacing: 6) {
                Text(permission.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2)
                if let diff = permission.diffContent {
                    ScrollView {
                        permissionDiffView(diff)
                    }
                    .frame(height: 120)
                    .padding(7)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(6)
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
            .background(Color.orange.opacity(0.12))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(Color.orange.opacity(0.25), lineWidth: 1)
            )
            .cornerRadius(9)
            .padding(.horizontal, 14)
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
                Text(Self.displayedPermissionDiffText(diff.newText))
                    .font(Theme.terminalSwiftUIFont(size: 11))
                    .foregroundStyle(.green)
            }
            if !diff.oldText.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Remove:")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(Self.displayedPermissionDiffText(diff.oldText))
                        .font(Theme.terminalSwiftUIFont(size: 11))
                        .foregroundStyle(.red)
                        .strikethrough()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Status Banner

    @ViewBuilder
    private var statusBanner: some View {
        if let status = chatState.statusMessage {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(status)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.08))
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        ChatInputBar(
            input: $input,
            onSend: sendMessage,
            isInputFocused: $isInputFocused,
            isDisabled: chatState.isLoading,
            availableCommands: chatState.availableCommands,
            pendingImages: chatState.pendingImages,
            onPasteImage: { image in
                chatState.addImage(image, label: "Pasted image")
            },
            onRemoveImage: { imageId in
                chatState.removeImage(id: imageId)
            }
        )
    }

    // MARK: - Styling

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .windowBackgroundColor),
                Color(nsColor: .windowBackgroundColor).opacity(0.95),
                Color.accentColor.opacity(0.05)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Actions

    private func autoConnect() {
        let workspacePath = store.workspace?.path ?? documentURL.deletingLastPathComponent().path
        chatState.startIfNeeded(
            cwd: workspacePath,
            filePath: documentURL.path,
            agent: selectedAgent,
            mcpServerManager: store.mcpServer,
            documentURL: documentURL
        )
        wireFileCallbacks()
    }

    private func wireOAuthCallback() {
        chatState.onOAuthRequest = { [openURL] url in
            openURL(url)
        }
    }

    private func attachEditorImage() {
        guard let imageURL = selectedImageURL,
              let image = NSImage(contentsOf: imageURL) else { return }
        let alreadyAttached = chatState.pendingImages.contains {
            $0.label == imageURL.lastPathComponent
        }
        if !alreadyAttached {
            chatState.addImage(image, label: imageURL.lastPathComponent)
        }
    }

    private func wireFileCallbacks() {
        chatState.onEditToolCompleted = { [weak store] locationPaths in
            guard let store else { return }
            let rootURL = store.workspace ?? documentURL.deletingLastPathComponent()
            for locationPath in locationPaths {
                guard let requestedURL = Self.scopedWorkspaceURL(path: locationPath, root: rootURL) else {
                    continue
                }
                _ = store.reloadOpenDocumentFromDisk(requestedURL)
            }
        }

        chatState.acpClient?.onFileRead = { [weak store] path in
            guard let store else { return nil }
            let rootURL = store.workspace ?? documentURL.deletingLastPathComponent()
            guard let requestedURL = Self.scopedWorkspaceURL(path: path, root: rootURL) else {
                return nil
            }

            if let fileIndex = store.openFiles.firstIndex(
                where: { Self.canonicalURL($0.url) == requestedURL }
            ) {
                return store.openFiles[fileIndex].content.string
            }
            return try? String(contentsOf: requestedURL, encoding: .utf8)
        }

        chatState.acpClient?.onFileWrite = { [weak store, weak chatState] path, content in
            guard let store, let chatState else { return }
            let rootURL = store.workspace ?? documentURL.deletingLastPathComponent()
            guard let requestedURL = Self.scopedWorkspaceURL(path: path, root: rootURL) else {
                return
            }

            if let fileIndex = store.openFiles.firstIndex(
                where: { Self.canonicalURL($0.url) == requestedURL }
            ) {
                let snapshot = UndoSnapshot(
                    url: store.openFiles[fileIndex].url,
                    content: store.openFiles[fileIndex].content.string,
                    timestamp: Date()
                )
                chatState.undoSnapshot = snapshot
                store.openFiles[fileIndex].content = NSAttributedString(string: content)
                store.openFiles[fileIndex].isDirty = true

                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    if chatState.undoSnapshot?.timestamp == snapshot.timestamp {
                        chatState.undoSnapshot = nil
                    }
                }
            }
        }
    }

    private static func scopedWorkspaceURL(path: String, root: URL) -> URL? {
        let requestedURL = canonicalURL(URL(fileURLWithPath: path))
        let rootURL = canonicalURL(root)
        let rootPath = rootURL.path
        let isRoot = requestedURL.path == rootPath
        let isDescendant = requestedURL.path.hasPrefix(rootPath + "/")
        return (isRoot || isDescendant) ? requestedURL : nil
    }

    private static func canonicalURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    private func sendMessage() {
        let prompt = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        chatState.messages.append(ChatMessage(role: .user, content: prompt))
        input = ""
        chatState.currentResponse = ""
        chatState.isLoading = true
        chatState.toolCalls.removeAll()
        refocusInputIfNeeded()

        let workspacePath = store.workspace?.path ?? documentURL.deletingLastPathComponent().path
        chatState.startIfNeeded(
            cwd: workspacePath,
            filePath: documentURL.path,
            agent: selectedAgent,
            mcpServerManager: store.mcpServer,
            documentURL: documentURL
        )
        wireFileCallbacks()

        guard chatState.acpClient?.isConnected == true else {
            waitAndSend(prompt: prompt, retries: 20)
            return
        }

        chatState.acpClient?.sendPrompt(buildContentBlocks(prompt: prompt))
    }

    private func refocusInputIfNeeded() {
        DispatchQueue.main.async {
            self.isInputFocused = true
        }
    }

    private func waitAndSend(prompt: String, retries: Int) {
        guard retries > 0 else {
            chatState.isLoading = false
            chatState.messages.append(
                ChatMessage(role: .assistant, content: "Failed to connect to kiro-cli.")
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

        // Image content blocks
        for chatImage in chatState.pendingImages {
            if let base64 = chatImage.image.pngBase64 {
                blocks.append([
                    "type": AnyCodable("image"),
                    "mimeType": AnyCodable("image/png"),
                    "data": AnyCodable(base64)
                ])
            }
        }
        chatState.pendingImages.removeAll()

        if let selection = selectedText, !selection.isEmpty {
            let label = selectedLineRange ?? "selection"
            blocks.append([
                "type": AnyCodable("text"),
                "text": AnyCodable("[Selected \(label) from \(documentURL.lastPathComponent)]:\n\(selection)")
            ])
        } else {
            blocks.append([
                "type": AnyCodable("text"),
                "text": AnyCodable("[Current file: \(documentURL.path)]\n\n\(documentContent)")
            ])
        }

        blocks.append([
            "type": AnyCodable("text"),
            "text": AnyCodable(prompt)
        ])

        return blocks
    }
}
