import SwiftUI
import Observation

enum SearchFacetKind: String, CaseIterable {
    case title
    case content
    case path
    case tag
    case person

    var displayName: String {
        switch self {
        case .title:
            return "Title"
        case .content:
            return "Content"
        case .path:
            return "Path"
        case .tag:
            return "Tag"
        case .person:
            return "Person"
        }
    }
}

struct SearchFacetToken: Identifiable, Equatable {
    let kind: SearchFacetKind
    let value: String

    var identifier: String {
        "\(kind.rawValue):\(value.lowercased())"
    }

    var id: String {
        identifier
    }

    var queryFragment: String {
        let escapedValue = value.replacingOccurrences(of: "\"", with: "\\\"")
        if escapedValue.contains(where: { $0.isWhitespace }) {
            return "\(kind.rawValue):\"\(escapedValue)\""
        }
        return "\(kind.rawValue):\(escapedValue)"
    }
}

enum DedicatedSearchSelectionDirection {
    case previous
    case next
}

enum DedicatedSearchResultSource: String {
    case local
    case qmd
    case blended

    var shortLabel: String {
        switch self {
        case .local:
            return "Local"
        case .qmd:
            return "QMD"
        case .blended:
            return "QMD + Local"
        }
    }

    var detailLabel: String {
        switch self {
        case .local:
            return "Matched by local index"
        case .qmd:
            return "Matched by QMD deep search"
        case .blended:
            return "Matched by both QMD and local index"
        }
    }
}

struct DedicatedSearchMergedNoteResult {
    let noteResult: NoteSearchResult
    let source: DedicatedSearchResultSource
}

enum DedicatedSearchPresentation {
    static func mergeNoteResults(
        localResults: [NoteSearchResult],
        qmdResults: [NoteSearchResult]
    ) -> [DedicatedSearchMergedNoteResult] {
        guard !qmdResults.isEmpty else {
            return localResults.map { noteResult in
                DedicatedSearchMergedNoteResult(noteResult: noteResult, source: .local)
            }
        }

        var mergedByURL: [URL: DedicatedSearchMergedNoteResult] = [:]
        for localResult in localResults {
            mergedByURL[localResult.url] = DedicatedSearchMergedNoteResult(
                noteResult: localResult,
                source: .local
            )
        }

        for qmdResult in qmdResults {
            if let existingResult = mergedByURL[qmdResult.url] {
                let preferredResult = qmdResult.score >= existingResult.noteResult.score
                    ? qmdResult
                    : existingResult.noteResult
                mergedByURL[qmdResult.url] = DedicatedSearchMergedNoteResult(
                    noteResult: preferredResult,
                    source: .blended
                )
            } else {
                mergedByURL[qmdResult.url] = DedicatedSearchMergedNoteResult(
                    noteResult: qmdResult,
                    source: .qmd
                )
            }
        }

        return mergedByURL.values.sorted { firstResult, secondResult in
            firstResult.noteResult.score > secondResult.noteResult.score
        }
    }
}

enum DedicatedSearchResetBehavior {
    static func reset(state: DedicatedSearchState, qmdResults: inout [NoteSearchResult]) {
        state.clear()
        qmdResults.removeAll(keepingCapacity: false)
    }
}

@Observable
final class DedicatedSearchState {
    var textQuery = ""
    var titleFilterText = ""
    var contentFilterText = ""
    var pathFilterText = ""
    var tagFilterText = ""
    var personFilterText = ""
    var selectedResultIdentifier: String?

    var composedQuery: String {
        let trimmedTextQuery = textQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let facetFragments = facetTokens.map(\.queryFragment)

        if trimmedTextQuery.isEmpty {
            return facetFragments.joined(separator: " ")
        }
        if facetFragments.isEmpty {
            return trimmedTextQuery
        }
        return ([trimmedTextQuery] + facetFragments).joined(separator: " ")
    }

    var hasFacetFilters: Bool {
        !facetTokens.isEmpty
    }

