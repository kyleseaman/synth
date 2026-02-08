import SwiftUI

struct MeetingNoteView: View {
    @Environment(DocumentStore.self) var store
    @Binding var isPresented: Bool

    @State private var meetingName = ""
    @FocusState private var isFieldFocused: Bool

    private var hasWorkspace: Bool {
        store.workspace != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Meeting Note")
                .font(.system(size: 16, weight: .semibold))

            if hasWorkspace {
                TextField("Meeting name", text: $meetingName)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFieldFocused)
                    .onSubmit { create() }
            } else {
                Text("Open a workspace first to create meeting notes.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                if hasWorkspace {
                    Button("Create") { create() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(meetingName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .padding(16)
        .frame(width: 420)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.windowBackgroundColor))
                .shadow(radius: 12)
        )
        .accessibilityAddTraits(.isModal)
        .onAppear {
            isFieldFocused = true
        }
    }

    private func create() {
        let trimmed = meetingName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        store.newMeetingNote(name: trimmed)
        isPresented = false
    }
}
