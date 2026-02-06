import SwiftUI

// MARK: - Chat Bubble

struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            MarkdownText(message.content)
                .font(.system(size: 13))
                .padding(10)
                .background(
                    message.role == .user
                        ? Color.accentColor.opacity(0.15)
                        : Color.primary.opacity(0.05)
                )
                .cornerRadius(8)
            if message.role == .assistant { Spacer(minLength: 40) }
        }
    }
}

// MARK: - Streaming Bubble

struct StreamingBubble: View {
    let text: String
    let isLoading: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                if !text.isEmpty {
                    MarkdownText(text)
                        .font(.system(size: 13))
                }
                if isLoading {
                    HStack(spacing: 4) {
                        ProgressView().scaleEffect(0.6)
                        Text("Thinking...")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
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

// MARK: - Markdown Text

struct MarkdownText: View {
    let source: String

    init(_ source: String) {
        self.source = source
    }

    var body: some View {
        if let attributed = try? AttributedString(
            markdown: source,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attributed)
                .textSelection(.enabled)
        } else {
            Text(source)
                .textSelection(.enabled)
        }
    }
}

// MARK: - Tool Call Bubble

struct ToolCallBubble: View {
    let toolCall: ACPToolCall

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .font(.system(size: 10))
                .foregroundStyle(statusColor)
            Text(toolCall.title)
                .font(.system(size: 11))
                .lineLimit(1)
            Spacer()
            if toolCall.status == "in_progress" {
                ProgressView().scaleEffect(0.5)
            } else {
                Text(toolCall.status)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(6)
    }

    private var iconName: String {
        switch toolCall.kind {
        case "read": return "doc.text"
        case "edit": return "pencil"
        case "search": return "magnifyingglass"
        case "execute": return "terminal"
        case "think": return "brain"
        default: return "wrench"
        }
    }

    private var statusColor: Color {
        switch toolCall.status {
        case "completed": return .green
        case "failed": return .red
        case "in_progress": return .orange
        default: return .secondary
        }
    }
}

// MARK: - Undo Toast

struct UndoToast: View {
    let onUndo: () -> Void

    var body: some View {
        Button(action: onUndo) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 12, weight: .medium))
                Text("Undo AI edit")
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .cornerRadius(20)
            .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
