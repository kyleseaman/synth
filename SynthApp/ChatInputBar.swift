import SwiftUI

struct ChatInputBar: View {
    @Binding var input: String
    var onSend: () -> Void
    @FocusState.Binding var isInputFocused: Bool
    var isDisabled: Bool = false
    var placeholder = "Ask for edits, summaries, or rewrites"
    var availableCommands: [ACPSlashCommand] = []
    var pendingImages: [ChatImage] = []
    var onPasteImage: ((NSImage) -> Void)?
    var onRemoveImage: ((UUID) -> Void)?

    @State private var showCommandPopover = false

    private var filteredCommands: [ACPSlashCommand] {
        guard input.hasPrefix("/") else { return [] }
        let typed = String(input.dropFirst()).lowercased()
        if typed.isEmpty { return availableCommands }
        return availableCommands.filter { $0.name.lowercased().hasPrefix(typed) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !pendingImages.isEmpty {
                imagePreviewStrip
            }
            if !filteredCommands.isEmpty {
                commandSuggestions
            }
            inputRow
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .padding(.top, 8)
    }

    // MARK: - Image Preview Strip

    private var imagePreviewStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(pendingImages) { chatImage in
                    ZStack(alignment: .topTrailing) {
                        Image(nsImage: chatImage.image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        Button {
                            onRemoveImage?(chatImage.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.white, .black.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                        .offset(x: 4, y: -4)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Slash Command Suggestions

    private var commandSuggestions: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(filteredCommands) { cmd in
                Button {
                    input = "/\(cmd.name) "
                } label: {
                    HStack(spacing: 8) {
                        Text("/\(cmd.name)")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                        Text(cmd.description)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    // MARK: - Input Row

    private var inputRow: some View {
        HStack(alignment: .center, spacing: 8) {
            TextField(placeholder, text: $input, axis: .vertical)
                .font(.system(size: 14))
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .focused($isInputFocused)
                .onSubmit {
                    if !isDisabled {
                        onSend()
                    }
                }
                .disabled(isDisabled)
                .onPasteCommand(of: [.image]) { providers in
                    for provider in providers {
                        _ = provider.loadDataRepresentation(
                            for: .image
                        ) { data, _ in
                            guard let data, let image = NSImage(data: data) else { return }
                            DispatchQueue.main.async {
                                onPasteImage?(image)
                            }
                        }
                    }
                }

            Button(action: onSend) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(
                        input.isEmpty || isDisabled
                            ? Color.secondary.opacity(0.45)
                            : Color.white
                    )
                    .frame(width: 27, height: 27)
                    .background(
                        input.isEmpty || isDisabled
                            ? Color.primary.opacity(0.08)
                            : Color.accentColor
                    )
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(input.isEmpty || isDisabled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.05))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.primary.opacity(0.12), lineWidth: 1))
    }
}
