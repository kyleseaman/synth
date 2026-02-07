import SwiftUI

// MARK: - People Browser

struct PeopleBrowserView: View {
    @EnvironmentObject var store: DocumentStore
    @Binding var isPresented: Bool
    var initialPerson: String?
    @State private var query = ""
    @State private var selectedPeople: Set<String> = []
    @State private var selectedNoteIndex = 0
    @State private var personListIndex = 0
    @FocusState private var isSearchFocused: Bool

    // MARK: - Computed Properties

    private var filteredPeople: [(name: String, count: Int)] {
        let allPeople = store.peopleIndex.allPeople
        if query.isEmpty { return allPeople }
        return allPeople
            .compactMap { person -> (name: String, count: Int, score: Int)? in
                guard let score = person.name.fuzzyScore(query) else { return nil }
                return (name: person.name, count: person.count, score: score)
            }
            .sorted { $0.score > $1.score }
            .map { (name: $0.name, count: $0.count) }
    }

    private var filteredNotes: [(url: URL, title: String, relativePath: String)] {
        guard !selectedPeople.isEmpty else { return [] }
        let urls = store.peopleIndex.files(matchingAll: selectedPeople)
        return urls.map { url in
            let title = url.deletingPathExtension().lastPathComponent
            let parent = url.deletingLastPathComponent().lastPathComponent
            return (url: url, title: title, relativePath: parent)
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "person.fill")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 14))
                TextField("Filter people...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($isSearchFocused)
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)

            // Active person pills
            if !selectedPeople.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(Array(selectedPeople).sorted(), id: \.self) { person in
                            PersonPill(personName: person) {
                                selectedPeople.remove(person)
                                selectedNoteIndex = 0
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
                .frame(height: 32)
            }

            Divider()

            // Two-panel layout
            HStack(spacing: 0) {
                // Left: People list
                personListPanel
                    .frame(width: 240)

                Divider()

                // Right: Note list
                noteListPanel
            }
            .frame(maxHeight: 440)
        }
        .frame(width: 700)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 8)
        .onAppear {
            isSearchFocused = true
            if let initial = initialPerson, !initial.isEmpty {
                selectedPeople.insert(initial.lowercased())
            }
        }
        .onChange(of: query) { _, _ in personListIndex = 0 }
        .background {
            KeyboardHandler(
                onUp: { handleUp() },
                onDown: { handleDown() },
                onEscape: { isPresented = false }
            )
        }
    }

    // MARK: - People List Panel

    private var personListPanel: some View {
        ScrollView {
            VStack(spacing: 0) {
                let people = filteredPeople
                if people.isEmpty {
                    Text("No people found")
                        .foregroundStyle(.tertiary)
                        .padding(12)
                } else {
                    ForEach(Array(people.enumerated()), id: \.element.name) { index, person in
                        HStack {
                            Text("@\(person.name)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color(nsColor: .systemPurple))
                            Spacer()
                            Text("(\(person.count))")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            selectedPeople.contains(person.name)
                                ? Color.accentColor.opacity(0.2)
                                : index == personListIndex
                                    ? Color.primary.opacity(0.03)
                                    : Color.clear
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            togglePerson(person.name)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Note List Panel

    private var noteListPanel: some View {
        ScrollView {
            VStack(spacing: 0) {
                let notes = filteredNotes
                if selectedPeople.isEmpty {
                    Text("Select a person to see notes")
                        .foregroundStyle(.tertiary)
                        .padding(12)
                        .frame(maxWidth: .infinity)
                } else if notes.isEmpty {
                    Text("No notes mentioning selected people")
                        .foregroundStyle(.tertiary)
                        .padding(12)
                        .frame(maxWidth: .infinity)
                } else {
                    ForEach(Array(notes.enumerated()), id: \.element.url) { index, note in
                        HStack {
                            Image(systemName: "doc.text")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 12))
                            Text(note.title)
                                .font(.system(size: 13))
                            Spacer()
                            Text(note.relativePath)
                                .foregroundStyle(.tertiary)
                                .font(.caption)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            index == selectedNoteIndex
                                ? Color.accentColor.opacity(0.2) : Color.clear
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            store.open(note.url)
                            isPresented = false
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func togglePerson(_ personName: String) {
        if selectedPeople.contains(personName) {
            selectedPeople.remove(personName)
        } else {
            selectedPeople.insert(personName)
        }
        selectedNoteIndex = 0
    }

    private func handleUp() {
        if personListIndex > 0 {
            personListIndex -= 1
        }
    }

    private func handleDown() {
        let maxIndex = max(filteredPeople.count - 1, 0)
        if personListIndex < maxIndex {
            personListIndex += 1
        }
    }
}

// MARK: - Person Pill

struct PersonPill: View {
    let personName: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text("@\(personName)")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(nsColor: .systemPurple))
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color(nsColor: .systemPurple).opacity(0.15))
        )
    }
}
