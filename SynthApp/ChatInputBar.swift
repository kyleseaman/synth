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
                ZStack(alignment: .leading) {
                    if input.isEmpty {
                        Text("Message")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                    }
                    TextEditor(text: $input)
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .scrollIndicators(.hidden)
                        .focused($isInputFocused)
                        .frame(minHeight: 18, maxHeight: 80)
                        .fixedSize(horizontal: false, vertical: true)
                        .offset(x: -5, y: 1)
                        .onKeyPress(.return, phases: .down) { press in
                            if press.modifiers.contains(.shift) {
                                return .ignored
                            }
                            onSend()
                            return .handled
                        }
                }

                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(input.isEmpty ? Color.secondary.opacity(0.3) : Color.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(input.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 1))
        }
        .padding(.horizontal, 12)
        .padding(.trailing, 44)
        .padding(.bottom, 10)
    }
}
