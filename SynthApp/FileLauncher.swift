import SwiftUI

enum LauncherResult: Identifiable {
    case file(node: FileTreeNode, score: Int)
    case person(name: String, count: Int, score: Int)

    var id: String {
        switch self {
        case .file(let node, _): return "file:\(node.url.absoluteString)"
        case .person(let name, _, _): return "person:\(name)"
        }
    }

    var sortScore: Int {
        switch self {
        case .file(_, let score): return score
        case .person(_, _, let score): return score
        }
    }
}

extension String {
    /// Capitalize the first letter of each word.
    var titleCased: String {
        self.split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    func fuzzyScore(_ query: String) -> Int? {
        if query.isEmpty { return 1000 }
        let lower = self.lowercased()
        let queryLower = query.lowercased()

        if lower == queryLower { return 10000 }
        if lower.contains(queryLower) {
            return 5000 + (lower.hasPrefix(queryLower) ? 1000 : 0)
        }
        var score = 0
        var remainder = queryLower[...]
        var lastMatchIndex = -1
        for (index, char) in lower.enumerated() where char == remainder.first {
            remainder.removeFirst()
            score += (lastMatchIndex == index - 1) ? 10 : 1
            lastMatchIndex = index
            if remainder.isEmpty { return score }
        }
        return nil
    }
}

struct FileLauncher: View {
    @EnvironmentObject var store: DocumentStore
    @Binding var isPresented: Bool
    @State private var query = ""
    @State private var selectedIndex = 0
    @State private var cachedFiles: [FileTreeNode] = []
    @FocusState private var isSearchFocused: Bool

    var results: [LauncherResult] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)

        // Strip leading @ for people-specific search
        let isPersonQuery = trimmed.hasPrefix("@")
        let searchQuery = isPersonQuery ? String(trimmed.dropFirst()) : trimmed

        if trimmed.isEmpty {
            let recentSet = Set(store.recentFiles)
            let recentNodes = store.recentFiles.compactMap { url in
                cachedFiles.first { $0.url == url }
            }
            let others = cachedFiles.filter { !recentSet.contains($0.url) }.prefix(20 - recentNodes.count)
            return (recentNodes + others).map { .file(node: $0, score: 0) }
        }

        // People results
        let peopleResults: [LauncherResult] = store.peopleIndex.search(searchQuery)
            .map { .person(name: $0.name, count: $0.count, score: $0.name.fuzzyScore(searchQuery) ?? 0) }

        if isPersonQuery {
            return peopleResults
        }

        // File results
        let fileResults: [LauncherResult] = cachedFiles
            .compactMap { file -> LauncherResult? in
                guard let nameScore = file.name.fuzzyScore(trimmed) else { return nil }
                let recentBonus = store.recentFiles.contains(file.url) ? 2000 : 0
                return .file(node: file, score: nameScore + recentBonus)
            }

        return (fileResults + peopleResults).sorted { $0.sortScore > $1.sortScore }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search files & people...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18))
                    .focused($isSearchFocused)
                    .onSubmit { openSelected() }
            }
            .padding(12)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    switch result {
                                    case .file(let node, _):
                                        Image(systemName: "doc.text")
                                            .foregroundStyle(.secondary)
                                        Text(node.name)
                                        Spacer()
                                        Text(node.url.deletingLastPathComponent().lastPathComponent)
                                            .foregroundStyle(.tertiary)
                                            .font(.caption)
                                    case .person(let name, let count, _):
                                        Image(systemName: "person.fill")
                                            .foregroundColor(Color(nsColor: .systemPurple))
                                        Text("@\(name)")
                                            .foregroundColor(Color(nsColor: .systemPurple))
                                        Spacer()
                                        let label = count == 1 ? "1 note" : "\(count) notes"
                                        Text(label)
                                            .foregroundStyle(.tertiary)
                                            .font(.caption)
                                    }
                                }
                                if case .file(let node, _) = result {
                                    FileDatesLabel(url: node.url)
                                }
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
                .onChange(of: selectedIndex) {
                    withAnimation { proxy.scrollTo(selectedIndex, anchor: .center) }
                }
            }
            .frame(maxHeight: 300)
        }
        .frame(width: 500)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 8)
        .onAppear {
            isSearchFocused = true
            cachedFiles = Self.flattenFiles(store.fileTree)
        }
        .onChange(of: store.fileTree) {
            cachedFiles = Self.flattenFiles(store.fileTree)
        }
        .onChange(of: query) { _, _ in selectedIndex = 0 }
        .background {
            KeyboardHandler(
                onUp: { selectedIndex = max(0, selectedIndex - 1) },
                onDown: { selectedIndex = min(results.count - 1, selectedIndex + 1) },
                onEscape: { isPresented = false }
            )
        }
    }

    static func flattenFiles(_ nodes: [FileTreeNode]) -> [FileTreeNode] {
        var result: [FileTreeNode] = []
        for node in nodes {
            if !node.isDirectory { result.append(node) }
            if let children = node.children {
                result.append(contentsOf: flattenFiles(children))
            }
        }
        return result
    }

    func openSelected() {
        guard selectedIndex >= 0 && selectedIndex < results.count else { return }
        switch results[selectedIndex] {
        case .file(let node, _):
            store.open(node.url)
        case .person(let name, _, _):
            NotificationCenter.default.post(
                name: .showPeopleBrowser,
                object: nil,
                userInfo: ["initialPerson": name]
            )
        }
        isPresented = false
    }
}

// MARK: - File Dates Label

struct FileDatesLabel: View {
    let url: URL

    private static let formatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateStyle = .short
        fmt.timeStyle = .short
        return fmt
    }()

    private var dates: (created: String, modified: String)? {
        guard let values = try? url.resourceValues(
            forKeys: [.creationDateKey, .contentModificationDateKey]
        ) else { return nil }
        let created = values.creationDate.map { Self.formatter.string(from: $0) } ?? "—"
        let modified = values.contentModificationDate.map { Self.formatter.string(from: $0) } ?? "—"
        return (created: created, modified: modified)
    }

    var body: some View {
        if let dates = dates {
            HStack(spacing: 8) {
                Text("Created \(dates.created)")
                Text("Modified \(dates.modified)")
            }
            .font(.system(size: 10))
            .foregroundStyle(.quaternary)
            .padding(.leading, 20)
        }
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

        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case 126: view.onUp?(); return nil
            case 125: view.onDown?(); return nil
            case 53: view.onEscape?(); return nil
            default: return event
            }
        }
        view.monitor = monitor
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let view = nsView as? KeyHandlerView {
            view.onUp = onUp
            view.onDown = onDown
            view.onEscape = onEscape
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        if let view = nsView as? KeyHandlerView {
            if let monitor = view.monitor {
                NSEvent.removeMonitor(monitor)
            }
            view.monitor = nil
        }
    }

    class KeyHandlerView: NSView {
        var onUp: (() -> Void)?
        var onDown: (() -> Void)?
        var onEscape: (() -> Void)?
        var monitor: Any?
    }
}
