import Foundation
import Observation

// MARK: - Tag Index

@Observable class TagIndex {
    /// Map from normalized tag name -> set of file URLs containing that tag
    private(set) var tagToFiles: [String: Set<URL>] = [:]

    /// Map from file URL -> set of normalized tag names in that file
    @ObservationIgnored private var fileToTags: [URL: Set<String>] = [:]

    // Tag regex: must start with letter after #, min 2 chars after #, not preceded by # or word char
    static let tagPattern = BacklinkIndex.makeRegex(
        "(?<![#\\w])#([a-zA-Z][a-zA-Z0-9_-]{1,49})(?=[^a-zA-Z0-9_-]|$)"
    )

    // MARK: - All Tags

    /// All known tags sorted by frequency (most used first).
    var allTags: [(name: String, count: Int)] {
        tagToFiles
            .map { (name: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }

    // MARK: - Full Rebuild

    /// Rebuild from pre-read file contents (unified indexer path)
    func rebuild(from files: [UnifiedIndexer.FileContent]) {
        var newTagToFiles: [String: Set<URL>] = [:]
        var newFileToTags: [URL: Set<String>] = [:]

        for file in files {
            let tags = scanFile(content: file.content)
            newFileToTags[file.url] = tags
            for tag in tags {
                newTagToFiles[tag, default: []].insert(file.url)
            }
        }

        tagToFiles = newTagToFiles
        fileToTags = newFileToTags
    }

    // MARK: - Incremental Update

    func addFile(_ url: URL, content: String) {
        let tags = scanFile(content: content)
        fileToTags[url] = tags
        for tag in tags {
            tagToFiles[tag, default: []].insert(url)
        }
    }

    func removeFile(_ url: URL) {
        if let oldTags = fileToTags.removeValue(forKey: url) {
            for tag in oldTags {
                tagToFiles[tag]?.remove(url)
                if tagToFiles[tag]?.isEmpty == true {
                    tagToFiles.removeValue(forKey: tag)
                }
            }
        }
    }

    /// Incremental update for a single file on save. Must dispatch to main thread.
    func updateFile(_ url: URL, content: String) {
        let tags = scanFile(content: content)
        // Remove old tags for this file
        if let oldTags = fileToTags[url] {
            for tag in oldTags {
                tagToFiles[tag]?.remove(url)
                if tagToFiles[tag]?.isEmpty == true {
                    tagToFiles.removeValue(forKey: tag)
                }
            }
        }

        // Apply new scan results
        fileToTags[url] = tags
        for tag in tags {
            tagToFiles[tag, default: []].insert(url)
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
            let matches = Self.tagPattern.matches(in: line, range: range)
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

}
