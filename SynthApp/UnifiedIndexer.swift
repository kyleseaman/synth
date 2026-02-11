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
    static func rebuildAll(
        fileTree: [FileTreeNode],
        workspace: URL,
        context: IndexContext
    ) {
        let files = flattenMarkdownFiles(fileTree)
        var fileContents: [FileContent] = []
        fileContents.reserveCapacity(files.count)

        // Single pass: read all files
        for file in files {
            guard let content = try? String(contentsOf: file.url, encoding: .utf8) else { continue }
            fileContents.append(FileContent(url: file.url, content: content))
        }

        // Feed to each index with pre-read content
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