    var facetTokens: [SearchFacetToken] {
        var tokens: [SearchFacetToken] = []
        appendTokens(from: titleFilterText, kind: .title, into: &tokens)
        appendTokens(from: contentFilterText, kind: .content, into: &tokens)
        appendTokens(from: pathFilterText, kind: .path, into: &tokens)
        appendTokens(from: tagFilterText, kind: .tag, into: &tokens)
        appendTokens(from: personFilterText, kind: .person, into: &tokens)
        return tokens
    }

    func removeFacet(_ token: SearchFacetToken) {
        switch token.kind {
        case .title:
            titleFilterText = Self.removingFacetValue(token.value, from: titleFilterText)
        case .content:
            contentFilterText = Self.removingFacetValue(token.value, from: contentFilterText)
        case .path:
            pathFilterText = Self.removingFacetValue(token.value, from: pathFilterText)
        case .tag:
            tagFilterText = Self.removingFacetValue(token.value, from: tagFilterText)
        case .person:
            personFilterText = Self.removingFacetValue(token.value, from: personFilterText)
        }
    }

    func clear() {
        textQuery = ""
        titleFilterText = ""
        contentFilterText = ""
        pathFilterText = ""
        tagFilterText = ""
        personFilterText = ""
        selectedResultIdentifier = nil
    }

    static func reconcileSelection(
        currentIdentifier: String?,
        availableIdentifiers: [String]
    ) -> String? {
        guard !availableIdentifiers.isEmpty else { return nil }
        if let currentIdentifier,
           availableIdentifiers.contains(currentIdentifier) {
            return currentIdentifier
        }
        return availableIdentifiers.first
    }

    static func stepSelection(
        currentIdentifier: String?,
        availableIdentifiers: [String],
        direction: DedicatedSearchSelectionDirection
    ) -> String? {
        guard !availableIdentifiers.isEmpty else { return nil }
        guard let currentIdentifier,
              let currentIndex = availableIdentifiers.firstIndex(of: currentIdentifier) else {
            return availableIdentifiers.first
        }

        switch direction {
        case .previous:
            return availableIdentifiers[max(0, currentIndex - 1)]
        case .next:
            return availableIdentifiers[min(availableIdentifiers.count - 1, currentIndex + 1)]
        }
    }

    private func appendTokens(
        from rawValue: String,
        kind: SearchFacetKind,
        into tokens: inout [SearchFacetToken]
    ) {
        let facetValues = Self.facetValues(from: rawValue)
        for facetValue in facetValues {
            tokens.append(SearchFacetToken(kind: kind, value: facetValue))
        }
    }

    private static func removingFacetValue(_ value: String, from rawText: String) -> String {
        let lowercasedValue = value.lowercased()
        let remaining = facetValues(from: rawText)
            .filter { facetValue in
                facetValue.lowercased() != lowercasedValue
            }
        return remaining.joined(separator: ", ")
    }

    private static func facetValues(from rawText: String) -> [String] {
        let components = rawText.split(separator: ",", omittingEmptySubsequences: true)
        var seenValues: Set<String> = []
        var values: [String] = []

        for component in components {
            let trimmedValue = component.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedValue.isEmpty else { continue }
            let canonicalValue = trimmedValue.lowercased()
            guard seenValues.insert(canonicalValue).inserted else { continue }
            values.append(trimmedValue)
        }

        return values
    }
}

enum DedicatedSearchResult: Identifiable {
    case note(result: NoteSearchResult, source: DedicatedSearchResultSource)
    case file(node: FileTreeNode, score: Int)
    case person(name: String, count: Int, score: Int)
    case tag(name: String, count: Int, score: Int)

    var identifier: String {
        switch self {
        case .note(let noteResult, _):
            return "note:\(noteResult.url.absoluteString)"
        case .file(let node, _):
            return "file:\(node.url.absoluteString)"
        case .person(let name, _, _):
            return "person:\(name)"
        case .tag(let name, _, _):
            return "tag:\(name)"
        }
    }

