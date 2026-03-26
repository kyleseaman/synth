import SwiftUI

// MARK: - Kanban Board View

struct KanbanBoardView: View {
    @Environment(DocumentStore.self) var store
    @State private var filesByColumn: [String: [URL]] = [:]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(DocumentStore.kanbanColumns, id: \.self) { column in
                KanbanColumn(
                    title: column,
                    files: Binding(
                        get: { filesByColumn[column] ?? [] },
                        set: { filesByColumn[column] = $0 }
                    ),
                    folderName: column,
                    store: store,
                    onOpen: openNote,
                    onArchive: archiveNote,
                    onDrop: handleDrop
                )
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            store.bootstrapKanbanFolders()
            reloadAll()
        }
    }

    private func reloadAll() {
        for column in DocumentStore.kanbanColumns {
            filesByColumn[column] = store.kanbanFiles(in: column)
        }
    }

    private func openNote(_ url: URL) {
        store.open(url)
        store.detailMode = .editor
    }

    private func archiveNote(_ url: URL) {
        guard let workspace = store.workspace else { return }
        let archiveFolder = workspace.appendingPathComponent(
            DocumentStore.kanbanArchive
        )
        guard store.moveFile(from: url, to: archiveFolder) != nil else { return }
        removeFromColumn(url)
    }

    private func handleDrop(_ url: URL, _ targetFolder: String) {
        filesByColumn = Self.updatedColumnsAfterDrop(
            sourceURL: url,
            targetFolder: targetFolder,
            workspace: store.workspace,
            currentFilesByColumn: filesByColumn,
            moveFile: store.moveFile(from:to:)
        )
    }

    private func removeFromColumn(_ url: URL) {
        for column in DocumentStore.kanbanColumns {
            filesByColumn[column]?.removeAll { $0 == url }
        }
    }

    @MainActor
    static func updatedColumnsAfterDrop(
        sourceURL: URL,
        targetFolder: String,
        workspace: URL?,
        currentFilesByColumn: [String: [URL]],
        moveFile: (URL, URL) -> URL?
    ) -> [String: [URL]] {
        guard let workspace else { return currentFilesByColumn }

        let targetURL = workspace.appendingPathComponent(targetFolder)
        guard let movedURL = moveFile(sourceURL, targetURL) else {
            return currentFilesByColumn
        }

        var updatedFilesByColumn = currentFilesByColumn
        for column in DocumentStore.kanbanColumns {
            updatedFilesByColumn[column]?.removeAll {
                $0 == sourceURL || $0 == movedURL
            }
        }
        updatedFilesByColumn[targetFolder, default: []].append(movedURL)
        updatedFilesByColumn[targetFolder]?.sort {
            $0.lastPathComponent.localizedCaseInsensitiveCompare(
                $1.lastPathComponent
            ) == .orderedAscending
        }
        return updatedFilesByColumn
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
            .scrollIndicators(.never)
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isDropTargeted
                    ? Color.accentColor.opacity(0.12)
                    : Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    Color.accentColor.opacity(isDropTargeted ? 0.6 : 0),
                    lineWidth: 2
                )
        )
        .animation(.easeInOut(duration: 0.15), value: isDropTargeted)
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
