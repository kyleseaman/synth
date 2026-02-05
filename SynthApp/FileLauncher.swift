import SwiftUI

extension String {
    func fuzzyMatch(_ query: String) -> Bool {
        if query.isEmpty { return true }
        var remainder = query[...]
        for char in self {
            if char == remainder.first {
                remainder.removeFirst()
                if remainder.isEmpty { return true }
            }
        }
        return false
    }
}

struct FileLauncher: View {
    @EnvironmentObject var store: DocumentStore
    @Binding var isPresented: Bool
    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var isSearchFocused: Bool

    var filteredFiles: [FileTreeNode] {
        let allFiles = flattenFiles(store.fileTree)
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            return Array(allFiles.prefix(20))
        }
        let searchQuery = query.lowercased()
        return allFiles.filter { $0.name.lowercased().fuzzyMatch(searchQuery) }
            .sorted { first, second in
                let firstPrefix = first.name.lowercased().hasPrefix(searchQuery)
                let secondPrefix = second.name.lowercased().hasPrefix(searchQuery)
                if firstPrefix != secondPrefix { return firstPrefix }
                return first.name < second.name
            }
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
                TextField("Search files...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18))
                    .focused($isSearchFocused)
                    .onSubmit { openSelected() }
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
                    withAnimation { proxy.scrollTo(newValue, anchor: .center) }
                }
            }
            .frame(maxHeight: 300)
        }
        .frame(width: 500)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 20)
        .onAppear { isSearchFocused = true }
        .onChange(of: query) { selectedIndex = 0 }
        .background {
            KeyboardHandler(
                onUp: { selectedIndex = max(0, selectedIndex - 1) },
                onDown: { selectedIndex = min(filteredFiles.count - 1, selectedIndex + 1) },
                onEscape: { isPresented = false }
            )
        }
    }

    func openSelected() {
        guard selectedIndex >= 0 && selectedIndex < filteredFiles.count else { return }
        store.open(filteredFiles[selectedIndex].url)
        isPresented = false
    }
}

struct KeyboardHandler: NSViewRepresentable {
    var onUp: () -> Void
    var onDown: () -> Void
    var onEscape: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = KeyHandlerView()
        view.onUp = onUp
        view.onDown = onDown
        view.onEscape = onEscape

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case 126: view.onUp?(); return nil // up
            case 125: view.onDown?(); return nil // down  
            case 53: view.onEscape?(); return nil // escape
            default: return event
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let view = nsView as? KeyHandlerView {
            view.onUp = onUp
            view.onDown = onDown
            view.onEscape = onEscape
        }
    }

    class KeyHandlerView: NSView {
        var onUp: (() -> Void)?
        var onDown: (() -> Void)?
        var onEscape: (() -> Void)?
    }
}
