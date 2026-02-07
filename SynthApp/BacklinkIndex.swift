import Foundation

// MARK: - Backlink Index

class BacklinkIndex: ObservableObject {
    /// Map from note title (lowercased) -> set of URLs that reference it
    @Published private(set) var incomingLinks: [String: Set<URL>] = [:]

    /// Map from source URL -> set of note titles it links to
    private var outgoingLinks: [URL: Set<String>] = [:]

    /// Map from source URL -> (note title -> context snippet)
    @Published private(set) var contextSnippets: [URL: [String: String]] = [:]

    // swiftlint:disable:next force_try
    private let wikiPattern = try! NSRegularExpression(pattern: "\\[\\[(.+?)\\]\\]")

    /// Matches unfurled date mentions like @2026-02-07
    // swiftlint:disable:next force_try
    private let atDatePattern = try! NSRegularExpression(
        pattern: "@(\\d{4}-\\d{2}-\\d{2})"
    )

    // MARK: - Full Rebuild

    /// Full rebuild from workspace file tree. Run on background thread.
    func rebuild(fileTree: [FileTreeNode]) {
        var newIncoming: [String: Set<URL>] = [:]
        var newOutgoing: [URL: Set<String>] = [:]
        var newSnippets: [URL: [String: String]] = [:]

        let files = Self.flattenMarkdownFiles(fileTree)
        for file in files {
            guard let content = try? String(contentsOf: file.url, encoding: .utf8) else { continue }
            let (targets, snippets) = scanFile(content: content)
            newOutgoing[file.url] = targets
            newSnippets[file.url] = snippets
            for target in targets {
                newIncoming[target, default: []].insert(file.url)
            }
        }

        DispatchQueue.main.async {
            self.incomingLinks = newIncoming
            self.outgoingLinks = newOutgoing
            self.contextSnippets = newSnippets
        }
    }

    // MARK: - Incremental Update

    /// Incremental update for a single file on save. Must dispatch to main thread.
    func updateFile(_ url: URL, content: String) {
        let (targets, snippets) = scanFile(content: content)
        DispatchQueue.main.async {
            // Remove old outgoing links for this file
            if let oldTargets = self.outgoingLinks[url] {
                for target in oldTargets {
                    self.incomingLinks[target]?.remove(url)
                    if self.incomingLinks[target]?.isEmpty == true {
                        self.incomingLinks.removeValue(forKey: target)
                    }
                }
            }

            // Apply new scan results
            self.outgoingLinks[url] = targets
            self.contextSnippets[url] = snippets
            for target in targets {
                self.incomingLinks[target, default: []].insert(url)
            }
        }
    }

    // MARK: - Queries

    /// Get all URLs that link to a given note title.
    func links(to noteTitle: String) -> Set<URL> {
        incomingLinks[noteTitle.lowercased()] ?? []
    }

    /// Get the context snippet for a source URL linking to a target title.
    func snippet(from source: URL, to noteTitle: String) -> String? {
        contextSnippets[source]?[noteTitle.lowercased()]
    }

    /// Get outgoing link targets from a given URL.
    func outgoing(from url: URL) -> Set<String> {
        outgoingLinks[url] ?? []
    }

    // MARK: - Private

    private func scanFile(content: String) -> (targets: Set<String>, snippets: [String: String]) {
        var targets: Set<String> = []
        var snippets: [String: String] = [:]
        let lines = content.components(separatedBy: "\n")

        for line in lines {
            let range = NSRange(location: 0, length: line.utf16.count)

            // Scan [[wiki links]]
            let wikiMatches = wikiPattern.matches(in: line, range: range)
            for match in wikiMatches {
                guard let innerRange = Range(match.range(at: 1), in: line) else { continue }
                var target = String(line[innerRange]).lowercased()
                // Strip alias if present: [[Actual|Display]] -> actual
                if let pipeIndex = target.firstIndex(of: "|") {
                    target = String(target[..<pipeIndex])
                        .trimmingCharacters(in: .whitespaces)
                }
                targets.insert(target)
                let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                if trimmedLine.count > 120 {
                    snippets[target] = String(trimmedLine.prefix(120)) + "..."
                } else {
                    snippets[target] = trimmedLine
                }
            }

            // Scan unfurled @date mentions (@2026-02-07)
            let dateMatches = atDatePattern.matches(
                in: line, range: range
            )
            for match in dateMatches {
                guard let innerRange = Range(
                    match.range(at: 1), in: line
                ) else { continue }
                let target = String(line[innerRange])
                    .lowercased()
                targets.insert(target)
                let trimmedLine = line.trimmingCharacters(
                    in: .whitespaces
                )
                if snippets[target] == nil {
                    if trimmedLine.count > 120 {
                        snippets[target] = String(
                            trimmedLine.prefix(120)
                        ) + "..."
                    } else {
                        snippets[target] = trimmedLine
                    }
                }
            }

        }

        return (targets, snippets)
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
