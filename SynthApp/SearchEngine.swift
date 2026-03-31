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

    private var searchTask: Task<Void, Never>?
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

    // MARK: - Debounced Search

    /// Run the full search pipeline off the main thread with a 150ms debounce.
    func search(
        query: String,
        completion: @MainActor @Sendable @escaping (SearchResult) -> Void
    ) {
        searchTask?.cancel()

        let noteIdx = noteIndex
        let peopleIdx = peopleIndex
        let tagIdx = tagIndex
        let files = cachedFiles
        let recent = recentFiles

        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }

            let result = Self.runSearchSync(
                query: query, noteIndex: noteIdx,
                peopleIndex: peopleIdx, tagIndex: tagIdx,
                files: files, recentFiles: recent
            )

            guard !Task.isCancelled else { return }
            completion(result)
        }
    }

    /// Run search immediately (no debounce). For onAppear, after QMD, etc.
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
            let cleaned = FileLauncher.cleanPreviewText(text)
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
}
