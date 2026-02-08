import SwiftUI
import AppKit

extension Notification.Name {
    static let reloadEditor = Notification.Name("reloadEditor")

    // MARK: - Wiki Link Notifications
    static let wikiLinkTrigger = Notification.Name("wikiLinkTrigger")
    static let wikiLinkDismiss = Notification.Name("wikiLinkDismiss")
    static let wikiLinkQueryUpdate = Notification.Name("wikiLinkQueryUpdate")
    static let wikiLinkSelect = Notification.Name("wikiLinkSelect")
    static let wikiLinkNavigate = Notification.Name("wikiLinkNavigate")

    // MARK: - Daily Notes
    static let showDailyDate = Notification.Name("showDailyDate")
}

struct ContentView: View {
    @Environment(DocumentStore.self) var store
    @State private var dismissedSetup = false

    private var openWorkspaceButton: some CustomizableToolbarContent {
        ToolbarItem(id: "openWorkspace", placement: .automatic) {
            Button {
                store.pickWorkspace()
            } label: {
                Image(systemName: "folder")
            }
            .help("Open Workspace (⌘O)")
        }
    }

    private var tabBar: some CustomizableToolbarContent {
        ToolbarItem(id: "tabBar", placement: .principal) {
            HStack(spacing: 4) {
                ForEach(store.openFiles.indices, id: \.self) { index in
                    TabButton(
                        title: store.openFiles[index].url.lastPathComponent,
                        isSelected: index == store.currentIndex,
                        isDirty: store.openFiles[index].isDirty,
                        onSelect: { store.switchTo(index) },
                        onClose: { store.closeTab(at: index) }
                    )
                }
            }
        }
    }

