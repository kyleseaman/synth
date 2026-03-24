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
    case note(NoteSearchResult)
    case file(node: FileTreeNode, score: Int)
    case person(name: String, count: Int, score: Int)
    case tag(name: String, count: Int, score: Int)

    var identifier: String {
        switch self {
        case .note(let noteResult):
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
        case .note(let noteResult):
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
    @State private var cachedFiles: [FileTreeNode] = []
    @State private var previewCache: [URL: String] = [:]
    @State private var qmdResults: [NoteSearchResult] = []
    @State private var isQmdSearching = false
    @State private var qmdSearchTask: Task<Void, Never>?
    @FocusState private var isQueryFocused: Bool

    private var freeTextQuery: String {
        store.dedicatedSearch.textQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var activeQuery: String {
        store.dedicatedSearch.composedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var localNoteResults: [NoteSearchResult] {
        guard !activeQuery.isEmpty else { return [] }
        return store.noteIndex.search(activeQuery)
    }

    private var mergedNoteResults: [NoteSearchResult] {
        guard !qmdResults.isEmpty else { return localNoteResults }

        var uniqueByURL: Set<URL> = []
        var mergedResults: [NoteSearchResult] = []
        for noteResult in qmdResults + localNoteResults
            where uniqueByURL.insert(noteResult.url).inserted {
            mergedResults.append(noteResult)
        }
        return mergedResults.sorted { firstResult, secondResult in
            firstResult.score > secondResult.score
        }
    }

    private var noteResultItems: [DedicatedSearchResult] {
        mergedNoteResults.map(DedicatedSearchResult.note)
    }

    private var fileResultItems: [DedicatedSearchResult] {
        guard !freeTextQuery.isEmpty else { return [] }

        let noteURLs = Set(mergedNoteResults.map(\.url))
        let recentFiles = Set(store.recentFiles)
        let scoredResults: [DedicatedSearchResult] = cachedFiles
            .filter { fileNode in
                !noteURLs.contains(fileNode.url)
            }
            .compactMap { fileNode in
                guard let fuzzyScore = fileNode.name.fuzzyScore(freeTextQuery) else { return nil }
                let recentBonus = recentFiles.contains(fileNode.url) ? 2_000 : 0
                return DedicatedSearchResult.file(node: fileNode, score: fuzzyScore + recentBonus)
            }
            .sorted { firstResult, secondResult in
                firstResult.sortScore > secondResult.sortScore
            }
        return Array(scoredResults.prefix(20))
    }

    private var personResultItems: [DedicatedSearchResult] {
        guard !freeTextQuery.isEmpty else { return [] }
        let personMatches = Array(store.peopleIndex.search(freeTextQuery).prefix(10))
        return personMatches.map { personMatch in
            let score = personMatch.name.fuzzyScore(freeTextQuery) ?? 0
            return .person(name: personMatch.name, count: personMatch.count, score: score)
        }
    }

    private var tagResultItems: [DedicatedSearchResult] {
        guard !freeTextQuery.isEmpty else { return [] }
        let tagMatches = Array(store.tagIndex.search(freeTextQuery).prefix(10))
        return tagMatches.map { tagMatch in
            let score = tagMatch.name.fuzzyScore(freeTextQuery) ?? 0
            return .tag(name: tagMatch.name, count: tagMatch.count, score: score)
        }
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
            refreshCachedFiles()
        }
        .onChange(of: store.fileTree) {
            refreshCachedFiles()
        }
        .onChange(of: activeQuery) {
            qmdResults = []
            qmdSearchTask?.cancel()
            isQmdSearching = false
        }
        .onChange(of: resultIdentifiers) { _, availableIdentifiers in
            store.dedicatedSearch.selectedResultIdentifier = DedicatedSearchState.reconcileSelection(
                currentIdentifier: store.dedicatedSearch.selectedResultIdentifier,
                availableIdentifiers: availableIdentifiers
            )
            preloadSelectedPreview()
        }
        .onDisappear {
            qmdSearchTask?.cancel()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(
                    "Search notes, files, tags, and people",
                    text: binding(for: \.textQuery)
                )
                .textFieldStyle(.plain)
                .font(Theme.uiSwiftUIFont(size: 17))
                .focused($isQueryFocused)

                if isQmdSearching {
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
                    store.dedicatedSearch.clear()
                    qmdResults = []
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

            HStack(spacing: 8) {
                if store.qmdClient?.isWorkspaceIndexed == true {
                    Button("Deep Search") {
                        triggerQmdSearch(activeQuery)
                    }
                    .buttonStyle(.bordered)
                    .disabled(activeQuery.isEmpty || isQmdSearching)

                    Text("QMD available")
                        .font(Theme.uiSwiftUIFont(size: 11))
                        .foregroundStyle(.tertiary)
                } else {
                    Text("QMD unavailable. Showing local index results.")
                        .font(Theme.uiSwiftUIFont(size: 11))
                        .foregroundStyle(.tertiary)
                }

                Spacer()
                Text("Persistent search mode. Cmd+P stays optimized for quick jumping.")
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
                    Text("Start typing to search")
                        .font(Theme.uiSwiftUIFont(size: 15, weight: .semibold))
                    Text("Add optional facet filters to narrow by title, content, path, tag, or person.")
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
                        Section("Notes") {
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
                        Section("Files") {
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
                        Section("People") {
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
                        Section("Tags") {
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
                case .note(let noteResult):
                    Image(systemName: "doc.text.magnifyingglass")
                        .foregroundStyle(.secondary)
                    Text(noteResult.title)
                        .lineLimit(1)
                    Spacer()
                    Text(noteResult.relativePath)
                        .font(Theme.uiSwiftUIFont(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                case .file(let node, _):
                    Image(systemName: "doc")
                        .foregroundStyle(.secondary)
                    Text(node.name)
                        .lineLimit(1)
                    Spacer()
                    Text(node.url.deletingLastPathComponent().lastPathComponent)
                        .font(Theme.uiSwiftUIFont(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                case .person(let name, let count, _):
                    Image(systemName: "person.fill")
                        .foregroundStyle(.secondary)
                    Text("@\(name)")
                        .lineLimit(1)
                    Spacer()
                    Text(count == 1 ? "1 note" : "\(count) notes")
                        .font(Theme.uiSwiftUIFont(size: 11))
                        .foregroundStyle(.tertiary)
                case .tag(let name, let count, _):
                    Image(systemName: "tag.fill")
                        .foregroundStyle(.secondary)
                    Text("#\(name)")
                        .lineLimit(1)
                    Spacer()
                    Text(count == 1 ? "1 note" : "\(count) notes")
                        .font(Theme.uiSwiftUIFont(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }

            if case .note(let noteResult) = result {
                Text(noteResult.preview)
                    .font(Theme.uiSwiftUIFont(size: 11))
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
        case .note(let noteResult):
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
            loadPreview(for: noteResult.url)
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

            if let previewText = previewCache[fileNode.url], !previewText.isEmpty {
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
            loadPreview(for: fileNode.url)
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
        guard let fullText = previewCache[noteResult.url], !fullText.isEmpty else {
            return noteResult.preview
        }
        let previewText = FileLauncher.focusedSnippet(
            from: fullText,
            query: activeQuery,
            fallback: noteResult.preview
        )
        if previewText.isEmpty {
            return noteResult.preview
        }
        return previewText
    }

    private func preloadSelectedPreview() {
        guard let selectedResult else { return }
        switch selectedResult {
        case .note(let noteResult):
            loadPreview(for: noteResult.url)
        case .file(let node, _):
            loadPreview(for: node.url)
        case .person, .tag:
            return
        }
    }

    private func loadPreview(for fileURL: URL) {
        if previewCache[fileURL] != nil {
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let fileText = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
            let cleanedText = FileLauncher.cleanPreviewText(fileText)
            DispatchQueue.main.async {
                previewCache[fileURL] = cleanedText
            }
        }
    }

    private func refreshCachedFiles() {
        cachedFiles = FileLauncher.flattenFiles(store.fileTree)
    }

    private func openResultKeepingSearch(_ result: DedicatedSearchResult) {
        switch result {
        case .note(let noteResult):
            store.openFromSearch(noteResult.url)
        case .file(let node, _):
            store.openFromSearch(node.url)
        case .person(let name, _, _):
            store.showPeopleBrowserModal(person: name)
        case .tag(let name, _, _):
            store.showTagBrowserModal(tag: name)
        }
    }

    private func triggerQmdSearch(_ queryText: String) {
        let trimmedQuery = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty,
              let qmdClient = store.qmdClient,
              qmdClient.isWorkspaceIndexed,
              let workspaceURL = store.workspace else {
            return
        }

        qmdSearchTask?.cancel()
        isQmdSearching = true

        qmdSearchTask = Task {
            let qmdHits = await qmdClient.search(query: trimmedQuery, limit: 20)
            guard !Task.isCancelled else { return }
            let mappedHits: [NoteSearchResult] = qmdHits.compactMap { qmdHit in
                let fileURL: URL
                if qmdHit.path.hasPrefix("/") {
                    fileURL = URL(fileURLWithPath: qmdHit.path)
                } else {
                    fileURL = workspaceURL.appendingPathComponent(qmdHit.path)
                }
                guard FileManager.default.fileExists(atPath: fileURL.path) else {
                    return nil
                }

                let boostedScore = Int(qmdHit.score * 30_000) + 10_000
                return NoteSearchResult(
                    id: fileURL,
                    title: qmdHit.title,
                    relativePath: fileURL.deletingLastPathComponent().lastPathComponent,
                    url: fileURL,
                    preview: qmdHit.snippet,
                    score: boostedScore
                )
            }

            await MainActor.run {
                qmdResults = mappedHits
                isQmdSearching = false
            }
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