    var id: String {
        identifier
    }

    var sortScore: Int {
        switch self {
        case .note(let noteResult, _):
            return noteResult.score
        case .file(_, let score):
            return score
        case .person(_, _, let score):
            return score
        case .tag(_, _, let score):
            return score
        }
    }
}

struct DedicatedSearchView: View {
    @Environment(DocumentStore.self) private var store
    @State private var qmdResults: [NoteSearchResult] = []
    @State private var localNoteResults: [NoteSearchResult] = []
    @State private var scoredFiles: [ScoredFile] = []
    @State private var scoredPeople: [ScoredMatch] = []
    @State private var scoredTags: [ScoredMatch] = []
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var isQueryFocused: Bool

    private var engine: SearchEngine { store.searchEngine }

    private var freeTextQuery: String {
        store.dedicatedSearch.textQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var activeQuery: String {
        store.dedicatedSearch.composedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var mergedNoteResults: [DedicatedSearchMergedNoteResult] {
        DedicatedSearchPresentation.mergeNoteResults(
            localResults: localNoteResults,
            qmdResults: qmdResults
        )
    }

    private var noteResultItems: [DedicatedSearchResult] {
        mergedNoteResults.map { mergedResult in
            .note(result: mergedResult.noteResult, source: mergedResult.source)
        }
    }

    private var noteSourceByURL: [URL: DedicatedSearchResultSource] {
        Dictionary(uniqueKeysWithValues: mergedNoteResults.map { mergedResult in
            (mergedResult.noteResult.url, mergedResult.source)
        })
    }

    private var noteSourceCounts: [DedicatedSearchResultSource: Int] {
        mergedNoteResults.reduce(into: [:]) { counts, mergedResult in
            counts[mergedResult.source, default: 0] += 1
        }
    }

    private var noteSectionLabel: String {
        var components: [String] = ["Notes (\(noteResultItems.count))"]
        if let localCount = noteSourceCounts[.local], localCount > 0 {
            components.append("Local \(localCount)")
        }
        if let qmdCount = noteSourceCounts[.qmd], qmdCount > 0 {
            components.append("QMD \(qmdCount)")
        }
        if let blendedCount = noteSourceCounts[.blended], blendedCount > 0 {
            components.append("Blended \(blendedCount)")
        }
        return components.joined(separator: " · ")
    }

    private var resultSummaryLabel: String {
        let totalCount = allResultItems.count
        return "Results \(totalCount) · Notes \(noteResultItems.count) · Files \(fileResultItems.count) "
            + "· People \(personResultItems.count) · Tags \(tagResultItems.count)"
    }

    private var fileResultItems: [DedicatedSearchResult] {
        guard !freeTextQuery.isEmpty else { return [] }

        let noteURLs = Set(mergedNoteResults.map(\.noteResult.url))
        return scoredFiles
            .filter { !noteURLs.contains($0.node.url) }
            .prefix(20)
            .map { .file(node: $0.node, score: $0.score) }
    }

    private var personResultItems: [DedicatedSearchResult] {
        scoredPeople.map { .person(name: $0.name, count: $0.count, score: $0.score) }
    }

    private var tagResultItems: [DedicatedSearchResult] {
        scoredTags.map { .tag(name: $0.name, count: $0.count, score: $0.score) }
    }

    private var allResultItems: [DedicatedSearchResult] {
        noteResultItems + fileResultItems + personResultItems + tagResultItems
    }

    private var resultIdentifiers: [String] {
        allResultItems.map(\.id)
    }

    private var selectedResult: DedicatedSearchResult? {
        guard let selectedIdentifier = store.dedicatedSearch.selectedResultIdentifier else {
            return nil
        }
        return allResultItems.first { result in
            result.id == selectedIdentifier
        }
    }

    private var shouldShowEmptyQueryPrompt: Bool {
        activeQuery.isEmpty && !store.dedicatedSearch.hasFacetFilters
    }

    private var selectionBinding: Binding<String?> {
        Binding(
            get: { store.dedicatedSearch.selectedResultIdentifier },
            set: { store.dedicatedSearch.selectedResultIdentifier = $0 }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                resultsPanel
                detailPanel
            }
        }
        .onAppear {
            isQueryFocused = true
        }
        .onChange(of: activeQuery) {
            qmdResults = []
            engine.cancelQmdSearch()
            searchTask?.cancel()

            let query = activeQuery
            if query.isEmpty {
                localNoteResults = []
                scoredFiles = []
                scoredPeople = []
                scoredTags = []
                return
            }

            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                let result = engine.searchImmediate(query: query)
                guard !Task.isCancelled else { return }
                localNoteResults = result.notes
                scoredFiles = result.files
                scoredPeople = result.people
                scoredTags = result.tags
            }
        }
        .onChange(of: resultIdentifiers) { _, availableIdentifiers in
            store.dedicatedSearch.selectedResultIdentifier = DedicatedSearchState.reconcileSelection(
                currentIdentifier: store.dedicatedSearch.selectedResultIdentifier,
                availableIdentifiers: availableIdentifiers
            )
            preloadSelectedPreview()
        }
        .onDisappear {
            engine.cancelQmdSearch()
        }
        .background {
            KeyboardHandler(
                onUp: { moveSelection(.previous) },
                onDown: { moveSelection(.next) },
                onEscape: { resetSearch() }
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(
                    "Search titles, note content, files, tags, and people",
                    text: binding(for: \.textQuery)
                )
                .textFieldStyle(.plain)
                .font(Theme.uiSwiftUIFont(size: 17))
                .focused($isQueryFocused)
                .onSubmit {
                    handleSubmit()
                }

                if engine.isQmdSearching {
                    ProgressView()
                        .controlSize(.small)
                }

                Button("Quick Jump") {
                    store.showFileLauncherModal()
                }
                .buttonStyle(.bordered)
                .help("Open Cmd+P quick jump")
            }

            HStack(spacing: 8) {
                facetField("Title", text: binding(for: \.titleFilterText), placeholder: "weekly")
                facetField(
                    "Content",
                    text: binding(for: \.contentFilterText),
                    placeholder: "deployment"
                )
                facetField("Path", text: binding(for: \.pathFilterText), placeholder: "meetings")
            }

            HStack(spacing: 8) {
                facetField("Tag", text: binding(for: \.tagFilterText), placeholder: "project")
                facetField("Person", text: binding(for: \.personFilterText), placeholder: "alex")
                Spacer()
                Button("Reset") {
                    resetSearch()
                }
                .buttonStyle(.bordered)
            }

            if !store.dedicatedSearch.facetTokens.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(store.dedicatedSearch.facetTokens) { facetToken in
                            HStack(spacing: 6) {
                                Text("\(facetToken.kind.displayName): \(facetToken.value)")
                                Button {
                                    store.dedicatedSearch.removeFacet(facetToken)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(Theme.uiSwiftUIFont(size: 11))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                        }
                    }
                }
            }

            if !allResultItems.isEmpty {
                Text(resultSummaryLabel)
                    .font(Theme.uiSwiftUIFont(size: 11))
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 8) {
                if store.qmdClient?.isWorkspaceIndexed == true {
                    Button("Deep Search") {
                        triggerQmdSearch(activeQuery)
                    }
                    .buttonStyle(.bordered)
                    .disabled(activeQuery.isEmpty || engine.isQmdSearching)

                    Text("QMD deep content search available")
                        .font(Theme.uiSwiftUIFont(size: 11))
                        .foregroundStyle(.tertiary)
                } else {
                    Text("QMD unavailable. Showing local title/content index results.")
                        .font(Theme.uiSwiftUIFont(size: 11))
                        .foregroundStyle(.tertiary)
                }

                if !qmdResults.isEmpty {
                    Text("Blending \(qmdResults.count) deep content result(s) with local results.")
                        .font(Theme.uiSwiftUIFont(size: 11))
                        .foregroundStyle(.tertiary)
                }

                Spacer()
                Text("Persistent search includes note content. Cmd+P stays optimized for title/file jumping.")
                    .font(Theme.uiSwiftUIFont(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var resultsPanel: some View {
        Group {
            if shouldShowEmptyQueryPrompt {
                VStack(spacing: 10) {
                    Spacer()
                    Text("Start typing to search the workspace")
                        .font(Theme.uiSwiftUIFont(size: 15, weight: .semibold))
                    Text("Search titles and note content, then narrow with title, content, path, tag, or person filters.")
                        .font(Theme.uiSwiftUIFont(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if allResultItems.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Text("No results")
                        .font(Theme.uiSwiftUIFont(size: 15, weight: .semibold))
                    Text("Refine your query or remove a filter.")
                        .font(Theme.uiSwiftUIFont(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: selectionBinding) {
                    if !noteResultItems.isEmpty {
                        Section(noteSectionLabel) {
                            ForEach(noteResultItems) { resultItem in
                                resultRow(resultItem)
                                    .tag(resultItem.id)
                                    .onTapGesture(count: 2) {
                                        openResultKeepingSearch(resultItem)
                                    }
                            }
                        }
                    }

                    if !fileResultItems.isEmpty {
                        Section("Files (\(fileResultItems.count))") {
                            ForEach(fileResultItems) { resultItem in
                                resultRow(resultItem)
                                    .tag(resultItem.id)
                                    .onTapGesture(count: 2) {
                                        openResultKeepingSearch(resultItem)
                                    }
                            }
                        }
                    }

                    if !personResultItems.isEmpty {
                        Section("People (\(personResultItems.count))") {
                            ForEach(personResultItems) { resultItem in
                                resultRow(resultItem)
                                    .tag(resultItem.id)
                                    .onTapGesture(count: 2) {
                                        openResultKeepingSearch(resultItem)
                                    }
                            }
                        }
                    }

                    if !tagResultItems.isEmpty {
                        Section("Tags (\(tagResultItems.count))") {
                            ForEach(tagResultItems) { resultItem in
                                resultRow(resultItem)
                                    .tag(resultItem.id)
                                    .onTapGesture(count: 2) {
                                        openResultKeepingSearch(resultItem)
                                    }
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 420)
    }

    private var detailPanel: some View {
        Group {
            if let selectedResult {
                selectedResultDetail(selectedResult)
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    Text("Select a result to inspect details")
                        .font(Theme.uiSwiftUIFont(size: 13))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 340)
    }

    private func resultRow(_ result: DedicatedSearchResult) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                switch result {
                case .note(let noteResult, let source):
                    Image(systemName: "doc.text.magnifyingglass")
                        .foregroundStyle(.secondary)
                    Text(SearchEngine.highlightedText(noteResult.title, query: freeTextQuery))
                        .lineLimit(1)
                    Spacer()
                    sourceBadge(source)
                    Text(noteResult.relativePath)
                        .font(Theme.uiSwiftUIFont(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                case .file(let node, _):
                    Image(systemName: "doc")
                        .foregroundStyle(.secondary)
                    Text(SearchEngine.highlightedText(node.name, query: freeTextQuery))
                        .lineLimit(1)
                    Spacer()
                    Text(node.url.deletingLastPathComponent().lastPathComponent)
                        .font(Theme.uiSwiftUIFont(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                case .person(let name, let count, _):
                    Image(systemName: "person.fill")
                        .foregroundStyle(.secondary)
                    Text(SearchEngine.highlightedText("@\(name)", query: freeTextQuery))
                        .lineLimit(1)
                    Spacer()
                    Text(count == 1 ? "1 note" : "\(count) notes")
                        .font(Theme.uiSwiftUIFont(size: 11))
                        .foregroundStyle(.tertiary)
                case .tag(let name, let count, _):
                    Image(systemName: "tag.fill")
                        .foregroundStyle(.secondary)
                    Text(SearchEngine.highlightedText("#\(name)", query: freeTextQuery))
                        .lineLimit(1)
                    Spacer()
                    Text(count == 1 ? "1 note" : "\(count) notes")
                        .font(Theme.uiSwiftUIFont(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }

            if case .note(let noteResult, _) = result {
                Text(SearchEngine.highlightedText(
                    rowPreviewText(for: noteResult),
                    query: freeTextQuery,
                    baseFont: Theme.uiSwiftUIFont(size: 11)
                ))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.leading, 20)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func selectedResultDetail(_ result: DedicatedSearchResult) -> some View {
        switch result {
        case .note(let noteResult, _):
            noteDetailPanel(noteResult)
        case .file(let node, _):
            fileDetailPanel(node)
        case .person(let name, let count, _):
            personDetailPanel(name: name, count: count)
        case .tag(let name, let count, _):
            tagDetailPanel(name: name, count: count)
        }
    }

    private func noteDetailPanel(_ noteResult: NoteSearchResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(noteResult.title)
                        .font(Theme.uiSwiftUIFont(size: 14, weight: .semibold))
                    Text(noteResult.relativePath)
                        .font(Theme.uiSwiftUIFont(size: 11))
                        .foregroundStyle(.tertiary)
                    if let source = noteSourceByURL[noteResult.url] {
                        sourceBadge(source)
                    }
                }
                Spacer()
                Button("Open") {
                    store.openFromSearch(noteResult.url)
                }
                .buttonStyle(.borderedProminent)
                Button("Open in Editor") {
                    store.open(noteResult.url)
                }
                .buttonStyle(.bordered)
            }

            Divider()

            ScrollView {
                Text(previewText(for: noteResult))
                    .font(Theme.uiSwiftUIFont(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .onAppear {
            engine.loadPreview(for: noteResult.url)
        }
    }

    private func fileDetailPanel(_ fileNode: FileTreeNode) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(fileNode.name)
                        .font(Theme.uiSwiftUIFont(size: 14, weight: .semibold))
                    Text(fileNode.url.path)
                        .font(Theme.uiSwiftUIFont(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer()
                Button("Open") {
                    store.openFromSearch(fileNode.url)
                }
                .buttonStyle(.borderedProminent)
                Button("Open in Editor") {
                    store.open(fileNode.url)
                }
                .buttonStyle(.bordered)
            }

            Divider()

            if let previewText = engine.previewCache[fileNode.url], !previewText.isEmpty {
                ScrollView {
                    Text(previewText)
                        .font(Theme.uiSwiftUIFont(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            } else {
                Text("No preview available.")
                    .font(Theme.uiSwiftUIFont(size: 12))
                    .foregroundStyle(.secondary)
            }

            FileDatesLabel(url: fileNode.url)
            Spacer(minLength: 0)
        }
        .padding(12)
        .onAppear {
            engine.loadPreview(for: fileNode.url)
        }
    }

    private func personDetailPanel(name: String, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("@\(name)")
                .font(Theme.uiSwiftUIFont(size: 16, weight: .semibold))
            Text(count == 1 ? "Mentioned in 1 note" : "Mentioned in \(count) notes")
                .font(Theme.uiSwiftUIFont(size: 12))
                .foregroundStyle(.secondary)
            Button("Open People Browser") {
                store.showPeopleBrowserModal(person: name)
            }
            .buttonStyle(.borderedProminent)
            Spacer(minLength: 0)
        }
        .padding(12)
    }

    private func tagDetailPanel(name: String, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("#\(name)")
                .font(Theme.uiSwiftUIFont(size: 16, weight: .semibold))
            Text(count == 1 ? "Appears in 1 note" : "Appears in \(count) notes")
                .font(Theme.uiSwiftUIFont(size: 12))
                .foregroundStyle(.secondary)
            Button("Open Tag Browser") {
                store.showTagBrowserModal(tag: name)
            }
            .buttonStyle(.borderedProminent)
            Spacer(minLength: 0)
        }
        .padding(12)
    }

    private func previewText(for noteResult: NoteSearchResult) -> String {
        let fullText = engine.previewCache[noteResult.url] ?? noteResult.preview
        let previewText = SearchEngine.focusedSnippet(
            from: fullText,
            query: freeTextQuery,
            fallback: noteResult.preview
        )
        if previewText.isEmpty {
            return noteResult.preview
        }
        return previewText
    }

    private func rowPreviewText(for noteResult: NoteSearchResult) -> String {
        let rowSource = engine.previewCache[noteResult.url] ?? noteResult.preview
        let snippetText = SearchEngine.focusedSnippet(
            from: rowSource,
            query: freeTextQuery,
            fallback: noteResult.preview
        )
        if snippetText.isEmpty {
            return noteResult.preview
        }
        return snippetText
    }

    private func preloadSelectedPreview() {
        guard let selectedResult else { return }
        switch selectedResult {
        case .note(let noteResult, _):
            engine.loadPreview(for: noteResult.url)
        case .file(let node, _):
            engine.loadPreview(for: node.url)
        case .person, .tag:
            return
        }
    }

    private func openResultKeepingSearch(_ result: DedicatedSearchResult) {
        switch result {
        case .note(let noteResult, _):
            store.openFromSearch(noteResult.url)
        case .file(let node, _):
            store.openFromSearch(node.url)
        case .person(let name, _, _):
            store.showPeopleBrowserModal(person: name)
        case .tag(let name, _, _):
            store.showTagBrowserModal(tag: name)
        }
    }

    private func moveSelection(_ direction: DedicatedSearchSelectionDirection) {
        let currentIdentifier = store.dedicatedSearch.selectedResultIdentifier
        let nextIdentifier = DedicatedSearchState.stepSelection(
            currentIdentifier: currentIdentifier,
            availableIdentifiers: resultIdentifiers,
            direction: direction
        )
        guard nextIdentifier != currentIdentifier else { return }
        store.dedicatedSearch.selectedResultIdentifier = nextIdentifier
        preloadSelectedPreview()
    }

    private func resetSearch() {
        DedicatedSearchResetBehavior.reset(
            state: store.dedicatedSearch,
            qmdResults: &qmdResults
        )
    }

    private func handleSubmit() {
        guard let selectedResult else {
            if store.qmdClient?.isWorkspaceIndexed == true,
               !activeQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                triggerQmdSearch(activeQuery)
            }
            return
        }
        openResultKeepingSearch(selectedResult)
    }

    @ViewBuilder
    private func sourceBadge(_ source: DedicatedSearchResultSource) -> some View {
        Text(source.shortLabel)
            .font(Theme.uiSwiftUIFont(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.12), in: Capsule())
            .help(source.detailLabel)
    }

    private func triggerQmdSearch(_ queryText: String) {
        engine.triggerQmdSearch(query: queryText) { [self] mapped in
            qmdResults = mapped
        }
    }

    private func binding(
        for keyPath: ReferenceWritableKeyPath<DedicatedSearchState, String>
    ) -> Binding<String> {
        Binding(
            get: {
                store.dedicatedSearch[keyPath: keyPath]
            },
            set: { newValue in
                store.dedicatedSearch[keyPath: keyPath] = newValue
            }
        )
    }

    private func facetField(
        _ title: String,
        text: Binding<String>,
        placeholder: String
    ) -> some View {
        HStack(spacing: 6) {
            Text("\(title):")
                .font(Theme.uiSwiftUIFont(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .font(Theme.uiSwiftUIFont(size: 12))
        }
    }
}