    var body: some View {
        @Bindable var store = store
        NavigationSplitView(columnVisibility: $store.columnVisibility) {
            VStack {
                if store.workspace == nil {
                    VStack(spacing: 12) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                        Text("No workspace open")
                            .foregroundStyle(.secondary)
                        Button("Open Workspace...") { store.pickWorkspace() }
                            .keyboardShortcut("o")
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    List {
                        // MARK: - Daily Notes sidebar button
                        Button {
                            store.activateDailyNotes()
                        } label: {
                            Label("Daily Notes", systemImage: "square.and.pencil")
                                .fontWeight(
                                    store.detailMode == .dailyNotes ? .semibold : .regular
                                )
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 6)
                        .background(
                            store.detailMode == .dailyNotes
                                ? Color.accentColor.opacity(0.15)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6)
                        )

                        // MARK: - Links sidebar button
                        Button {
                            store.selectLinksTab()
                        } label: {
                            Label("Links", systemImage: "link")
                                .fontWeight(
                                    store.detailMode == .links ? .semibold : .regular
                                )
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 6)
                        .background(
                            store.detailMode == .links
                                ? Color.accentColor.opacity(0.15)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6)
                        )

                        // MARK: - Media sidebar button
                        Button {
                            store.selectMediaTab()
                        } label: {
                            Label("Media", systemImage: "photo.on.rectangle")
                                .fontWeight(
                                    store.detailMode == .media ? .semibold : .regular
                                )
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 6)
                        .background(
                            store.detailMode == .media
                                ? Color.accentColor.opacity(0.15)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6)
                        )

                        FileTreeView(nodes: store.fileTree, store: store)
                    }
                    .listStyle(.sidebar)
                    .contentTransition(.identity)
                    .transaction { $0.animation = nil }
                }
            }
            .navigationTitle(store.workspace?.lastPathComponent ?? "Files")
            .navigationSplitViewColumnWidth(min: 250, ideal: 320, max: 500)
            .toolbar(id: "sidebar") {
                openWorkspaceButton
            }
        } detail: {
            VStack(spacing: 0) {
                // Kiro setup banner
                if store.needsKiroSetup && store.workspace != nil && !dismissedSetup {
                    KiroSetupBanner {
                        store.bootstrapKiroConfig()
                    } onDismiss: {
                        dismissedSetup = true
                    }
                }

                if store.detailMode == .dailyNotes {
                    DailyNotesView()
                } else if store.detailMode == .links {
                    LinksView()
                } else if store.detailMode == .media {
                    MediaGridView()
                } else if !store.openFiles.isEmpty, store.currentIndex >= 0 {
                    let currentDoc = store.openFiles[store.currentIndex]
                    let chatState = store.chatState(for: currentDoc.url)

                    ZStack(alignment: .bottom) {
                        EditorViewSimple()
                            .id(currentDoc.url)

                        // Undo toast overlay
                        if chatState.undoSnapshot != nil {
                            UndoToast {
                                if let snapshot = chatState.undoSnapshot {
                                    if let idx = store.openFiles.firstIndex(
                                        where: { $0.url == snapshot.url }
                                    ) {
                                        store.openFiles[idx].content = NSAttributedString(
                                            string: snapshot.content
                                        )
                                        store.openFiles[idx].isDirty = true
                                    }
                                    chatState.dismissUndo()
                                }
                            }
                            .padding(.bottom, store.isChatVisibleForCurrentTab ? 8 : 16)
                        }
                    }

                    if store.isChatVisibleForCurrentTab {
                        DocumentChatTray(
                            chatState: chatState,
                            documentURL: currentDoc.url,
                            documentContent: currentDoc.content.string,
                            selectedText: nil,
                            selectedLineRange: nil
                        )
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                } else {
                    Text("Open a file to start editing")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if !store.isChatVisibleForCurrentTab
                    && !store.openFiles.isEmpty
                    && store.detailMode == .editor {
                    Button {
                        store.toggleChatForCurrentTab()
                    } label: {
                        Image(systemName: "sparkles")
                            .font(.system(size: 16))
                            .padding(10)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive())
                    .padding(12)
                }
            }
            .toolbar(id: "tabs") {
                tabBar
            }
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        }
        .frame(minWidth: 800, minHeight: 500)
        .overlay {
            if store.activeModal != nil {
                Color.primary.opacity(0.05)
                    .ignoresSafeArea()
                    .onTapGesture {
                        store.activeModal = nil
                    }

                ZStack {
                    if store.activeModal == .fileLauncher {
                        FileLauncher(isPresented: Binding(
                            get: { store.activeModal == .fileLauncher },
                            set: { if !$0 { store.activeModal = nil } }
                        ))
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }

                    if store.activeModal == .linkCapture {
                        LinkCaptureView(isPresented: Binding(
                            get: { store.activeModal == .linkCapture },
                            set: { if !$0 { store.activeModal = nil } }
                        ))
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }

                    if store.activeModal == .meetingNote {
                        MeetingNoteView(isPresented: Binding(
                            get: { store.activeModal == .meetingNote },
                            set: { if !$0 { store.activeModal = nil } }
                        ))
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }

                    if case .tagBrowser(let tag) = store.activeModal {
                        TagBrowserView(
                            isPresented: Binding(
                                get: { store.activeModal != nil },
                                set: { if !$0 { store.activeModal = nil } }
                            ),
                            initialTag: tag
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }

                    if case .peopleBrowser(let person) = store.activeModal {
                        PeopleBrowserView(
                            isPresented: Binding(
                                get: { store.activeModal != nil },
                                set: { if !$0 { store.activeModal = nil } }
                            ),
                            initialPerson: person
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }
                }
            }
        }
        .animation(.easeOut(duration: 0.15), value: store.activeModal)
        .animation(.easeOut(duration: 0.2), value: store.isChatVisibleForCurrentTab)
        .alert("Rename", isPresented: Binding(
            get: { store.renameTarget != nil },
            set: { if !$0 { store.renameTarget = nil } }
        )) {
            TextField("Name", text: $store.renameText)
            Button("Cancel", role: .cancel) { store.renameTarget = nil }
            Button("Rename") { store.confirmRename() }
        } message: {
            Text("Enter a new name")
        }
        .fileImporter(
            isPresented: $store.showWorkspacePicker,
            allowedContentTypes: [.folder]
        ) { result in
            if case .success(let url) = result {
                store.setWorkspace(url)
            }
        }
        .sheet(item: $store.imageDetailURL) { mediaURL in
            MediaDetailView(
                mediaURL: mediaURL,
                referencingNotes: store.notesReferencing(
                    mediaFilename: mediaURL.lastPathComponent
                ),
                onCopy: {
                    if let img = NSImage(contentsOf: mediaURL) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.writeObjects([img])
                    }
                },
                onDelete: {
                    store.imageDetailURL = nil
                    try? FileManager.default.trashItem(
                        at: mediaURL, resultingItemURL: nil
                    )
                    store.loadFileTree()
                },
                onNavigate: { noteURL in
                    store.imageDetailURL = nil
                    store.open(noteURL)
                }
            )
        }
    }
}

// MARK: - File Tree Views

struct FileRow: View {
    let node: FileTreeNode
    let isOpen: Bool
    @State private var isHovering = false

    var body: some View {
        HStack {
            Label(node.name, systemImage: node.isDirectory ? "folder" : "doc.text")
                .fontWeight(isOpen ? .semibold : .regular)
            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isHovering ? Color.accentColor.opacity(0.15) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
        .onHover { isHovering = $0 }
    }
}

struct FileTreeView: View {
    let nodes: [FileTreeNode]
    var store: DocumentStore

    var body: some View {
        ForEach(nodes) { node in
            FileNodeView(node: node, store: store)
        }
    }
}

struct FileNodeView: View {
    let node: FileTreeNode
    var store: DocumentStore

    var body: some View {
        @Bindable var store = store
        if node.isDirectory {
            DisclosureGroup(isExpanded: Binding(
                get: { store.expandedFolders.contains(node.url) },
                set: { newValue in
                    if newValue {
                        store.expandedFolders.insert(node.url)
                    } else {
                        store.expandedFolders.remove(node.url)
                    }
                }
            )) {
                if let children = node.children {
                    FileTreeView(nodes: children, store: store)
                }
            } label: {
                FileRow(node: node, isOpen: false)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if store.expandedFolders.contains(node.url) {
                            store.expandedFolders.remove(node.url)
                        } else {
                            store.expandedFolders.insert(node.url)
                        }
                    }
                    .contextMenu {
                        Button("Rename...") { store.promptRename(node.url) }
                    }
            }
        } else {
            FileRow(node: node, isOpen: store.openFiles.contains { $0.url == node.url })
                .contentShape(Rectangle())
                .onTapGesture { store.open(node.url) }
                .contextMenu {
                    Button("Rename...") { store.promptRename(node.url) }
                    Divider()
                    Button("Delete", role: .destructive) { store.delete(node.url) }
                }
        }
    }
}

// MARK: - Tab Button

struct TabButton: View {
    let title: String
    let isSelected: Bool
    let isDirty: Bool
    let onSelect: () -> Void
    let onClose: (() -> Void)?
    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 12))
                    .lineLimit(1)

                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: isDirty ? "circle.fill" : "xmark")
                            .font(.system(size: isDirty ? 6 : 9, weight: .bold))
                            .foregroundStyle(isDirty ? .orange : .secondary)
                    }
                    .buttonStyle(.plain)
                    .opacity(isHovering || isSelected || isDirty ? 1 : 0)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                if isSelected {
                    Capsule().fill(.ultraThinMaterial)
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? .primary : .secondary)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Kiro Setup Banner

