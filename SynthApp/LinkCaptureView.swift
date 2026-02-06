import SwiftUI
import AppKit

struct LinkCaptureView: View {
    @EnvironmentObject var linkStore: LinkStore
    @EnvironmentObject var store: DocumentStore
    @Binding var isPresented: Bool

    @State private var linkText = ""
    @FocusState private var isFieldFocused: Bool

    private var isValid: Bool {
        LinkStore.normalize(linkText) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save Link")
                .font(.system(size: 16, weight: .semibold))

            TextField("Paste a link", text: $linkText)
                .textFieldStyle(.roundedBorder)
                .focused($isFieldFocused)
                .onSubmit { save() }

            if !linkText.isEmpty && !isValid {
                Text("Enter a valid URL")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
        }
        .padding(16)
        .frame(width: 420)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: NSColor.windowBackgroundColor))
                .shadow(radius: 12)
        )
        .onAppear {
            isFieldFocused = true
            prefillFromPasteboard()
        }
    }

    private func save() {
        guard linkStore.addLink(linkText) != nil else { return }
        store.selectLinksTab()
        isPresented = false
    }

    private func prefillFromPasteboard() {
        guard linkText.isEmpty else { return }
        guard let clipboardText = NSPasteboard.general.string(forType: .string) else { return }
        guard LinkStore.normalize(clipboardText) != nil else { return }
        linkText = clipboardText
    }
}
