import SwiftUI

struct FileLauncher: View {
    @EnvironmentObject var store: DocumentStore
    @Binding var isPresented: Bool
    @State private var query = ""
    @State private var selectedIndex = 0
    
    var filteredFiles: [FileTreeNode] {
        let allFiles = flattenFiles(store.fileTree)
        if query.trimmingCharacters(in: .whitespaces).isEmpty { 
            return Array(allFiles.prefix(20)) 
        }
        let q = query.lowercased()
        return allFiles.filter { $0.name.lowercased().contains(q) }
    }
    
    func flattenFiles(_ nodes: [FileTreeNode]) -> [FileTreeNode] {
        var result: [FileTreeNode] = []
        for node in nodes {
            if !node.isDirectory { result.append(node) }
            if let children = node.children {
                result.append(contentsOf: flattenFiles(children))
            }
        }
        return result
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                QuickOpenField(
                    text: $query,
                    onArrowUp: { selectedIndex = max(0, selectedIndex - 1) },
                    onArrowDown: { selectedIndex = min(filteredFiles.count - 1, selectedIndex + 1) },
                    onEnter: { openSelected() },
                    onEscape: { isPresented = false }
                )
            }
            .padding(12)
            
            Divider()
            
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(filteredFiles.enumerated()), id: \.element.id) { index, file in
                            HStack {
                                Image(systemName: "doc.text")
                                    .foregroundStyle(.secondary)
                                Text(file.name)
                                Spacer()
                                Text(file.url.deletingLastPathComponent().lastPathComponent)
                                    .foregroundStyle(.tertiary)
                                    .font(.caption)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(index == selectedIndex ? Color.accentColor.opacity(0.2) : Color.clear)
                            .contentShape(Rectangle())
                            .id(index)
                            .onTapGesture {
                                selectedIndex = index
                                openSelected()
                            }
                        }
                    }
                }
                .onChange(of: selectedIndex) { newValue in
                    withAnimation {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
            .frame(maxHeight: 300)
        }
        .frame(width: 500)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 20)
        .onChange(of: query) { _ in
            selectedIndex = 0
        }
    }
    
    func openSelected() {
        guard selectedIndex >= 0 && selectedIndex < filteredFiles.count else { return }
        store.open(filteredFiles[selectedIndex].url)
        isPresented = false
    }
}

struct QuickOpenField: NSViewRepresentable {
    @Binding var text: String
    var onArrowUp: () -> Void
    var onArrowDown: () -> Void
    var onEnter: () -> Void
    var onEscape: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.delegate = context.coordinator
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.placeholderString = "Search files..."
        textField.font = .systemFont(ofSize: 18)
        DispatchQueue.main.async {
            textField.window?.makeFirstResponder(textField)
        }
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: QuickOpenField

        init(parent: QuickOpenField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else { return }
            parent.text = textField.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                parent.onArrowUp()
                return true
            } else if commandSelector == #selector(NSResponder.moveDown(_:)) {
                parent.onArrowDown()
                return true
            } else if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onEnter()
                return true
            } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onEscape()
                return true
            }
            return false
        }
    }
}
