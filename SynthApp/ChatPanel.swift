import SwiftUI
import AppKit

class ChatMessageStore: ObservableObject {
    @Published var messages: [ChatMessage] = []
}

struct ChatPanel: View {
    @EnvironmentObject var store: DocumentStore
    @StateObject private var acp = ACPClient()
    @StateObject private var messageStore = ChatMessageStore()
    @State private var input = ""
    @State private var currentResponse = ""
    @State private var isLoading = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header with drag handle
            HStack {
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 40, height: 4)
                    .cornerRadius(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)

            Divider()

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(messageStore.messages) { msg in
                            ChatBubble(message: msg).id(msg.id)
                        }
                        if !currentResponse.isEmpty || isLoading {
                            StreamingBubble(text: currentResponse, isLoading: isLoading)
                                .id("streaming")
                        }
                    }.padding(12)
                }
                .onChange(of: messageStore.messages.count) {
                    if let last = messageStore.messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
                .onChange(of: currentResponse) {
                    proxy.scrollTo("streaming", anchor: .bottom)
                }
            }

            Divider()

            // Input bar
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(.tint)

                TextField("Ask Kiro...", text: $input)
                    .textFieldStyle(.plain)
                    .focused($isInputFocused)
                    .onSubmit { sendMessage() }

                if !input.isEmpty {
                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.tint)
                    }.buttonStyle(.plain)
                }

                Button {
                    NotificationCenter.default.post(name: .toggleChat, object: nil)
                } label: {
                    Image(systemName: "chevron.down.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close (⌘J)")
            }
            .padding(10)
        }
        .background(.regularMaterial)
        .onAppear {
            isInputFocused = true
            acp.start()
            acp.onUpdate = { chunk in
                currentResponse += chunk
            }
        }
        .onDisappear {
            acp.stop()
        }
    }

    func sendMessage() {
        let prompt = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        messageStore.messages.append(ChatMessage(role: .user, content: prompt))
        input = ""
        currentResponse = ""
        isLoading = true

        let filePath = store.currentIndex >= 0 ? store.openFiles[store.currentIndex].url.path : nil

        if acp.isConnected {
            acp.sendPrompt(prompt, filePath: filePath)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.checkStreamingComplete()
            }
        } else {
            // Fallback to simple kiro_chat
            runFallbackChat(prompt: prompt, filePath: filePath)
        }
    }

    func runFallbackChat(prompt: String, filePath: String?) {
        DispatchQueue.global().async {
            var fullPrompt = prompt
            if let path = filePath { fullPrompt = "Working on file: \(path)\n\n\(prompt)" }

            var response = "Error: No response"
            if let cPrompt = fullPrompt.cString(using: .utf8), let result = kiro_chat(cPrompt) {
                response = String(cString: result)
                free_string(result)
            }

            DispatchQueue.main.async {
                self.isLoading = false
                self.messageStore.messages.append(ChatMessage(role: .assistant, content: response))
            }
        }
    }

    func checkStreamingComplete() {
        let lastLength = currentResponse.count
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if self.currentResponse.count == lastLength && !self.currentResponse.isEmpty {
                self.messageStore.messages.append(
                    ChatMessage(role: .assistant, content: self.currentResponse)
                )
                self.currentResponse = ""
                self.isLoading = false
            } else if self.isLoading {
                self.checkStreamingComplete()
            }
        }
    }

}

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    let content: String
    enum Role { case user, assistant }
}

struct ChatBubble: View {
    let message: ChatMessage
    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Text(message.content)
                .font(.system(size: 13))
                .textSelection(.enabled)
                .padding(10)
                .background(message.role == .user ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05))
                .cornerRadius(8)
            if message.role == .assistant { Spacer(minLength: 40) }
        }
    }
}

struct StreamingBubble: View {
    let text: String
    let isLoading: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                if !text.isEmpty {
                    Text(text)
                        .font(.system(size: 13))
                        .textSelection(.enabled)
                }
                if isLoading {
                    HStack(spacing: 4) {
                        ProgressView().scaleEffect(0.6)
                        Text("Thinking...").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(10)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(8)
            Spacer(minLength: 40)
        }
    }
}

extension Notification.Name {
    static let reloadEditor = Notification.Name("reloadEditor")
}
