import SwiftUI

struct ChatInputBar: View {
    @Binding var input: String
    var onSend: () -> Void
    @FocusState.Binding var isInputFocused: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Button {} label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            HStack(alignment: .center, spacing: 8) {
                TextField("Message", text: $input, axis: .vertical)
                    .font(.system(size: 13))
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .focused($isInputFocused)
                    .onSubmit { onSend() }

                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(input.isEmpty ? Color.secondary.opacity(0.3) : Color.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(input.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 1))
        }
        .padding(.horizontal, 12)
        .padding(.trailing, 44)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }
}
