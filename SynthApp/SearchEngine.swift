import Foundation

/// Unified result type for all search operations across FileLauncher and DedicatedSearchView.
struct SearchResult: Sendable {
    let notes: [NoteSearchResult]
    let files: [ScoredFile]
    let people: [ScoredMatch]
    let tags: [ScoredMatch]
}

struct ScoredFile: Sendable {
    let node: FileTreeNode
    let score: Int
}

struct ScoredMatch: Sendable {
    let name: String
    let count: Int
    let score: Int
}

/// SearchEngine centralizes the debounced search pipeline shared by
/// FileLauncher and DedicatedSearchView. It owns the cached file list,
/// preview cache, and QMD search lifecycle.
@MainActor
@Observable
final class SearchEngine {
    // MARK: - Cached State

    private(set) var cachedFiles: [FileTreeNode] = []
    private(set) var previewCache: [URL: String] = [:]
    private(set) var isQmdSearching = false

    // MARK: - Dependencies (set via configure)

    private weak var noteIndex: NoteIndex?
    private weak var peopleIndex: PeopleIndex?
    private weak var tagIndex: TagIndex?
    private var recentFiles: Set<URL> = []
    private var workspace: URL?
    private weak var qmdClient: QmdClient?

    // MARK: - Tasks

    private var qmdSearchTask: Task<Void, Never>?

    // MARK: - Configuration

    func configure(
        noteIndex: NoteIndex,
        peopleIndex: PeopleIndex,
        tagIndex: TagIndex,
        recentFiles: [URL],
        workspace: URL?,
        qmdClient: QmdClient?
    ) {
        self.noteIndex = noteIndex
        self.peopleIndex = peopleIndex
        self.tagIndex = tagIndex
        self.recentFiles = Set(recentFiles)
        self.workspace = workspace
        self.qmdClient = qmdClient
    }

    func updateRecentFiles(_ files: [URL]) {
        recentFiles = Set(files)
    }

    func refreshFileCache(from fileTree: [FileTreeNode]) {
        cachedFiles = Self.flattenFiles(fileTree)
    }

    // MARK: - Search

    /// Run the full search pipeline synchronously.
    func searchImmediate(query: String) -> SearchResult {
        Self.runSearchSync(
            query: query, noteIndex: noteIndex,
            peopleIndex: peopleIndex, tagIndex: tagIndex,
            files: cachedFiles, recentFiles: recentFiles
        )
    }

    // MARK: - QMD Search

    func triggerQmdSearch(
        query: String,
        limit: Int = 20,
        completion: @MainActor @Sendable @escaping ([NoteSearchResult]) -> Void
    ) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let qmdClient,
              qmdClient.isWorkspaceIndexed,
              let workspaceURL = workspace else {
            return
        }

        qmdSearchTask?.cancel()
        isQmdSearching = true

        qmdSearchTask = Task {
            let qmdHits = await qmdClient.search(query: trimmed, limit: limit)
            guard !Task.isCancelled else { return }

            let mapped: [NoteSearchResult] = qmdHits.compactMap { qmdHit in
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

            isQmdSearching = false
            completion(mapped)
        }
    }

    func cancelQmdSearch() {
        qmdSearchTask?.cancel()
        isQmdSearching = false
    }

    // MARK: - Preview Cache

    func loadPreview(for fileURL: URL) {
        if previewCache[fileURL] != nil { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let text = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
            let cleaned = Self.cleanPreviewText(text)
            DispatchQueue.main.async {
                self?.previewCache[fileURL] = cleaned
            }
        }
    }

    // MARK: - Internals

    private static nonisolated func runSearchSync(
        query: String,
        noteIndex: NoteIndex?,
        peopleIndex: PeopleIndex?,
        tagIndex: TagIndex?,
        files: [FileTreeNode],
        recentFiles: Set<URL>
    ) -> SearchResult {
        let trimmed = query.trimmingCharacters(in: .whitespaces)

        let notes = trimmed.isEmpty ? [] : (noteIndex?.search(trimmed) ?? [])

        let people: [ScoredMatch] = trimmed.isEmpty ? [] :
            (peopleIndex?.search(trimmed) ?? []).prefix(10).map {
                ScoredMatch(name: $0.name, count: $0.count,
                            score: $0.name.fuzzyScore(trimmed) ?? 0)
            }

        let tags: [ScoredMatch] = trimmed.isEmpty ? [] :
            (tagIndex?.search(trimmed) ?? []).prefix(10).map {
                ScoredMatch(name: $0.name, count: $0.count,
                            score: $0.name.fuzzyScore(trimmed) ?? 0)
            }

        let scoredFiles: [ScoredFile]
        if trimmed.isEmpty {
            scoredFiles = []
        } else {
            let noteURLs = Set(notes.map(\.url))
            scoredFiles = files
                .filter { !noteURLs.contains($0.url) }
                .compactMap { fileNode -> ScoredFile? in
                    guard let score = fileNode.name.fuzzyScore(trimmed) else { return nil }
                    let bonus = recentFiles.contains(fileNode.url) ? 2_000 : 0
                    return ScoredFile(node: fileNode, score: score + bonus)
                }
                .sorted { $0.score > $1.score }
        }

        return SearchResult(notes: notes, files: scoredFiles, people: people, tags: tags)
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

    // MARK: - Text Utilities

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
        let terms = snippetTerms(from: query)

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

    nonisolated private static func snippetTerms(from query: String) -> [String] {
        let parsedQuery = NoteIndex.parseLocalSearchQuery(query)
        var orderedTerms: [String] = []
        var seenTerms: Set<String> = []

        func appendTerm(_ rawTerm: String) {
            let normalizedTerm = rawTerm
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard normalizedTerm.count >= 3 else { return }
            guard seenTerms.insert(normalizedTerm).inserted else { return }
            orderedTerms.append(normalizedTerm)
        }

        func appendTokens(from rawValue: String) {
            for token in rawValue.lowercased().split(whereSeparator: { character in
                !character.isLetter && !character.isNumber
            }) {
                appendTerm(String(token))
            }
        }

        for phrase in parsedQuery.normalizedPhrases {
            appendTerm(phrase)
            appendTokens(from: phrase)
        }
        for requiredContent in parsedQuery.requiredContentTerms {
            appendTerm(requiredContent)
            appendTokens(from: requiredContent)
        }
        for requiredTitle in parsedQuery.requiredTitleTerms {
            appendTerm(requiredTitle)
            appendTokens(from: requiredTitle)
        }
        for queryToken in parsedQuery.queryTokens {
            appendTerm(queryToken)
        }

        if orderedTerms.isEmpty {
            appendTokens(from: parsedQuery.displayQuery)
        }

        return orderedTerms
    }
}
