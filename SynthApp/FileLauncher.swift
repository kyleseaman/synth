import SwiftUI

enum LauncherResult: Identifiable {
    case note(result: NoteSearchResult)
    case file(node: FileTreeNode, score: Int)
    case person(name: String, count: Int, score: Int)

    var id: String {
        switch self {
        case .note(let result): return "note:\(result.url.absoluteString)"
        case .file(let node, _): return "file:\(node.url.absoluteString)"
        case .person(let name, _, _): return "person:\(name)"
        }
    }

    var sortScore: Int {
        switch self {
        case .note(let result): return result.score
        case .file(_, let score): return score
        case .person(_, _, let score): return score
        }
    }
}

extension String {
    /// FNV-1a 64-bit hash for fast content change detection.
    var fnv1a: UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in self.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }

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

        // Early exit: if remaining string is shorter than remaining query, no match possible
        let queryCount = queryLower.count
        let stringCount = lower.count
        if queryCount > stringCount { return nil }

        var score = 0
        var remainder = queryLower[...]
        var lastMatchIndex = -1
        let lowerChars = Array(lower)

        for (index, char) in lowerChars.enumerated() {
            // Early exit: not enough characters left to match remaining query
            let remainingInString = stringCount - index
            if remainingInString < remainder.count { return nil }

            if char == remainder.first {
                remainder.removeFirst()
                score += (lastMatchIndex == index - 1) ? 10 : 1
                lastMatchIndex = index
                if remainder.isEmpty { return score }
            }
        }
        return nil
    }
}

struct FileLauncher: View {
    enum SubmitAction: Equatable {
        case openSelected
        case triggerQmdSearch
        case noAction
    }

    @Environment(DocumentStore.self) var store
    @Binding var isPresented: Bool
    @State private var query = ""
    @State private var selectedIndex = 0
    @State private var cachedFiles: [FileTreeNode] = []
    @State private var previewCache: [URL: String] = [:]
    @State private var noteLookup: [URL: NoteSearchResult] = [:]
    @State private var qmdResults: [LauncherResult] = []
    @State private var isQmdSearching = false
    @State private var qmdSearchTask: Task<Void, Never>?
    @FocusState private var isSearchFocused: Bool

