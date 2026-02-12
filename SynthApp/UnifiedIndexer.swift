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
    struct FileContent {
        let url: URL
        let content: String
    }

    /// Rebuild all indexes from file tree, reading each file only once
    /// File reading is parallelized for better performance on large workspaces
    static func rebuildAll(
        fileTree: [FileTreeNode],
        workspace: URL,
        context: IndexContext
    ) {
        let files = flattenMarkdownFiles(fileTree)

        // Parallel file reading using DispatchQueue for concurrent I/O
        let fileContents = readFilesInParallel(files)

        // Feed to each index with pre-read content
        context.noteIndex.rebuild(from: fileContents, workspace: workspace)
        context.backlinkIndex.rebuild(from: fileContents)
        context.tagIndex.rebuild(from: fileContents)
        context.peopleIndex.rebuild(from: fileContents)
    }

    /// Read files in parallel using a concurrent dispatch queue
    private static func readFilesInParallel(_ files: [FileTreeNode]) -> [FileContent] {
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
