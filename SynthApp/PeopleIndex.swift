import Foundation

// MARK: - People Index

class PeopleIndex: ObservableObject {
    /// Map from normalized person name -> set of file URLs containing that mention
    @Published private(set) var personToFiles: [String: Set<URL>] = [:]

    /// Map from file URL -> set of normalized person names in that file
    private var fileToPersons: [URL: Set<String>] = [:]

    /// Global people set persisted across workspaces via UserDefaults
    @Published private(set) var globalPeople: Set<String> = []

    private let storageKey = "synth.globalPeople"

    // Person regex: @ followed by letter, then 1-49 word chars/hyphens, not preceded by word char or @
    // swiftlint:disable:next force_try
    static let personPattern = try! NSRegularExpression(
        pattern: "(?<![\\w@])@([A-Za-z][A-Za-z0-9_-]{1,49})(?=[^a-zA-Z0-9_-]|$)"
    )

    private static let dateTokens: Set<String> = ["today", "yesterday", "tomorrow"]

    init() {
        loadGlobal()
    }

    // MARK: - All People

    /// All known people: merges workspace scan with global set, sorted by frequency (most mentioned first).
    var allPeople: [(name: String, count: Int)] {
        // Start with workspace people and their counts
        var merged: [String: Int] = [:]
        for (name, files) in personToFiles {
            merged[name] = files.count
        }
        // Add global people not already in workspace
        for name in globalPeople where merged[name] == nil {
            merged[name] = 0
        }
        return merged
            .map { (name: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    // MARK: - Full Rebuild

    /// Full rebuild from workspace file tree.
    func rebuild(fileTree: [FileTreeNode]) {
        var newPersonToFiles: [String: Set<URL>] = [:]
        var newFileToPersons: [URL: Set<String>] = [:]

        let files = Self.flattenMarkdownFiles(fileTree)
        for file in files {
            guard let content = try? String(contentsOf: file.url, encoding: .utf8) else { continue }
            let people = scanFile(content: content)
            newFileToPersons[file.url] = people
            for person in people {
                newPersonToFiles[person, default: []].insert(file.url)
            }
        }

        DispatchQueue.main.async {
            self.personToFiles = newPersonToFiles
            self.fileToPersons = newFileToPersons
            // Merge discovered people into global set
            let discovered = Set(newPersonToFiles.keys)
            if !discovered.isEmpty {
                self.globalPeople.formUnion(discovered)
                self.saveGlobal()
            }
        }
    }

    // MARK: - Incremental Update

    /// Incremental update for a single file on save.
    func updateFile(_ url: URL, content: String) {
        let people = scanFile(content: content)
        DispatchQueue.main.async {
            // Remove old people for this file
            if let oldPeople = self.fileToPersons[url] {
                for person in oldPeople {
                    self.personToFiles[person]?.remove(url)
                    if self.personToFiles[person]?.isEmpty == true {
                        self.personToFiles.removeValue(forKey: person)
                    }
                }
            }

            // Apply new scan results
            self.fileToPersons[url] = people
            for person in people {
                self.personToFiles[person, default: []].insert(url)
            }

            // Merge into global set
            if !people.isEmpty {
                self.globalPeople.formUnion(people)
                self.saveGlobal()
            }
        }
    }

    // MARK: - Queries

    /// Search people using fuzzy matching.
    func search(_ query: String) -> [(name: String, count: Int)] {
        let all = allPeople
        if query.isEmpty { return all }
        return all
            .compactMap { person -> (name: String, count: Int, score: Int)? in
                guard let score = person.name.fuzzyScore(query) else { return nil }
                return (name: person.name, count: person.count, score: score)
            }
            .sorted { $0.score > $1.score }
            .map { (name: $0.name, count: $0.count) }
    }

    /// Get files mentioning a specific person.
    func notes(for person: String) -> Set<URL> {
        personToFiles[person.lowercased()] ?? []
    }

    /// Get files matching ALL given people (intersection).
    func files(matchingAll people: Set<String>) -> Set<URL> {
        guard let firstPerson = people.first else { return [] }
        var result = personToFiles[firstPerson] ?? []
        for person in people.dropFirst() {
            result = result.intersection(personToFiles[person] ?? [])
        }
        return result
    }

    // MARK: - Private

    func scanFile(content: String) -> Set<String> {
        var people: Set<String> = []
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
            let matches = Self.personPattern.matches(in: line, range: range)
            for match in matches {
                guard let personRange = Range(match.range(at: 1), in: line) else { continue }
                let personName = String(line[personRange]).lowercased()
                // Filter out date tokens
                guard !Self.dateTokens.contains(personName) else { continue }
                guard personName.count >= 2 else { continue }
                people.insert(personName)
            }
        }

        return people
    }

    // MARK: - Persistence

    private func loadGlobal() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        guard let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) else { return }
        globalPeople = decoded
    }

    private func saveGlobal() {
        guard let data = try? JSONEncoder().encode(globalPeople) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
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