struct KiroSetupBanner: View {
    let onSetup: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 16))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Set up AI for this workspace")
                    .font(.system(size: 13, weight: .medium))
                Text("Create .kiro/ with steering context and agents")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Initialize", action: onSetup)
                .controlSize(.small)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.accentColor.opacity(0.08))
    }
}

// MARK: - Editor View

struct EditorViewSimple: View {
    @Environment(DocumentStore.self) var store
    @State private var text: String = ""
    @State private var linePositions: [CGFloat] = []
    @State private var scrollOffset: CGFloat = 0
    @State private var selectedText: String = ""
    @State private var selectedLineRange: String = ""

    private var currentNoteTitle: String {
        guard store.currentIndex >= 0,
              store.currentIndex < store.openFiles.count else { return "" }
        return store.openFiles[store.currentIndex].url
            .deletingPathExtension().lastPathComponent
    }

    private var currentNoteURL: URL? {
        guard store.currentIndex >= 0,
              store.currentIndex < store.openFiles.count else { return nil }
        return store.openFiles[store.currentIndex].url
    }

    var body: some View {
        HStack(spacing: 0) {
            // Editor
            HStack(spacing: 0) {
                LineNumberGutter(linePositions: linePositions, scrollOffset: scrollOffset)
                    .frame(width: 44)
                    .background(Color(.textBackgroundColor))

                MarkdownEditor(
                    text: $text,
                    scrollOffset: $scrollOffset,
                    linePositions: $linePositions,
                    selectedText: $selectedText,
                    selectedLineRange: $selectedLineRange,
                    store: store
                )
                .background(Color(.textBackgroundColor))
            }

            // Backlinks right sidebar
            if store.showBacklinks {
                Divider()

                ScrollView {
                    VStack(spacing: 0) {
                        BacklinksSection(
                            noteTitle: currentNoteTitle,
                            backlinkIndex: store.backlinkIndex,
                            onNavigate: { url in store.open(url) }
                        )

                        RelatedNotesSection(
                            noteTitle: currentNoteTitle,
                            noteURL: currentNoteURL,
                            backlinkIndex: store.backlinkIndex,
                            tagIndex: store.tagIndex,
                            onNavigate: { url in store.open(url) }
                        )
                    }
                }
                .frame(width: 260)
                .background(Color(.textBackgroundColor).opacity(0.5))
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    store.toggleBacklinks()
                }
            } label: {
                Image(systemName: "link")
                    .font(.system(size: 12))
                    .foregroundStyle(store.showBacklinks ? .primary : .tertiary)
                    .padding(6)
            }
            .buttonStyle(.plain)
            .help("Toggle Backlinks (⌘⇧B)")
            .padding(.top, 4)
            .padding(.trailing, 4)
        }
        .onChange(of: store.currentIndex) { _, _ in loadText() }
        .onChange(of: text) { _, _ in saveText() }
        .onAppear { loadText() }
        .onReceive(NotificationCenter.default.publisher(for: .reloadEditor)) { _ in
            loadText()
        }
    }

    func loadText() {
        guard store.currentIndex >= 0 && store.currentIndex < store.openFiles.count else { return }
        text = store.openFiles[store.currentIndex].content.string
    }

    func saveText() {
        guard store.currentIndex >= 0 && store.currentIndex < store.openFiles.count else { return }
        store.updateContent(NSAttributedString(string: text))
    }
}

