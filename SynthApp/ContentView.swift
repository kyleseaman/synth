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
                Label(node.name, systemImage: node.isDirectory ? "folder" : "doc.text")
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
                    GlassEffectContainer(spacing: 8) {
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
            }
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
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(isHovering || isSelected ? 1 : 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? .primary : .secondary)
        .glassEffect(isSelected ? .regular : .identity)
        .onHover { isHovering = $0 }
    }
}


struct EditorViewSimple: View {
    @EnvironmentObject var store: DocumentStore
    @State private var text: String = ""
    
    var body: some View {
        TextEditor(text: $text)
            .font(.custom("Georgia", size: 18))
            .foregroundColor(.black)
            .scrollContentBackground(.hidden)
            .background(Color(white: 0.95))
            .onChange(of: store.currentIndex) { _ in
                loadText()
            }
            .onAppear {
                loadText()
            }
    }
    
    func loadText() {
        guard store.currentIndex >= 0 && store.currentIndex < store.openFiles.count else { return }
        text = store.openFiles[store.currentIndex].content.string
    }
}
