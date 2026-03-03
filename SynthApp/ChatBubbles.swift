import SwiftUI

enum ThinkingAnimation {
    static let phaseDuration: TimeInterval = 0.45
    private static let totalPhases = 6
    private static let statusSteps = ["Thinking", "Reviewing", "Reasoning"]
    private static let fallbackByKind: [String: String] = [
        "read": "Reading",
        "edit": "Editing",
        "search": "Searching",
        "execute": "Running",
        "think": "Reasoning"
    ]

    static func phaseIndex(at date: Date) -> Int {
        let rawValue = Int((date.timeIntervalSinceReferenceDate / phaseDuration).rounded(.down))
        return rawValue.modulo(totalPhases)
    }

    static func activeDotIndex(for phaseIndex: Int) -> Int {
        phaseIndex.modulo(3)
    }

    static func statusText(for phaseIndex: Int) -> String {
        statusText(for: phaseIndex, latestToolCall: nil)
    }

    static func statusText(for phaseIndex: Int, latestToolCall: ACPToolCall?) -> String {
        if let latestToolCall {
            if let titleAction = actionFromToolTitle(latestToolCall.title) {
                return titleAction
            }
            return fallbackByKind[latestToolCall.kind.lowercased()] ?? "Thinking"
        }
        return statusSteps[phaseIndex.modulo(statusSteps.count)]
    }

    private static func actionFromToolTitle(_ title: String) -> String? {
        guard let token = title
            .split(separator: " ")
            .first?
            .trimmingCharacters(in: .punctuationCharacters) else { return nil }
        let actionWord = String(token)
        guard actionWord.count >= 4 else { return nil }
        guard actionWord.range(of: "^[A-Za-z]+$", options: .regularExpression) != nil else {
            return nil
        }
        return actionWord.prefix(1).uppercased() + actionWord.dropFirst()
    }
}

private extension Int {
    func modulo(_ divisor: Int) -> Int {
        let remainder = self % divisor
        return remainder >= 0 ? remainder : remainder + divisor
    }
}

@ViewBuilder
private func roleBadge(symbolName: String, tintColor: Color) -> some View {
    Image(systemName: symbolName)
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(tintColor)
        .frame(width: 18, height: 18)
        .background(tintColor.opacity(0.13))
        .clipShape(Circle())
}

// MARK: - Chat Bubble

struct ChatBubble: View {
    let message: ChatMessage
    @State private var isHovered = false

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 70)
            } else {
                roleBadge(symbolName: "sparkles", tintColor: .accentColor)
            }

            MarkdownText(message.content)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    message.role == .user
                        ? Color.accentColor.opacity(0.18)
                        : Color(nsColor: .textBackgroundColor).opacity(0.55)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .bottomTrailing) {
                    if message.role == .assistant && isHovered {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(message.content, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 10))
                                .padding(4)
                                .background(.regularMaterial)
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .padding(4)
                    }
                }
                .onHover { isHovered = $0 }

            if message.role == .assistant {
                Spacer(minLength: 70)
            } else {
                roleBadge(symbolName: "person.fill", tintColor: .orange)
            }
        }
    }

}

// MARK: - Streaming Bubble

struct ThinkingStatusIndicator: View {
    let latestToolCall: ACPToolCall?

    var body: some View {
        TimelineView(.animation(minimumInterval: ThinkingAnimation.phaseDuration / 2)) { timeline in
            let phaseIndex = ThinkingAnimation.phaseIndex(at: timeline.date)
            let activeDot = ThinkingAnimation.activeDotIndex(for: phaseIndex)
            let statusText = ThinkingAnimation.statusText(
                for: phaseIndex,
                latestToolCall: latestToolCall
            )
            let pulseScale = phaseIndex % 2 == 0 ? 1.0 : 1.08

            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 18, height: 18)
                        .scaleEffect(pulseScale)
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }

                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(
                                index == activeDot
                                    ? Color.accentColor
                                    : Color.secondary.opacity(0.35)
                            )
                            .frame(width: 5, height: 5)
                            .offset(y: index == activeDot ? -1 : 0)
                    }
                }

                Text("\(statusText)...")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct StreamingBubble: View {
    let text: String
    let isLoading: Bool
    let latestToolCall: ACPToolCall?

    var body: some View {
        HStack {
            roleBadge(symbolName: "sparkles", tintColor: .accentColor)
            VStack(alignment: .leading, spacing: 4) {
                if !text.isEmpty {
                    MarkdownText(text)
                        .font(.system(size: 13))
                }
                if isLoading {
                    ThinkingStatusIndicator(latestToolCall: latestToolCall)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            Spacer(minLength: 70)
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
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