struct LineNumberGutter: View {
    let linePositions: [CGFloat]
    let scrollOffset: CGFloat

    var body: some View {
        GeometryReader { _ in
            Canvas { context, size in
                for (lineIndex, yPos) in linePositions.enumerated() {
                    let yOffset = yPos - scrollOffset
                    if yOffset > -20 && yOffset < size.height + 20 {
                        let text = Text("\(lineIndex + 1)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Color(.tertiaryLabelColor))
                        context.draw(
                            text,
                            at: CGPoint(x: size.width - 8, y: yOffset),
                            anchor: .trailing
                        )
                    }
                }
            }
        }
        .clipped()
    }
}

struct MediaGridView: View {
    @Environment(DocumentStore.self) var store
    @State private var selectedMedia: URL?
    private let gridColumns = [
        GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if store.mediaFiles.isEmpty {
                    Text("No screenshots found in /media")
                        .foregroundStyle(.secondary)
                        .padding(.top, 20)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    Text("Screenshots (\(store.mediaFiles.count))")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: gridColumns, spacing: 12) {
                        ForEach(store.mediaFiles, id: \.self) { mediaURL in
                            MediaTile(
                                mediaURL: mediaURL,
                                onCopy: { copyImage(at: mediaURL) },
                                onDelete: { deleteMedia(mediaURL) },
                                onTap: { selectedMedia = mediaURL }
                            )
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Color(.textBackgroundColor))
        .sheet(item: $selectedMedia) { mediaURL in
            MediaDetailView(
                mediaURL: mediaURL,
                referencingNotes: store.notesReferencing(
                    mediaFilename: mediaURL.lastPathComponent
                ),
                onCopy: { copyImage(at: mediaURL) },
                onDelete: {
                    selectedMedia = nil
                    deleteMedia(mediaURL)
                },
                onNavigate: { noteURL in
                    selectedMedia = nil
                    store.open(noteURL)
                }
            )
        }
    }

    private func copyImage(at mediaURL: URL) {
        guard let image = NSImage(contentsOf: mediaURL) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }

    private func deleteMedia(_ mediaURL: URL) {
        try? FileManager.default.trashItem(
            at: mediaURL, resultingItemURL: nil
        )
        store.loadFileTree()
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

// MARK: - Media Detail (fullscreen sheet)

struct MediaDetailView: View {
    let mediaURL: URL
    let referencingNotes: [(title: String, url: URL)]
    let onCopy: () -> Void
    let onDelete: () -> Void
    let onNavigate: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var fullImage: NSImage?

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text(mediaURL.lastPathComponent)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)

                Spacer()

                Button {
                    onCopy()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.bordered)

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Image
            if let fullImage {
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: fullImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity
                        )
                        .padding(20)
                }
            } else {
                Spacer()
                ProgressView()
                Spacer()
            }

