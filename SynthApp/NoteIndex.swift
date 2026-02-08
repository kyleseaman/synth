import Foundation
import Observation

// MARK: - Note Search Result

struct NoteSearchResult: Identifiable {
    let id: URL
    let title: String
    let relativePath: String
    let url: URL
}

// MARK: - Note Index

@Observable class NoteIndex {
    private(set) var notes: [NoteSearchResult] = []
    @ObservationIgnored private var allNotes: [NoteSearchResult] = []
    /// Whether the index has been populated at least once.
    @ObservationIgnored private(set) var isPopulated = false

    func rebuild(from fileTree: [FileTreeNode], workspace: URL?) {
        allNotes = Self.flatten(fileTree, workspace: workspace)
        notes = allNotes
        isPopulated = true
    }

    func search(_ query: String) -> [NoteSearchResult] {
        if query.isEmpty { return Array(allNotes.prefix(20)) }
        return allNotes
            .compactMap { note -> (NoteSearchResult, Int)? in
                guard let score = note.title.fuzzyScore(query) else { return nil }
                return (note, score)
            }
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
    }

    func findExact(_ title: String) -> NoteSearchResult? {
        allNotes.first { $0.title.lowercased() == title.lowercased() }
    }

    private static func flatten(_ nodes: [FileTreeNode], workspace: URL?) -> [NoteSearchResult] {
        var result: [NoteSearchResult] = []
        for node in nodes {
            if !node.isDirectory {
                let ext = node.url.pathExtension.lowercased()
                if ext == "md" || ext == "txt" {
                    let title = node.url.deletingPathExtension().lastPathComponent
                    let parent = node.url.deletingLastPathComponent().lastPathComponent
                    result.append(NoteSearchResult(
                        id: node.url, title: title,
                        relativePath: parent, url: node.url
                    ))
                }
            }
            if let children = node.children {
                result.append(contentsOf: flatten(children, workspace: workspace))
            }
        }
        return result
    }
}
