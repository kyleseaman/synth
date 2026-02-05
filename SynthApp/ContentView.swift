import SwiftUI
import AppKit

extension Notification.Name {
    static let toggleSidebar = Notification.Name("toggleSidebar")
    static let toggleChat = Notification.Name("toggleChat")
}

struct ContentView: View {
    @EnvironmentObject var store: DocumentStore
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showChat = false
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(store.fileTree, children: \.children) { node in
                FileRow(node: node, isOpen: store.openFiles.contains { $0.url == node.url })
                    .onTapGesture {
                        if !node.isDirectory {
                            store.open(node.url)
                        }
                    }
            }
            .listStyle(.sidebar)
            .navigationTitle(store.workspace?.lastPathComponent ?? "Files")
        } detail: {
            VStack(spacing: 0) {
                if !store.openFiles.isEmpty {
                    EditorViewSimple()
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
                        ForEach(store.openFiles.indices, id: \.self) { i in
                            TabButton(
                                title: store.openFiles[i].url.lastPathComponent,
                                isSelected: i == store.currentIndex,
                                onSelect: { store.switchTo(i) },
                                onClose: { store.closeTab(at: i) }
                            )
                        }
                    }
                }
            }
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        }
        .frame(minWidth: 800, minHeight: 500)
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
    }
}

struct FileRow: View {
    let node: FileTreeNode
    let isOpen: Bool
    @State private var isHovering = false
    
    var body: some View {
        Label(node.name, systemImage: node.isDirectory ? "folder" : "doc.text")
            .fontWeight(isOpen ? .semibold : .regular)
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
            .background(isHovering ? Color.white.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
            .onHover { isHovering = $0 }
    }
}

struct TabButton: View {
    let title: String
    let isSelected: Bool
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
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(isHovering || isSelected ? 1 : 0)
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
        .onChange(of: store.currentIndex) { _ in loadText() }
        .onChange(of: text) { _ in saveText() }
        .onAppear { loadText() }
    }
    
    func loadText() {
        guard store.currentIndex >= 0 && store.currentIndex < store.openFiles.count else { return }
        let newText = store.openFiles[store.currentIndex].content.string
        if text != newText { text = newText }
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
        GeometryReader { geo in
            Canvas { context, size in
                for (i, yPos) in linePositions.enumerated() {
                    let y = yPos - scrollOffset
                    if y > -20 && y < size.height + 20 {
                        let text = Text("\(i + 1)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                        context.draw(text, at: CGPoint(x: size.width - 8, y: y), anchor: .trailing)
                    }
                }
            }
        }
        .clipped()
    }
}
