import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    private enum Layout {
        static let headerLeadingCollapsed: CGFloat = 200
        static let headerLeadingExpanded: CGFloat = 16
        static let headerTopCollapsed: CGFloat = 32
        static let headerTopExpanded: CGFloat = 10
    }

    @Environment(DocumentStore.self) var store
    @Environment(\.openWindow) private var openWindow
    @State private var dismissedSetup = false
    @State private var selectionByDocument: [URL: EditorSelectionContext] = [:]
    @State private var isEmailDropTargeted = false

    // MARK: - Sidebar Content

    @ViewBuilder
    private var sidebarContent: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            Spacer().frame(height: 36)

            if store.workspace == nil {
                VStack(spacing: 12) {
                    Image(systemName: "folder.badge.plus")
                        .font(Theme.uiSwiftUIFont(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No workspace open")
                        .foregroundStyle(.secondary)
                    Button("Open Workspace...") { store.pickWorkspace() }
                        .keyboardShortcut("o")
                        .keyboardShortcutHint("⌘O")
                }
                .frame(maxHeight: .infinity)
            } else {
                VStack(spacing: 4) {
                    SidebarModeButton(
                        label: "Daily Notes", icon: "square.and.pencil",
                        mode: .dailyNotes, isSelected: store.detailMode == .dailyNotes
                    ) { store.activateDailyNotes() }

                    SidebarModeButton(
                        label: "Search", icon: "magnifyingglass",
                        mode: .search, isSelected: store.detailMode == .search
                    ) { store.selectSearchTab() }

                    SidebarModeButton(
                        label: "Links", icon: "link",
                        mode: .links, isSelected: store.detailMode == .links
                    ) { store.selectLinksTab() }

                    SidebarModeButton(
                        label: "Media", icon: "photo.on.rectangle",
                        mode: .media, isSelected: store.detailMode == .media
                    ) { store.selectMediaTab() }

                    SidebarModeButton(
                        label: "Kanban", icon: "rectangle.3.group",
                        mode: .kanban, isSelected: store.detailMode == .kanban
                    ) { store.showKanbanModal() }
                }
                .font(Theme.sidebarSwiftUIFont(size: 14))
                .padding(.horizontal, 12)
                .padding(.bottom, 16)

                Text(store.workspace?.lastPathComponent.uppercased() ?? "WORKSPACE")
                    .font(Theme.sidebarSwiftUIFont(size: 11, weight: .medium))
                    .foregroundStyle(.quaternary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)

                List {
                    FileTreeView(nodes: store.fileTree, store: store, isRoot: true)
                        .id(store.workspace)
                        .contextMenu {
                            if let workspace = store.workspace {
                                Button {
                                    store.promptNewFolder(in: workspace)
                                } label: {
                                    Label("New Folder...", systemImage: "folder.badge.plus")
                                }
                            }
                        }
                }
                .font(Theme.sidebarSwiftUIFont(size: 13))
                .listStyle(.sidebar)
                .listRowSeparator(.hidden)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
                .contentMargins(.bottom, 0, for: .scrollContent)
                .contentTransition(.identity)
                .transaction { $0.animation = nil }
            }
        }
    }

    // MARK: - Detail Content

    @ViewBuilder
    private var detailContent: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            if store.needsKiroSetup && store.workspace != nil && !dismissedSetup {
                KiroSetupBanner {
                    store.bootstrapKiroConfig()
                } onDismiss: {
                    dismissedSetup = true
                }
            }

            if store.detailMode == .dailyNotes {
                DailyNotesView()
            } else if store.detailMode == .search {
                DedicatedSearchView()
            } else if store.detailMode == .links {
                LinksView()
            } else if store.detailMode == .media {
                MediaGridView()
            } else if store.detailMode == .kanban {
                KanbanBoardView()
            } else if !store.openFiles.isEmpty, store.currentIndex >= 0 {
                let currentDoc = store.openFiles[store.currentIndex]
                let chatState = store.chatState(for: currentDoc.url)
                let selectionContext = selectionByDocument[currentDoc.url]
                let chatVisible = store.isChatVisibleForCurrentTab
                let chatView = DocumentChatTray(
                    chatState: chatState,
                    documentURL: currentDoc.url,
                    documentContent: currentDoc.content.string,
                    selectedText: selectionContext?.selectedText,
                    selectedLineRange: selectionContext?.selectedLineRange,
                    selectedImageURL: nil
                )

                let editorBlock = VStack(spacing: 0) {
                    Text(currentDoc.url.deletingPathExtension().lastPathComponent)
                        .font(Theme.sidebarSwiftUIFont(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(
                            .leading,
                            store.columnVisibility == .detailOnly
                                ? Layout.headerLeadingCollapsed : Layout.headerLeadingExpanded
                        )
                        .padding(.trailing, Layout.headerLeadingExpanded)
                        .padding(
                            .top,
                            store.columnVisibility == .detailOnly
                                ? Layout.headerTopCollapsed : Layout.headerTopExpanded
                        )
                        .padding(.bottom, 4)

                    ZStack(alignment: .bottom) {
                    EditorViewSimple { documentURL, selectedText, selectedLineRange in
                        let trimmedText = selectedText.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        if trimmedText.isEmpty {
                            selectionByDocument.removeValue(forKey: documentURL)
                        } else {
                            selectionByDocument[documentURL] = EditorSelectionContext(
                                selectedText: selectedText,
                                selectedLineRange: selectedLineRange
                            )
                        }
                    }
                        .id(currentDoc.url)
                        .overlay(alignment: .topTrailing) {
                            Button {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    store.toggleBacklinks()
                                }
                            } label: {
                                Image(systemName: "link")
                                    .font(Theme.uiSwiftUIFont(size: 14))
                                    .foregroundStyle(
                                        store.showBacklinks ? .primary : .secondary
                                    )
                                    .padding(8)
                            }
                            .buttonStyle(.plain)
                            .glassEffect(.regular.interactive())
                            .padding(12)
                        }

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
                        .padding(.bottom, chatVisible ? 8 : 16)
                    }
                    }
                }

                if store.chatPlacement == .trailing && chatVisible {
                    HStack(spacing: 0) {
                        editorBlock
                        chatView
                            .frame(width: store.chatWidth)
                            .padding(.vertical, 8)
                            .padding(.trailing, 8)
                            .transition(
                                .move(edge: .trailing).combined(with: .opacity)
                            )
                    }
                } else {
                    editorBlock
                    if chatVisible {
                        chatView
                            .padding(.horizontal, 12)
                            .padding(.bottom, 8)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
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
                        .font(Theme.uiSwiftUIFont(size: 16))
                        .padding(10)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive())
                .keyboardShortcutHint("⌘J")
                .padding(12)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let emlURL = urls.first,
                  emlURL.pathExtension.lowercased() == "eml"
            else { return false }
            store.newEmailNote(from: emlURL)
            return true
        } isTargeted: { targeted in
            isEmailDropTargeted = targeted
        }
        .overlay {
            if isEmailDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        Color.accentColor,
                        style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                    )
                    .background(Color.accentColor.opacity(0.05))
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
    }

    var body: some View {
        @Bindable var store = store
        HStack(spacing: 0) {
            // MARK: - Sidebar
            if store.columnVisibility != .detailOnly {
                sidebarContent
                    .frame(width: 280)
                    .background(.ultraThinMaterial)
            }

            // MARK: - Detail
            detailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: .black.opacity(0.08), radius: 4, x: -2, y: 0)
        }
        .frame(minWidth: 800, minHeight: 500)
        .overlay(alignment: .topLeading) {
            HStack(spacing: 12) {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        store.columnVisibility = store.columnVisibility == .detailOnly
                            ? .all : .detailOnly
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Toggle Sidebar")

                Button {
                    store.pickWorkspace()
                } label: {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcutHint("⌘O")

                Button {
                    openWindow(id: "synth-settings-window")
                } label: {
                    Image(systemName: "gearshape")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Settings")
                .keyboardShortcutHint("⌘,")
            }
            .padding(.leading, 84)
            .padding(.top, 10)
        }
        .ignoresSafeArea()
        .background(Color(.windowBackgroundColor))
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
        .alert("New Folder", isPresented: Binding(
            get: { store.newFolderParent != nil },
            set: { if !$0 { store.newFolderParent = nil } }
        )) {
            TextField("Folder name", text: $store.newFolderName)
            Button("Cancel", role: .cancel) { store.newFolderParent = nil }
            Button("Create") { store.confirmNewFolder() }
        } message: {
            Text("Enter a name for the new folder")
        }
        .alert(
            "Delete Folder",
            isPresented: Binding(
                get: {
                    store.pendingDeleteTarget != nil && store.pendingDeleteIsDirectory
                },
                set: { shouldShow in
                    if !shouldShow {
                        store.cancelPendingDelete()
                    }
                }
            )
        ) {
            Button("Cancel", role: .cancel) {
                store.cancelPendingDelete()
            }
            Button("Delete Folder", role: .destructive) {
                _ = store.confirmPendingDelete()
            }
        } message: {
            Text(
                "Delete \"\(store.pendingDeleteName)\" and all of its contents? This cannot be undone."
            )
        }
        .fileImporter(
            isPresented: $store.showWorkspacePicker,
            allowedContentTypes: [.folder]
        ) { result in
            if case .success(let url) = result {
                store.setWorkspace(url)
            }
        }
        .fileExporter(
            isPresented: $store.showDocxExport,
            document: store.docxExportData.map { DocxExportDocument(data: $0) },
            contentType: UTType(filenameExtension: "docx") ?? .data,
            defaultFilename: store.currentDocumentURL?
                .deletingPathExtension().lastPathComponent.appending(".docx") ?? "Export.docx"
        ) { _ in
            store.docxExportData = nil
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
                    _ = store.deleteMedia(mediaURL)
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

    private var displayName: String {
        if node.isDirectory { return node.name }
        return node.url.deletingPathExtension().lastPathComponent
    }

    var body: some View {
        HStack {
            Label(displayName, systemImage: node.isDirectory ? "folder" : "doc.text")
            Spacer()
        }
        .padding(.vertical, 1)
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
    var isRoot: Bool = false
    @State private var isRootDropTargeted = false

    var body: some View {
        ForEach(nodes) { node in
            FileNodeView(node: node, store: store)
        }
        // Drop zone for moving items to workspace root
        if isRoot, let workspace = store.workspace {
            Rectangle()
                .fill(isRootDropTargeted ? Color.accentColor.opacity(0.1) : Color.clear)
                .frame(height: isRootDropTargeted ? 32 : 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(
                            style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])
                        )
                        .foregroundStyle(Color.accentColor)
                        .opacity(isRootDropTargeted ? 1 : 0)
                )
                .dropDestination(for: URL.self) { urls, _ in
                    guard let sourceURL = urls.first else { return false }
                    _ = store.moveFile(from: sourceURL, to: workspace)
                    return true
                } isTargeted: { targeted in
                    isRootDropTargeted = targeted
                }
                .animation(.easeInOut(duration: 0.15), value: isRootDropTargeted)
        }
    }
}

struct FileNodeView: View {
    let node: FileTreeNode
    var store: DocumentStore
    @State private var isDropTargeted = false
    @State private var expandTimer: Timer?

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
                    .onDrop(of: [.plainText], isTargeted: nil) { providers in
                        guard let provider = providers.first else { return false }
                        _ = provider.loadObject(ofClass: NSString.self) { path, _ in
                            guard let path = path as? String else { return }
                            DispatchQueue.main.async {
                                _ = store.moveFile(
                                    from: URL(fileURLWithPath: path),
                                    to: node.url
                                )
                            }
                        }
                        return true
                    }
                    .contextMenu {
                        Button {
                            store.promptNewFolder(in: node.url)
                        } label: {
                            Label("New Folder...", systemImage: "folder.badge.plus")
                        }
                        Button {
                            store.promptRename(node.url)
                        } label: {
                            Label("Rename Folder...", systemImage: "pencil")
                        }
                        Divider()
                        Button(role: .destructive) {
                            store.requestDelete(node.url, isDirectory: true)
                        } label: {
                            Label("Delete Folder...", systemImage: "trash")
                        }
                    }
            }
            .draggable(node)
            .dropDestination(for: URL.self) { urls, _ in
                guard let sourceURL = urls.first else { return false }
                _ = store.moveFile(from: sourceURL, to: node.url)
                return true
            } isTargeted: { targeted in
                isDropTargeted = targeted
                if targeted {
                    expandTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { _ in
                        Task { @MainActor in
                            store.expandedFolders.insert(node.url)
                        }
                    }
                } else {
                    expandTimer?.invalidate()
                    expandTimer = nil
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.accentColor, lineWidth: 2)
                    .opacity(isDropTargeted ? 1 : 0)
            )
        } else {
            Button { store.open(node.url) } label: {
                FileRow(node: node, isOpen: store.openFiles.contains { $0.url == node.url })
            }
            .buttonStyle(.plain)
            .onDrag { NSItemProvider(object: node.url.path as NSString) }
                .contextMenu {
                    Button {
                        store.promptRename(node.url)
                    } label: {
                        Label("Rename File...", systemImage: "pencil")
                    }
                    Divider()
                    Button(role: .destructive) {
                        store.requestDelete(node.url, isDirectory: false)
                    } label: {
                        Label("Delete File", systemImage: "trash")
                    }
                }
                .draggable(node)
        }
    }
}