    var results: [LauncherResult] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)

        // Strip leading @ for people-specific search.
        let isPersonQuery = trimmed.hasPrefix("@")
        let searchQuery = isPersonQuery ? String(trimmed.dropFirst()) : trimmed

        if trimmed.isEmpty {
            let recentSet = Set(store.recentFiles)
            let recentNodes = store.recentFiles.compactMap { url in
                cachedFiles.first { $0.url == url }
            }
            let others = cachedFiles.filter { !recentSet.contains($0.url) }.prefix(20 - recentNodes.count)
            return (recentNodes + others).map { file in
                if let note = noteLookup[file.url] {
                    return .note(result: note)
                }
                return .file(node: file, score: 0)
            }
        }

        // People results.
        let peopleResults: [LauncherResult] = store.peopleIndex.search(searchQuery)
            .map { .person(name: $0.name, count: $0.count, score: $0.name.fuzzyScore(searchQuery) ?? 0) }

        if isPersonQuery {
            return peopleResults
        }

        // Semantic + fuzzy note results.
        let noteResults = store.noteIndex.search(searchQuery)
        let noteURLs = Set(noteResults.map(\.url))
        let semanticResults: [LauncherResult] = noteResults.map { .note(result: $0) }

        // Fallback for non-note files by file name.
        let fileResults = Self.fallbackFileResults(
            from: cachedFiles,
            query: trimmed,
            noteURLs: noteURLs,
            recentFiles: Set(store.recentFiles)
        )

        return blendWithQmdResults(
            base: (semanticResults + fileResults + peopleResults)
                .sorted { $0.sortScore > $1.sortScore }
        )
    }

    private var selectedNoteResult: NoteSearchResult? {
        guard selectedIndex >= 0 && selectedIndex < results.count else { return nil }
        guard case .note(let note) = results[selectedIndex] else { return nil }
        return note
    }

    var body: some View {
        VStack(spacing: 0) {
            searchHeader
            Divider()
            HStack(alignment: .top, spacing: 0) {
                resultsPanel
                Divider()
                previewPanel
            }
            .frame(maxHeight: 360)
        }
        .frame(width: 780)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 8)
        .onAppear {
            isSearchFocused = true
            cachedFiles = Self.flattenFiles(store.fileTree)
            noteLookup = Dictionary(uniqueKeysWithValues: store.noteIndex.notes.map { ($0.url, $0) })
            if let selectedNoteResult {
                loadPreview(for: selectedNoteResult.url)
            }
        }
        .onChange(of: store.fileTree) {
            cachedFiles = Self.flattenFiles(store.fileTree)
            noteLookup = Dictionary(uniqueKeysWithValues: store.noteIndex.notes.map { ($0.url, $0) })
        }
        .onChange(of: query) { _, _ in
            selectedIndex = 0
            qmdResults = []
            qmdSearchTask?.cancel()
            isQmdSearching = false
        }
        .onChange(of: results.count) { _, newValue in
            guard newValue > 0 else {
                selectedIndex = 0
                return
            }
            selectedIndex = min(selectedIndex, newValue - 1)
        }
        .onChange(of: selectedNoteResult?.url) { _, nextURL in
            guard let nextURL else { return }
            loadPreview(for: nextURL)
        }
        .background {
            KeyboardHandler(
                onUp: { selectedIndex = max(0, selectedIndex - 1) },
                onDown: {
                    guard !results.isEmpty else { return }
                    selectedIndex = min(results.count - 1, selectedIndex + 1)
                },
                onEscape: { isPresented = false }
            )
        }
    }

    private var searchHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search notes, files & people...", text: $query)
                    .textFieldStyle(.plain)
                    .font(Theme.uiSwiftUIFont(size: 18))
                    .focused($isSearchFocused)
                    .onSubmit { handleSubmit() }
                if isQmdSearching {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            HStack(spacing: 6) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(Theme.uiSwiftUIFont(size: 11))
                    .foregroundStyle(.tertiary)
                let hint = store.qmdClient?.isWorkspaceIndexed == true
                    ? "Press Enter to deep search · tag:project  person:alex  \"exact phrase\""
                    : "Try: tag:project  person:alex  path:meetings  \"exact phrase\""
                Text(hint)
                    .font(Theme.uiSwiftUIFont(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    private var resultsPanel: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: []) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                        resultRow(result: result, index: index)
                    }
                }
            }
            .onChange(of: selectedIndex) {
                withAnimation { proxy.scrollTo(selectedIndex, anchor: .center) }
            }
        }
        .frame(width: 420, alignment: .top)
    }

    @ViewBuilder
    private func resultRow(result: LauncherResult, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                switch result {
                case .note(let note):
                    Image(systemName: "doc.text.magnifyingglass")
                        .foregroundStyle(.secondary)
                    Text(note.title)
                    Spacer()
                    Text(note.relativePath)
                        .foregroundStyle(.tertiary)
                        .font(.caption)
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
                        .foregroundColor(.purple)
                    Text("@\(name)")
                        .foregroundColor(.purple)
                    Spacer()
                    let label = count == 1 ? "1 note" : "\(count) notes"
                    Text(label)
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                }
            }
            if case .note(let note) = result {
                Text(note.preview)
                    .font(Theme.uiSwiftUIFont(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.leading, 20)
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

    static func fallbackFileResults(
        from files: [FileTreeNode],
        query: String,
        noteURLs: Set<URL>,
        recentFiles: Set<URL>
    ) -> [LauncherResult] {
        files
            .filter { !noteURLs.contains($0.url) }
            .compactMap { fileNode -> LauncherResult? in
                guard let nameScore = fileNode.name.fuzzyScore(query) else { return nil }
                let recentBonus = recentFiles.contains(fileNode.url) ? 2000 : 0
                return .file(node: fileNode, score: nameScore + recentBonus)
            }
    }

    @ViewBuilder
    private var previewPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let selectedNoteResult {
                Text(selectedNoteResult.title)
                    .font(Theme.uiSwiftUIFont(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(selectedNoteResult.relativePath)
                    .font(Theme.uiSwiftUIFont(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Divider()
                ScrollView {
                    Text(previewText(for: selectedNoteResult))
                        .font(Theme.uiSwiftUIFont(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            } else {
                Spacer()
                Text("Select a note result to preview the full context.")
                    .font(Theme.uiSwiftUIFont(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(12)
        .frame(width: 360, alignment: .topLeading)
    }

    private func loadPreview(for url: URL) {
        if previewCache[url] != nil { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let cleaned = Self.cleanPreviewText(text)
            DispatchQueue.main.async {
                previewCache[url] = cleaned
            }
        }
    }

    private func previewText(for note: NoteSearchResult) -> String {
        guard let fullText = previewCache[note.url], !fullText.isEmpty else {
            return note.preview
        }

        let content = Self.focusedSnippet(
            from: fullText,
            query: query,
            fallback: note.preview
        )
        return content.isEmpty ? note.preview : content
    }

    nonisolated static func cleanPreviewText(_ text: String) -> String {
        text
            .components(separatedBy: .newlines)
            .map { line in
                line.replacingOccurrences(
                    of: #"\s+"#,
                    with: " ",
                    options: .regularExpression
                )
                .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    nonisolated static func focusedSnippet(
        from content: String,
        query: String,
        fallback: String
    ) -> String {
        let terms = query
            .lowercased()
            .split { $0.isWhitespace }
            .map(String.init)
            .filter {
                !$0.contains(":")
                    && !$0.hasPrefix("#")
                    && !$0.hasPrefix("@")
                    && $0.count >= 3
            }

        if terms.isEmpty {
            return String(content.prefix(650))
        }

        let lowerContent = content.lowercased()
        var firstRange: Range<String.Index>?
        for term in terms {
            if let range = lowerContent.range(of: term) {
                firstRange = range
                break
            }
        }

        guard let firstRange else {
            if !fallback.isEmpty { return fallback }
            return String(content.prefix(650))
        }

        let lowerBound = lowerContent.distance(from: lowerContent.startIndex, to: firstRange.lowerBound)
        let upperBound = lowerContent.distance(from: lowerContent.startIndex, to: firstRange.upperBound)
        let startOffset = max(0, lowerBound - 220)
        let endOffset = min(content.count, upperBound + 420)

        let startIndex = content.index(content.startIndex, offsetBy: startOffset)
        let endIndex = content.index(content.startIndex, offsetBy: endOffset)
        return String(content[startIndex..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func openSelected() {
        guard selectedIndex >= 0 && selectedIndex < results.count else { return }
        switch results[selectedIndex] {
        case .note(let result):
            store.open(result.url)
        case .file(let node, _):
            store.open(node.url)
        case .person(let name, _, _):
            store.showPeopleBrowserModal(person: name)
        }
        isPresented = false
    }

    // MARK: - QMD Integration

    private func handleSubmit() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        switch Self.submitAction(
            trimmedQuery: trimmed,
            resultCount: results.count,
            selectedIndex: selectedIndex,
            qmdResultsCount: qmdResults.count,
            isWorkspaceIndexed: store.qmdClient?.isWorkspaceIndexed == true
        ) {
        case .openSelected:
            openSelected()
        case .triggerQmdSearch:
            triggerQmdSearch(trimmed)
        case .noAction:
            return
        }
    }

    static func submitAction(
        trimmedQuery: String,
        resultCount: Int,
        selectedIndex: Int,
        qmdResultsCount: Int,
        isWorkspaceIndexed: Bool
    ) -> SubmitAction {
        let hasSelection = selectedIndex >= 0 && selectedIndex < resultCount
        if hasSelection {
            return .openSelected
        }
        let canSearchQmd = !trimmedQuery.isEmpty
            && isWorkspaceIndexed
            && qmdResultsCount == 0
        if canSearchQmd {
            return .triggerQmdSearch
        }
        return .noAction
    }

    private func triggerQmdSearch(_ searchQuery: String) {
        qmdSearchTask?.cancel()
        guard let qmdClient = store.qmdClient,
              qmdClient.isWorkspaceIndexed,
              let workspace = store.workspace else { return }
        isQmdSearching = true
        qmdSearchTask = Task {
            let qmdHits = await qmdClient.search(query: searchQuery, limit: 15)
            guard !Task.isCancelled else { return }
            let mapped: [LauncherResult] = qmdHits.compactMap { hit in
                let fileURL: URL
                if hit.path.hasPrefix("/") {
                    fileURL = URL(fileURLWithPath: hit.path)
                } else {
                    fileURL = workspace.appendingPathComponent(hit.path)
                }
                guard FileManager.default.fileExists(atPath: fileURL.path) else {
                    return nil
                }
                let boostScore = Int(hit.score * 30_000) + 10_000
                let result = NoteSearchResult(
                    id: fileURL,
                    title: hit.title,
                    relativePath: fileURL.deletingLastPathComponent()
                        .lastPathComponent,
                    url: fileURL,
                    preview: hit.snippet,
                    score: boostScore
                )
                return .note(result: result)
            }
            await MainActor.run {
                qmdResults = mapped
                isQmdSearching = false
                selectedIndex = 0
            }
        }
    }

    private func blendWithQmdResults(
        base: [LauncherResult]
    ) -> [LauncherResult] {
        guard !qmdResults.isEmpty else { return base }
        let qmdURLs = Set(qmdResults.compactMap { result -> URL? in
            switch result {
            case .note(let note): return note.url
            case .file(let node, _): return node.url
            case .person: return nil
            }
        })
        let uniqueBase = base.filter { result in
            switch result {
            case .note(let note): return !qmdURLs.contains(note.url)
            case .file(let node, _): return !qmdURLs.contains(node.url)
            case .person: return true
            }
        }
        return (qmdResults + uniqueBase).sorted { $0.sortScore > $1.sortScore }
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
            .font(Theme.uiSwiftUIFont(size: 10))
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
