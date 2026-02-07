import SwiftUI

// MARK: - Tag Browser

struct TagBrowserView: View {
    @EnvironmentObject var store: DocumentStore
    @Binding var isPresented: Bool
    var initialTag: String?
    @State private var query = ""
    @State private var selectedTags: Set<String> = []
    @State private var selectedNoteIndex = 0
    @State private var tagListIndex = 0
    @FocusState private var isSearchFocused: Bool

    // MARK: - Computed Properties

    private var filteredTags: [(name: String, count: Int)] {
        let allTags = store.tagIndex.allTags
        if query.isEmpty { return allTags }
        return allTags
            .compactMap { tag -> (name: String, count: Int, score: Int)? in
                guard let score = tag.name.fuzzyScore(query) else { return nil }
                return (name: tag.name, count: tag.count, score: score)
            }
            .sorted { $0.score > $1.score }
            .map { (name: $0.name, count: $0.count) }
    }

    private var filteredNotes: [(url: URL, title: String, relativePath: String)] {
        guard !selectedTags.isEmpty else { return [] }
        let urls = store.tagIndex.files(matchingAll: selectedTags)
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
                Image(systemName: "number")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 14))
                TextField("Filter tags...", text: $query)
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

            // Active tag pills
            if !selectedTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(Array(selectedTags).sorted(), id: \.self) { tag in
                            TagPill(tagName: tag) {
                                selectedTags.remove(tag)
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
                // Left: Tag list
                tagListPanel
                    .frame(width: 200)

                Divider()

                // Right: Note list
                noteListPanel
            }
            .frame(maxHeight: 340)
        }
        .frame(width: 600)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 8)
        .onAppear {
            isSearchFocused = true
            if let initial = initialTag, !initial.isEmpty {
                selectedTags.insert(initial.lowercased())
            }
        }
        .onChange(of: query) { _, _ in tagListIndex = 0 }
        .background {
            KeyboardHandler(
                onUp: { handleUp() },
                onDown: { handleDown() },
                onEscape: { isPresented = false }
            )
        }
    }

    // MARK: - Tag List Panel

    private var tagListPanel: some View {
        ScrollView {
            VStack(spacing: 0) {
                let tags = filteredTags
                if tags.isEmpty {
                    Text("No tags found")
                        .foregroundStyle(.tertiary)
                        .padding(12)
                } else {
                    ForEach(Array(tags.enumerated()), id: \.element.name) { index, tag in
                        HStack {
                            Text("#\(tag.name)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color(nsColor: .systemTeal))
                            Spacer()
                            Text("(\(tag.count))")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            selectedTags.contains(tag.name)
                                ? Color.accentColor.opacity(0.2)
                                : index == tagListIndex
                                    ? Color.primary.opacity(0.03)
                                    : Color.clear
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            toggleTag(tag.name)
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
                if selectedTags.isEmpty {
                    Text("Select a tag to see notes")
                        .foregroundStyle(.tertiary)
                        .padding(12)
                        .frame(maxWidth: .infinity)
                } else if notes.isEmpty {
                    Text("No notes with selected tags")
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

    private func toggleTag(_ tagName: String) {
        if selectedTags.contains(tagName) {
            selectedTags.remove(tagName)
        } else {
            selectedTags.insert(tagName)
        }
        selectedNoteIndex = 0
    }

    private func handleUp() {
        if tagListIndex > 0 {
            tagListIndex -= 1
        }
    }

    private func handleDown() {
        let maxIndex = max(filteredTags.count - 1, 0)
        if tagListIndex < maxIndex {
            tagListIndex += 1
        }
    }
}

// MARK: - Tag Pill

struct TagPill: View {
    let tagName: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text("#\(tagName)")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(nsColor: .systemTeal))
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
                .fill(Color(nsColor: .systemTeal).opacity(0.15))
        )
    }
}
