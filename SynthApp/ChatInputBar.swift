import SwiftUI

struct ChatInputBar: View {
    @Binding var input: String
    var onSend: () -> Void
    @FocusState.Binding var isInputFocused: Bool
    var isDisabled: Bool = false
    var placeholder = "Ask for edits, reasoning, or code changes"

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor.opacity(0.9))
                .padding(6)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(Circle())

            TextField(placeholder, text: $input, axis: .vertical)
                .font(.system(size: 13))
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .focused($isInputFocused)
                .onSubmit {
                    if !isDisabled {
                        onSend()
                    }
                }
                .disabled(isDisabled)

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
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.9))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.primary.opacity(0.12), lineWidth: 1))
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .padding(.top, 8)
    }
}
