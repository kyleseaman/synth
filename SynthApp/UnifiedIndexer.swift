import Foundation

/// Context for unified indexing - holds all indexes to update
struct IndexContext {
    let noteIndex: NoteIndex
    let backlinkIndex: BacklinkIndex
    let tagIndex: TagIndex
    let peopleIndex: PeopleIndex
}

/// Unified indexer that reads each file once and updates all indexes
enum UnifiedIndexer {
    /// Result of scanning a single file
    struct FileContent: Sendable {
        let url: URL
        let content: String
    }

    /// Rebuild all indexes from file tree, reading each file only once.
    /// File reading is parallelized; index building runs on the calling thread.
    /// For async variant, use `rebuildAllAsync`.
    static func rebuildAll(
        fileTree: [FileTreeNode],
        workspace: URL,
        context: IndexContext
    ) {
        let fileContents = readFiles(from: fileTree)
        applyToIndexes(fileContents, workspace: workspace, context: context)
    }

    /// Async rebuild: reads files off the main thread,
    /// then applies results on MainActor.
    @MainActor
    static func rebuildAllAsync(
        fileTree: [FileTreeNode],
        workspace: URL,
        context: IndexContext
    ) async {
        let fileContents = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let contents = readFiles(from: fileTree)
                continuation.resume(returning: contents)
            }
        }
        applyToIndexes(fileContents, workspace: workspace, context: context)
    }

    // MARK: - Incremental Operations

    static func addFile(
        _ url: URL, content: String, workspace: URL,
        context: IndexContext
    ) {
        context.noteIndex.addFile(url, content: content, workspace: workspace)
        context.backlinkIndex.addFile(url, content: content)
        context.tagIndex.addFile(url, content: content)
        context.peopleIndex.addFile(url, content: content)
    }

    static func removeFile(_ url: URL, context: IndexContext) {
        context.noteIndex.removeFile(url)
        context.backlinkIndex.removeFile(url)
        context.tagIndex.removeFile(url)
        context.peopleIndex.removeFile(url)
    }

    static func updateFile(
        _ url: URL, content: String, context: IndexContext
    ) {
        context.noteIndex.updateFile(url, content: content)
        context.backlinkIndex.updateFile(url, content: content)
        context.tagIndex.updateFile(url, content: content)
        context.peopleIndex.updateFile(url, content: content)
    }

    // MARK: - Private

    private static func readFiles(from fileTree: [FileTreeNode]) -> [FileContent] {
        let files = flattenMarkdownFiles(fileTree)
        guard !files.isEmpty else { return [] }

        let collector = FileContentCollector(capacity: files.count)

        DispatchQueue.concurrentPerform(iterations: files.count) { index in
            let file = files[index]
            guard let content = try? String(contentsOf: file.url, encoding: .utf8) else { return }
            collector.store(
                FileContent(url: file.url, content: content),
                at: index
            )
        }

        return collector.allFiles()
    }

    private static func applyToIndexes(
        _ fileContents: [FileContent],
        workspace: URL,
        context: IndexContext
    ) {
        context.noteIndex.rebuild(from: fileContents, workspace: workspace)
        context.backlinkIndex.rebuild(from: fileContents)
        context.tagIndex.rebuild(from: fileContents)
        context.peopleIndex.rebuild(from: fileContents)
    }

    private static func flattenMarkdownFiles(_ nodes: [FileTreeNode]) -> [FileTreeNode] {
        var result: [FileTreeNode] = []
        for node in nodes {
            if node.isDirectory {
                if let children = node.children {
                    result.append(contentsOf: flattenMarkdownFiles(children))
                }
            } else if node.url.pathExtension == "md" || node.url.pathExtension == "txt" {
                result.append(node)
            }
        }
        return result
    }
}

private final class FileContentCollector: @unchecked Sendable {
    private var files: [UnifiedIndexer.FileContent?]
    private let collectorLock = NSLock()

    init(capacity: Int) {
        self.files = Array(repeating: nil, count: capacity)
    }

    func store(_ file: UnifiedIndexer.FileContent, at index: Int) {
        collectorLock.lock()
        files[index] = file
        collectorLock.unlock()
    }

    func allFiles() -> [UnifiedIndexer.FileContent] {
        collectorLock.lock()
        defer { collectorLock.unlock() }
        return files.compactMap { $0 }
    }
}
