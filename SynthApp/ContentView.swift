import SwiftUI
import AppKit

extension Notification.Name {
    static let toggleSidebar = Notification.Name("toggleSidebar")
    static let toggleChat = Notification.Name("toggleChat")
    static let showFileLauncher = Notification.Name("showFileLauncher")
}

struct ContentView: View {
    @EnvironmentObject var store: DocumentStore
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showChat = false
    @State private var showFileLauncher = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List {
                FileTreeView(nodes: store.fileTree, store: store)
            }
            .listStyle(.sidebar)
            .contentTransition(.identity)
            .transaction { $0.animation = nil }
            .navigationTitle(store.workspace?.lastPathComponent ?? "Files")
            .navigationSplitViewColumnWidth(min: 250, ideal: 320, max: 500)
        } detail: {
            VStack(spacing: 0) {
                if !store.openFiles.isEmpty, store.currentIndex >= 0 {
                    EditorViewSimple()
                        .id(store.openFiles[store.currentIndex].url)
                } else {
                    Text("Open a file to start editing")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if showChat {
                    ChatPanel()
                        .frame(height: 200)
                } else {
                    HStack {
                        Spacer()
                        Button {
                            NotificationCenter.default.post(name: .toggleChat, object: nil)
                        } label: {
                            Image(systemName: "terminal")
                                .padding(8)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive())
                    }
                    .padding(8)
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
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
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        }
        .frame(minWidth: 800, minHeight: 500)
        .overlay {
            if showFileLauncher {
                Color.primary.opacity(0.05)
                    .ignoresSafeArea()
                    .onTapGesture { showFileLauncher = false }

                FileLauncher(isPresented: $showFileLauncher)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.easeOut(duration: 0.15), value: showFileLauncher)
        .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in
            withAnimation {
                columnVisibility = columnVisibility == .all ? .detailOnly : .all
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleChat)) { _ in
            withAnimation {
                showChat.toggle()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showFileLauncher)) { _ in
            showFileLauncher = true
        }
    }
}

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
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(isHovering ? Color.primary.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
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

struct TabButton: View {
    let title: String
    let isSelected: Bool
    let isDirty: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 12))
                    .lineLimit(1)

                Button(action: onClose) {
                    Image(systemName: isDirty ? "circle.fill" : "xmark")
                        .font(.system(size: isDirty ? 6 : 9, weight: .bold))
                        .foregroundStyle(isDirty ? .orange : .secondary)
                }
                .buttonStyle(.plain)
                .opacity(isHovering || isSelected || isDirty ? 1 : 0)
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

struct EditorViewSimple: View {
    @EnvironmentObject var store: DocumentStore
    @State private var text: String = ""
    @State private var linePositions: [CGFloat] = []
    @State private var scrollOffset: CGFloat = 0
    var centered: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            LineNumberGutter(linePositions: linePositions, scrollOffset: scrollOffset)
                .frame(width: 44)
                .background(Color(nsColor: .textBackgroundColor))

            MarkdownEditor(text: $text, scrollOffset: $scrollOffset, linePositions: $linePositions)
                .background(Color(nsColor: .textBackgroundColor))
        }
        .onChange(of: text) { saveText() }
        .onAppear { loadText() }
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
                        context.draw(text, at: CGPoint(x: size.width - 8, y: yOffset), anchor: .trailing)
                    }
                }
            }
        }
        .clipped()
    }
}
