import SwiftUI
import AppKit

extension Notification.Name {
    static let toggleSidebar = Notification.Name("toggleSidebar")
    static let toggleChat = Notification.Name("toggleChat")
    static let showFileLauncher = Notification.Name("showFileLauncher")
    static let showLinkCapture = Notification.Name("showLinkCapture")
    static let reloadEditor = Notification.Name("reloadEditor")
    static let showMeetingNote = Notification.Name("showMeetingNote")
}

enum ActiveModal: Equatable {
    case fileLauncher
    case linkCapture
    case meetingNote
}

struct ContentView: View {
    @EnvironmentObject var store: DocumentStore
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var activeModal: ActiveModal?
    @State private var dismissedSetup = false

    private func modalBinding(_ modal: ActiveModal) -> Binding<Bool> {
        Binding(
            get: { activeModal == modal },
            set: { newValue in
                activeModal = newValue ? modal : nil
            }
        )
    }

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
                TabButton(
                    title: "Links",
                    isSelected: store.isLinksTabSelected,
                    isDirty: false,
                    onSelect: { store.selectLinksTab() },
                    onClose: nil
                )
            }
        }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
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

                if store.isLinksTabSelected {
                    LinksView()
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
                                        store.objectWillChange.send()
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
                if !store.isChatVisibleForCurrentTab && !store.openFiles.isEmpty && !store.isLinksTabSelected {
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
            if activeModal != nil {
                Color.primary.opacity(0.05)
                    .ignoresSafeArea()
                    .onTapGesture { activeModal = nil }

                ZStack {
                    if activeModal == .fileLauncher {
                        FileLauncher(isPresented: modalBinding(.fileLauncher))
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }

                    if activeModal == .linkCapture {
                        LinkCaptureView(isPresented: modalBinding(.linkCapture))
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }

                    if activeModal == .meetingNote {
                        MeetingNoteView(isPresented: modalBinding(.meetingNote))
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }
                }
            }
        }
        .animation(.easeOut(duration: 0.15), value: activeModal)
        .animation(.easeOut(duration: 0.2), value: store.isChatVisibleForCurrentTab)
        .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in
            withAnimation {
                columnVisibility = columnVisibility == .all ? .detailOnly : .all
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleChat)) { _ in
            withAnimation {
                store.toggleChatForCurrentTab()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showFileLauncher)) { _ in
            activeModal = .fileLauncher
        }
        .onReceive(NotificationCenter.default.publisher(for: .showLinkCapture)) { _ in
            activeModal = .linkCapture
        }
        .onReceive(NotificationCenter.default.publisher(for: .showMeetingNote)) { _ in
            activeModal = .meetingNote
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
    @ObservedObject var store: DocumentStore

    var body: some View {
        ForEach(nodes) { node in
            FileNodeView(node: node, store: store)
        }
    }
}

struct FileNodeView: View {
    let node: FileTreeNode
    @ObservedObject var store: DocumentStore

    private var isExpanded: Binding<Bool> {
        Binding(
            get: { store.expandedFolders.contains(node.url) },
            set: { newValue in
                if newValue {
                    store.expandedFolders.insert(node.url)
                } else {
                    store.expandedFolders.remove(node.url)
                }
            }
        )
    }

    var body: some View {
        if node.isDirectory {
            DisclosureGroup(isExpanded: isExpanded) {
                if let children = node.children {
                    FileTreeView(nodes: children, store: store)
                }
            } label: {
                FileRow(node: node, isOpen: false)
                    .contentShape(Rectangle())
                    .onTapGesture { isExpanded.wrappedValue.toggle() }
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
    @EnvironmentObject var store: DocumentStore
    @State private var text: String = ""
    @State private var linePositions: [CGFloat] = []
    @State private var scrollOffset: CGFloat = 0
    @State private var selectedText: String = ""
    @State private var selectedLineRange: String = ""

    var body: some View {
        HStack(spacing: 0) {
            LineNumberGutter(linePositions: linePositions, scrollOffset: scrollOffset)
                .frame(width: 44)
                .background(Color(nsColor: .textBackgroundColor))

            MarkdownEditor(
                text: $text,
                scrollOffset: $scrollOffset,
                linePositions: $linePositions,
                selectedText: $selectedText,
                selectedLineRange: $selectedLineRange
            )
            .background(Color(nsColor: .textBackgroundColor))
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
                            .foregroundColor(Color(nsColor: .tertiaryLabelColor))
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
