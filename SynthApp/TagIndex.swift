import Foundation

// MARK: - Tag Index

class TagIndex: ObservableObject {
    /// Map from normalized tag name -> set of file URLs containing that tag
    @Published private(set) var tagToFiles: [String: Set<URL>] = [:]

    /// Map from file URL -> set of normalized tag names in that file
    private var fileToTags: [URL: Set<String>] = [:]

    // Tag regex: must start with letter after #, min 2 chars after #, not preceded by # or word char
    // swiftlint:disable:next force_try
    private let tagPattern = try! NSRegularExpression(
        pattern: "(?<![#\\w])#([a-zA-Z][a-zA-Z0-9_-]{1,49})(?=[^a-zA-Z0-9_-]|$)"
    )

    // MARK: - All Tags

    /// All known tags sorted by frequency (most used first).
    var allTags: [(name: String, count: Int)] {
        tagToFiles
            .map { (name: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }

    // MARK: - Full Rebuild

    /// Full rebuild from workspace file tree.
    func rebuild(fileTree: [FileTreeNode]) {
        var newTagToFiles: [String: Set<URL>] = [:]
        var newFileToTags: [URL: Set<String>] = [:]

        let files = Self.flattenMarkdownFiles(fileTree)
        for file in files {
            guard let content = try? String(contentsOf: file.url, encoding: .utf8) else { continue }
            let tags = scanFile(content: content)
            newFileToTags[file.url] = tags
            for tag in tags {
                newTagToFiles[tag, default: []].insert(file.url)
            }
        }

        DispatchQueue.main.async {
            self.tagToFiles = newTagToFiles
            self.fileToTags = newFileToTags
        }
    }

    // MARK: - Incremental Update

    /// Incremental update for a single file on save. Must dispatch to main thread.
    func updateFile(_ url: URL, content: String) {
        let tags = scanFile(content: content)
        DispatchQueue.main.async {
            // Remove old tags for this file
            if let oldTags = self.fileToTags[url] {
                for tag in oldTags {
                    self.tagToFiles[tag]?.remove(url)
                    if self.tagToFiles[tag]?.isEmpty == true {
                        self.tagToFiles.removeValue(forKey: tag)
                    }
                }
            }

            // Apply new scan results
            self.fileToTags[url] = tags
            for tag in tags {
                self.tagToFiles[tag, default: []].insert(url)
            }
        }
    }

    // MARK: - Queries

    /// Search tags using fuzzy matching.
    func search(_ query: String) -> [(name: String, count: Int)] {
        let all = allTags
        if query.isEmpty { return all }
        return all
            .compactMap { tag -> (name: String, count: Int, score: Int)? in
                guard let score = tag.name.fuzzyScore(query) else { return nil }
                return (name: tag.name, count: tag.count, score: score)
            }
            .sorted { $0.score > $1.score }
            .map { (name: $0.name, count: $0.count) }
    }

    /// Get tags for a specific file.
    func tags(for url: URL) -> Set<String> {
        fileToTags[url] ?? []
    }

    /// Get files matching ALL given tags (intersection).
    func files(matchingAll tags: Set<String>) -> Set<URL> {
        guard let firstTag = tags.first else { return [] }
        var result = tagToFiles[firstTag] ?? []
        for tag in tags.dropFirst() {
            result = result.intersection(tagToFiles[tag] ?? [])
        }
        return result
    }

    /// Get files for a single tag.
    func notes(for tag: String) -> Set<URL> {
        tagToFiles[tag.lowercased()] ?? []
    }

    // MARK: - Private

    private func scanFile(content: String) -> Set<String> {
        var tags: Set<String> = []
        let lines = content.components(separatedBy: "\n")
        var inCodeBlock = false

        for line in lines {
            // Track fenced code blocks
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inCodeBlock.toggle()
                continue
            }
            if inCodeBlock { continue }

            let range = NSRange(location: 0, length: line.utf16.count)
            let matches = tagPattern.matches(in: line, range: range)
            for match in matches {
                guard let tagRange = Range(match.range(at: 1), in: line) else { continue }
                let tagName = String(line[tagRange]).lowercased()
                // Skip tags with only 1 char after #
                guard tagName.count >= 2 else { continue }
                tags.insert(tagName)
            }
        }

        return tags
    }

    private static func flattenMarkdownFiles(_ nodes: [FileTreeNode]) -> [FileTreeNode] {
        var result: [FileTreeNode] = []
        for node in nodes {
            if !node.isDirectory {
                let ext = node.url.pathExtension.lowercased()
                if ext == "md" || ext == "txt" {
                    result.append(node)
                }
            }
            if let children = node.children {
                result.append(contentsOf: flattenMarkdownFiles(children))
            }
        }
        return result
    }
}