// MARK: - Kiro Setup Banner

struct KiroSetupBanner: View {
    let onSetup: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(Theme.uiSwiftUIFont(size: 16))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Set up AI for this workspace")
                    .font(Theme.uiSwiftUIFont(size: 13, weight: .medium))
                Text("Create .kiro/ with steering context and agents")
                    .font(Theme.uiSwiftUIFont(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Initialize", action: onSetup)
                .controlSize(.small)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(Theme.uiSwiftUIFont(size: 10))
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
    @Environment(TemplateStore.self) var templateStore
    @AppStorage("hideSyntax") private var hideSyntax = true
    @State private var text: String = ""
    @State private var linePositions: [CGFloat] = []
    @State private var scrollOffset: CGFloat = 0
    @State private var selectedText: String = ""
    @State private var selectedLineRange: String = ""
    var onSelectionChange: ((URL, String, String) -> Void)?

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
                LineNumberGutter(
                    linePositions: linePositions,
                    scrollOffset: scrollOffset
                )
                    .frame(width: 44)
                    .background(Color(.textBackgroundColor))

                MarkdownEditor(
                    text: $text,
                    scrollOffset: $scrollOffset,
                    linePositions: $linePositions,
                    selectedText: $selectedText,
                    selectedLineRange: $selectedLineRange,
                    hideSyntax: hideSyntax,
                    store: store,
                    templateStore: templateStore
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
                .scrollIndicators(.hidden)
                .frame(width: 260)
                .background(Color(.textBackgroundColor).opacity(0.5))
            }
        }
        .onChange(of: selectedText) { _, _ in
            publishSelectionContext()
        }
        .onChange(of: selectedLineRange) { _, _ in
            publishSelectionContext()
        }
        .onChange(of: store.currentIndex) { _, _ in loadText() }
        .onChange(of: store.openFiles[safe: store.currentIndex]?.contentVersion) { _, newVersion in
            // Reload when file content changes externally (e.g., Kiro agent edit)
            guard newVersion != nil else { return }
            guard store.currentIndex >= 0,
                  store.currentIndex < store.openFiles.count else { return }
            let newValue = store.openFiles[store.currentIndex].content.string
            if newValue != text {
                text = newValue
            }
        }
        .onChange(of: text) { _, _ in saveText() }
        .onAppear { loadText() }
    }

