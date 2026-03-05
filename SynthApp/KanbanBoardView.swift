import SwiftUI

// MARK: - Kanban Board View

struct KanbanBoardView: View {
    @Environment(DocumentStore.self) var store
    @Binding var isPresented: Bool
    @State private var ideasFiles: [URL] = []
    @State private var draftsFiles: [URL] = []
    @State private var reviewFiles: [URL] = []

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "rectangle.3.group")
                    .foregroundStyle(.secondary)
                Text("Kanban Board")
                    .font(Theme.uiSwiftUIFont(size: 16, weight: .semibold))
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(12)

            Divider()

            // Columns
            HStack(alignment: .top, spacing: 12) {
                KanbanColumn(
                    title: "Ideas",
                    files: $ideasFiles,
                    folderName: "Ideas",
                    store: store,
                    onOpen: openNote,
                    onArchive: archiveNote,
                    onDrop: handleDrop
                )
                KanbanColumn(
                    title: "Drafts",
                    files: $draftsFiles,
                    folderName: "Drafts",
                    store: store,
                    onOpen: openNote,
                    onArchive: archiveNote,
                    onDrop: handleDrop
                )
                KanbanColumn(
                    title: "Ready for Review",
                    files: $reviewFiles,
                    folderName: "Ready for Review",
                    store: store,
                    onOpen: openNote,
                    onArchive: archiveNote,
                    onDrop: handleDrop
                )
            }
            .padding(12)
        }
        .frame(width: 780)
        .frame(minHeight: 400)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 8)
        .onAppear {
            store.bootstrapKanbanFolders()
            reloadAll()
        }
        .background {
            KeyboardHandler(
                onUp: {},
                onDown: {},
                onEscape: { isPresented = false }
            )
        }
    }

    private func reloadAll() {
        ideasFiles = store.kanbanFiles(in: "Ideas")
        draftsFiles = store.kanbanFiles(in: "Drafts")
        reviewFiles = store.kanbanFiles(in: "Ready for Review")
    }

    private func openNote(_ url: URL) {
        store.open(url)
        isPresented = false
    }

    private func archiveNote(_ url: URL) {
        guard let workspace = store.workspace else { return }
        let archiveFolder = workspace.appendingPathComponent(
            DocumentStore.kanbanArchive
        )
        store.moveFile(from: url, to: archiveFolder)
        reloadAll()
    }

    private func handleDrop(_ url: URL, _ targetFolder: String) {
        guard let workspace = store.workspace else { return }
        let targetURL = workspace.appendingPathComponent(targetFolder)
        store.moveFile(from: url, to: targetURL)
        reloadAll()
    }
}

// MARK: - Kanban Column

private struct KanbanColumn: View {
    let title: String
    @Binding var files: [URL]
    let folderName: String
    var store: DocumentStore
    let onOpen: (URL) -> Void
    let onArchive: (URL) -> Void
    let onDrop: (URL, String) -> Void
    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(Theme.uiSwiftUIFont(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(files.count)")
                    .font(Theme.uiSwiftUIFont(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 4)

            ScrollView {
                VStack(spacing: 6) {
                    if files.isEmpty {
                        Text("No notes")
                            .font(Theme.uiSwiftUIFont(size: 12))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                    } else {
                        ForEach(files, id: \.self) { fileURL in
                            KanbanCard(
                                fileURL: fileURL,
                                tags: store.tagIndex.tags(for: fileURL),
                                onOpen: { onOpen(fileURL) },
                                onArchive: { onArchive(fileURL) }
                            )
                            .draggable(fileURL)
                        }
                    }
                }
                .padding(4)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(isDropTargeted ? 0.06 : 0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    Color.accentColor,
                    lineWidth: isDropTargeted ? 2 : 0
                )
        )
        .dropDestination(for: URL.self) { urls, _ in
            guard let sourceURL = urls.first else { return false }
            onDrop(sourceURL, folderName)
            return true
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
    }
}

// MARK: - Kanban Card

private struct KanbanCard: View {
    let fileURL: URL
    let tags: Set<String>
    let onOpen: () -> Void
    let onArchive: () -> Void
    @State private var isHovering = false

    private var noteTitle: String {
        fileURL.deletingPathExtension().lastPathComponent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(noteTitle)
                    .font(Theme.uiSwiftUIFont(size: 13, weight: .medium))
                    .lineLimit(2)
                Spacer()
                if isHovering {
                    Button {
                        onArchive()
                    } label: {
                        Image(systemName: "archivebox")
                            .font(Theme.uiSwiftUIFont(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Archive")
                    .transition(.opacity)
                }
            }

            if !tags.isEmpty {
                let sortedTags = tags.sorted().prefix(4)
                HStack(spacing: 4) {
                    ForEach(Array(sortedTags), id: \.self) { tag in
                        Text("#\(tag)")
                            .font(Theme.uiSwiftUIFont(size: 10))
                            .foregroundColor(.teal)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(.teal.opacity(0.12))
                            )
                    }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(.windowBackgroundColor))
        )
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
    }
}