            // Referencing notes
            if !referencingNotes.isEmpty {
                Divider()
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 11))
                    ForEach(
                        referencingNotes,
                        id: \.url
                    ) { note in
                        Button(note.title) {
                            onNavigate(note.url)
                        }
                        .buttonStyle(.link)
                        .font(.system(size: 12))
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
        .frame(minWidth: 600, minHeight: 450)
        .background(Color(.windowBackgroundColor))
        .onAppear { loadFullImage() }
    }

    private func loadFullImage() {
        let maxSize = NSSize(width: 1600, height: 1200)
        WorkspaceImageLoader.shared.loadImage(
            at: mediaURL, maxSize: maxSize
        ) { loaded in
            fullImage = loaded
        }
    }
}

// MARK: - Media Tile with hover controls

struct MediaTile: View {
    let mediaURL: URL
    let onCopy: () -> Void
    let onDelete: () -> Void
    let onTap: () -> Void
    @State private var image: NSImage?
    @State private var isLoadingImage = false
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 140)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.12))
                        .frame(height: 140)
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        }
                }

                if isHovering {
                    HStack(spacing: 4) {
                        Button {
                            onCopy()
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 11))
                                .padding(6)
                        }
                        .buttonStyle(.plain)
                        .background(.ultraThickMaterial)
                        .clipShape(Circle())
                        .help("Copy image")

                        Button {
                            onDelete()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundStyle(.red)
                                .padding(6)
                        }
                        .buttonStyle(.plain)
                        .background(.ultraThickMaterial)
                        .clipShape(Circle())
                        .help("Delete image")
                    }
                    .padding(6)
                    .transition(.opacity)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onTap() }
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovering = hovering
                }
            }

            Text(mediaURL.lastPathComponent)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(2)
            Text("media/\(mediaURL.lastPathComponent)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(10)
        .background(Color(.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onAppear {
            loadImageIfNeeded()
        }
        .onChange(of: mediaURL) { _, _ in
            image = nil
            isLoadingImage = false
            loadImageIfNeeded()
        }
    }

    private func loadImageIfNeeded() {
        guard image == nil, !isLoadingImage else { return }
        let maxSize = NSSize(width: 420, height: 280)

        if let cached = WorkspaceImageLoader.shared.cachedImage(at: mediaURL, maxSize: maxSize) {
            image = cached
            return
        }

        isLoadingImage = true
        WorkspaceImageLoader.shared.loadImage(at: mediaURL, maxSize: maxSize) { loadedImage in
            image = loadedImage
            isLoadingImage = false
        }
    }
}