    func loadText() {
        guard store.currentIndex >= 0 && store.currentIndex < store.openFiles.count else { return }
        text = store.openFiles[store.currentIndex].content.string
        selectedText = ""
        selectedLineRange = ""
        publishSelectionContext()
    }

    func saveText() {
        guard store.currentIndex >= 0 && store.currentIndex < store.openFiles.count else { return }
        store.updateContent(NSAttributedString(string: text))
    }

    private func publishSelectionContext() {
        guard let currentNoteURL = currentNoteURL else { return }
        onSelectionChange?(currentNoteURL, selectedText, selectedLineRange)
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
                            .font(Theme.terminalSwiftUIFont(size: 11))
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

struct LineNumberMetrics {
    static func clampedScrollOffset(
        scrollOffset: CGFloat,
        documentHeight: CGFloat,
        viewportHeight: CGFloat,
        minimumHeightEpsilon: CGFloat = 0.5
    ) -> CGFloat {
        guard documentHeight > viewportHeight + minimumHeightEpsilon else { return 0 }
        let maxOffset = max(0, documentHeight - viewportHeight)
        return min(max(scrollOffset, 0), maxOffset)
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
                        .font(Theme.uiSwiftUIFont(size: 13, weight: .semibold))
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
        .scrollIndicators(.hidden)
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
        _ = store.deleteMedia(mediaURL)
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
                    .font(Theme.uiSwiftUIFont(size: 14, weight: .semibold))
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
                        .font(Theme.uiSwiftUIFont(size: 18))
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
                        .font(Theme.uiSwiftUIFont(size: 11))
                    ForEach(
                        referencingNotes,
                        id: \.url
                    ) { note in
                        Button(note.title) {
                            onNavigate(note.url)
                        }
                        .buttonStyle(.link)
                        .font(Theme.uiSwiftUIFont(size: 12))
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
                                .font(Theme.uiSwiftUIFont(size: 11))
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
                                .font(Theme.uiSwiftUIFont(size: 11))
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
                .font(Theme.uiSwiftUIFont(size: 12, weight: .medium))
                .lineLimit(2)
            Text("media/\(mediaURL.lastPathComponent)")
                .font(Theme.uiSwiftUIFont(size: 11))
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
