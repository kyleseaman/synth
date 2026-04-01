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
    @State private var noteLookup: [URL: NoteSearchResult] = [:]
    @State private var modDateCache: [URL: Date] = [:]
    @State private var qmdResults: [LauncherResult] = []
    @State private var searchResults: [LauncherResult] = []
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var isSearchFocused: Bool

    private var engine: SearchEngine { store.searchEngine }
    var results: [LauncherResult] { searchResults }

    private var selectedNoteResult: NoteSearchResult? {
        guard selectedIndex >= 0 && selectedIndex < results.count else { return nil }
        guard case .note(let note) = results[selectedIndex] else { return nil }
        return note
    }

    private var qmdResultURLs: Set<URL> {
        Set(qmdResults.compactMap { launcherResult in
            switch launcherResult {
            case .note(let noteResult):
                return noteResult.url
            case .file(let node, _):
                return node.url
            case .person:
                return nil
            }
        })
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
            noteLookup = Dictionary(uniqueKeysWithValues: store.noteIndex.notes.map { ($0.url, $0) })
            buildModDateCache()
            computeResults()
            if let selectedNoteResult {
                engine.loadPreview(for: selectedNoteResult.url)
            }
        }
        .onChange(of: store.fileTree) {
            noteLookup = Dictionary(uniqueKeysWithValues: store.noteIndex.notes.map { ($0.url, $0) })
            buildModDateCache()
            computeResults()
        }
        .onChange(of: query) { _, _ in
            selectedIndex = 0
            qmdResults = []
            engine.cancelQmdSearch()
            debounceSearch()
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
            engine.loadPreview(for: nextURL)
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
                if engine.isQmdSearching {
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

            if !qmdResults.isEmpty {
                Text("Blending \(qmdResults.count) QMD result(s) with local results.")
                    .font(Theme.uiSwiftUIFont(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
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
            .scrollIndicators(.never)
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
                    Text(SearchEngine.highlightedText(note.title, query: query))
                        .lineLimit(1)
                    Spacer()
                    if qmdResultURLs.contains(note.url) {
                        sourceBadge("QMD")
                    }
                    Text(note.relativePath)
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                case .file(let node, _):
                    Image(systemName: "doc.text")
                        .foregroundStyle(.secondary)
                    Text(SearchEngine.highlightedText(node.name, query: query))
                        .lineLimit(1)
                    Spacer()
                    if qmdResultURLs.contains(node.url) {
                        sourceBadge("QMD")
                    }
                    Text(node.url.deletingLastPathComponent().lastPathComponent)
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                case .person(let name, let count, _):
                    Image(systemName: "person.fill")
                        .foregroundColor(.purple)
                    Text(SearchEngine.highlightedText("@\(name)", query: query))
                        .foregroundColor(.purple)
                    Spacer()
                    let label = count == 1 ? "1 note" : "\(count) notes"
                    Text(label)
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                }
            }
            if case .note(let note) = result {
                Text(SearchEngine.highlightedText(
                    rowPreviewText(for: note),
                    query: query,
                    baseFont: Theme.uiSwiftUIFont(size: 11)
                ))
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

    private func previewText(for note: NoteSearchResult) -> String {
        let fullText = engine.previewCache[note.url] ?? note.preview

        let content = SearchEngine.focusedSnippet(
            from: fullText,
            query: query,
            fallback: note.preview
        )
        return content.isEmpty ? note.preview : content
    }

    private func rowPreviewText(for note: NoteSearchResult) -> String {
        let rowContent = engine.previewCache[note.url] ?? note.preview
        let snippetText = SearchEngine.focusedSnippet(
            from: rowContent,
            query: query,
            fallback: note.preview
        )
        return snippetText.isEmpty ? note.preview : snippetText
    }

    @ViewBuilder
    private func sourceBadge(_ label: String) -> some View {
        Text(label)
            .font(Theme.uiSwiftUIFont(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.12), in: Capsule())
    }

    private func debounceSearch() {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)

        // Empty query → show recents immediately, no debounce
        if trimmed.isEmpty {
            computeResults()
            return
        }

        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }

            if trimmed.hasPrefix("@") {
                let personQuery = String(trimmed.dropFirst())
                let result = engine.searchImmediate(query: personQuery)
                guard !Task.isCancelled else { return }
                searchResults = result.people.map {
                    .person(name: $0.name, count: $0.count, score: $0.score)
                }
                return
            }

            let result = engine.searchImmediate(query: trimmed)
            guard !Task.isCancelled else { return }
            applySearchResult(result)
        }
    }

    private func buildModDateCache() {
        var cache: [URL: Date] = [:]
        for file in engine.cachedFiles {
            if let date = (try? file.url.resourceValues(
                forKeys: [.contentModificationDateKey]
            ))?.contentModificationDate {
                cache[file.url] = date
            }
        }
        modDateCache = cache
    }

    private func computeResults() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)

        if trimmed.isEmpty {
            let cachedFiles = engine.cachedFiles
            let recentSet = Set(store.recentFiles)
            let recentNodes = store.recentFiles.compactMap { url in
                cachedFiles.first { $0.url == url }
            }
            let remainingFiles = cachedFiles
                .filter { !recentSet.contains($0.url) }
            let dateCache = modDateCache
            let sortedByModDate = remainingFiles.sorted { first, second in
                let firstDate = dateCache[first.url] ?? .distantPast
                let secondDate = dateCache[second.url] ?? .distantPast
                return firstDate > secondDate
            }
            let others = sortedByModDate.prefix(20 - recentNodes.count)
            searchResults = (recentNodes + others).map { file in
                if let note = noteLookup[file.url] {
                    return .note(result: note)
                }
                return .file(node: file, score: 0)
            }
            return
        }

        if trimmed.hasPrefix("@") {
            let personQuery = String(trimmed.dropFirst())
            let result = engine.searchImmediate(query: personQuery)
            searchResults = result.people.map {
                .person(name: $0.name, count: $0.count, score: $0.score)
            }
            return
        }

        let result = engine.searchImmediate(query: trimmed)
        applySearchResult(result)
    }

    private func applySearchResult(_ result: SearchResult) {
        let noteResults: [LauncherResult] = result.notes.map { .note(result: $0) }
        let fileResults: [LauncherResult] = result.files.map { .file(node: $0.node, score: $0.score) }
        let peopleResults: [LauncherResult] = result.people.map {
            .person(name: $0.name, count: $0.count, score: $0.score)
        }

        let base = (noteResults + fileResults + peopleResults)
            .sorted { $0.sortScore > $1.sortScore }
        searchResults = blendWithQmdResults(base: base)
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
        engine.triggerQmdSearch(query: searchQuery, limit: 15) { mapped in
            self.qmdResults = mapped.map { .note(result: $0) }
            self.selectedIndex = 0
            self.computeResults()
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

    @State private var dates: (created: String, modified: String)?

    var body: some View {
        if let dates {
            HStack(spacing: 8) {
                Text("Created \(dates.created)")
                Text("Modified \(dates.modified)")
            }
            .font(Theme.uiSwiftUIFont(size: 10))
            .foregroundStyle(.quaternary)
            .padding(.leading, 20)
        }
    }

    init(url: URL) {
        self.url = url
        if let values = try? url.resourceValues(
            forKeys: [.creationDateKey, .contentModificationDateKey]
        ) {
            let created = values.creationDate.map { Self.formatter.string(from: $0) } ?? "—"
            let modified = values.contentModificationDate.map { Self.formatter.string(from: $0) } ?? "—"
            _dates = State(initialValue: (created: created, modified: modified))
        } else {
            _dates = State(initialValue: nil)
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
