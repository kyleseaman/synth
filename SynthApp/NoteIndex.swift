import Foundation
import Observation

// MARK: - Note Search Result

struct NoteSearchResult: Identifiable {
    let id: URL
    let title: String
    let relativePath: String
    let url: URL
    let preview: String
    let score: Int

    init(
        id: URL,
        title: String,
        relativePath: String,
        url: URL,
        preview: String = "",
        score: Int = 0
    ) {
        self.id = id
        self.title = title
        self.relativePath = relativePath
        self.url = url
        self.preview = preview
        self.score = score
    }
}

extension NoteIndex {
    private struct QuerySegment {
        let text: String
        let isQuoted: Bool
        let allowsScopedParsing: Bool
    }

    private enum QueryScope {
        case path
        case tag
        case person
        case title
        case content
    }

    private struct QueryFilters {
        var requiredTags: Set<String> = []
        var excludedTags: Set<String> = []
        var requiredPeople: Set<String> = []
        var excludedPeople: Set<String> = []
        var requiredPaths: [String] = []
        var excludedPaths: [String] = []
        var requiredTitleTerms: [String] = []
        var excludedTitleTerms: [String] = []
        var requiredContentTerms: [String] = []
        var excludedContentTerms: [String] = []
    }

    static func parseLocalSearchQuery(_ query: String) -> LocalSearchQuery {
        parseQuery(query)
    }

    private static func parseQuery(_ query: String) -> LocalSearchQuery {
        let segments = splitQuerySegments(query)
        var positiveTerms: [String] = []
        var negativeTerms: [String] = []
        var positivePhrases: [String] = []
        var negativePhrases: [String] = []
        var filters = QueryFilters()

        for segment in segments {
            let rawText = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawText.isEmpty else { continue }

            var tokenText = rawText
            let isNegated = tokenText.hasPrefix("-") && tokenText.count > 1
            if isNegated {
                tokenText.removeFirst()
            }
            guard !tokenText.isEmpty else { continue }

            if segment.isQuoted && !segment.allowsScopedParsing {
                if isNegated {
                    negativePhrases.append(tokenText)
                } else {
                    positivePhrases.append(tokenText)
                }
                continue
            }

            if consumeScopedClause(
                tokenText,
                isNegated: isNegated,
                filters: &filters
            ) {
                continue
            }

            if tokenText.hasPrefix("#"), let tagFilter = normalizeTag(tokenText) {
                if isNegated {
                    filters.excludedTags.insert(tagFilter)
                } else {
                    filters.requiredTags.insert(tagFilter)
                }
                continue
            }
            if tokenText.hasPrefix("@"), let personFilter = normalizePerson(tokenText) {
                if isNegated {
                    filters.excludedPeople.insert(personFilter)
                } else {
                    filters.requiredPeople.insert(personFilter)
                }
                continue
            }

            if segment.isQuoted {
                if isNegated {
                    negativePhrases.append(tokenText)
                } else {
                    positivePhrases.append(tokenText)
                }
                continue
            }

            if isNegated {
                negativeTerms.append(tokenText)
            } else {
                positiveTerms.append(tokenText)
            }
        }

        let normalizedPhrases = positivePhrases.map(normalizeText).filter { !$0.isEmpty }
        let excludedPhrases = negativePhrases.map(normalizeText).filter { !$0.isEmpty }
        let phraseTokens = positivePhrases.flatMap(tokens(from:))
        let termTokens = positiveTerms.flatMap(tokens(from:)) + phraseTokens
        let excludedTokens = Set(negativeTerms.flatMap(tokens(from:)))
        let displayTerms = positiveTerms + positivePhrases
        let displayQuery = displayTerms.joined(separator: " ").trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let normalizedQuery = normalizeText(displayQuery)

        return LocalSearchQuery(
            displayQuery: displayQuery,
            normalizedQuery: normalizedQuery,
            queryTokens: termTokens,
            excludedQueryTokens: excludedTokens,
            normalizedPhrases: normalizedPhrases,
            excludedPhrases: excludedPhrases,
            requiredTags: filters.requiredTags,
            excludedTags: filters.excludedTags,
            requiredPeople: filters.requiredPeople,
            excludedPeople: filters.excludedPeople,
            requiredPaths: filters.requiredPaths,
            excludedPaths: filters.excludedPaths,
            requiredTitleTerms: filters.requiredTitleTerms,
            excludedTitleTerms: filters.excludedTitleTerms,
            requiredContentTerms: filters.requiredContentTerms,
            excludedContentTerms: filters.excludedContentTerms
        )
    }

    private static func consumeScopedClause(
        _ text: String,
        isNegated: Bool,
        filters: inout QueryFilters
    ) -> Bool {
        guard let scopedClause = parseScopedClause(text) else { return false }

        switch scopedClause.scope {
        case .path:
            if isNegated {
                filters.excludedPaths.append(scopedClause.value.lowercased())
            } else {
                filters.requiredPaths.append(scopedClause.value.lowercased())
            }
            return true
        case .tag:
            guard let normalizedTag = normalizeTag(scopedClause.value) else { return false }
            if isNegated {
                filters.excludedTags.insert(normalizedTag)
            } else {
                filters.requiredTags.insert(normalizedTag)
            }
            return true
        case .person:
            guard let normalizedPerson = normalizePerson(scopedClause.value) else { return false }
            if isNegated {
                filters.excludedPeople.insert(normalizedPerson)
            } else {
                filters.requiredPeople.insert(normalizedPerson)
            }
            return true
        case .title:
            let normalizedValue = normalizeText(scopedClause.value)
            guard !normalizedValue.isEmpty else { return false }
            if isNegated {
                filters.excludedTitleTerms.append(normalizedValue)
            } else {
                filters.requiredTitleTerms.append(normalizedValue)
            }
            return true
        case .content:
            let normalizedValue = normalizeText(scopedClause.value)
            guard !normalizedValue.isEmpty else { return false }
            if isNegated {
                filters.excludedContentTerms.append(normalizedValue)
            } else {
                filters.requiredContentTerms.append(normalizedValue)
            }
            return true
        }
    }

    private static func parseScopedClause(_ text: String) -> (scope: QueryScope, value: String)? {
        let parts = text.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }

        let rawKey = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let rawValue = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawValue.isEmpty else { return nil }

        switch rawKey {
        case "path", "in":
            return (.path, rawValue)
        case "tag":
            return (.tag, rawValue)
        case "person", "people", "mention":
            return (.person, rawValue)
        case "title":
            return (.title, rawValue)
        case "content", "body", "text":
            return (.content, rawValue)
        default:
            return nil
        }
    }

    private static func splitQuerySegments(_ query: String) -> [QuerySegment] {
        var segments: [QuerySegment] = []
        var currentToken = ""
        var index = query.startIndex

        func flushCurrentToken(
            isQuoted: Bool = false,
            allowsScopedParsing: Bool = false
        ) {
            let trimmed = currentToken.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                currentToken = ""
                return
            }
            segments.append(
                QuerySegment(
                    text: trimmed,
                    isQuoted: isQuoted,
                    allowsScopedParsing: allowsScopedParsing
                )
            )
            currentToken = ""
        }

        while index < query.endIndex {
            let character = query[index]

            if character.isWhitespace {
                flushCurrentToken()
                index = query.index(after: index)
                continue
            }

            if character == "\"" {
                if currentToken.hasSuffix(":") {
                    let valueStart = query.index(after: index)
                    let quotedSegment = readQuotedSegment(query, from: valueStart)
                    currentToken.append(quotedSegment.text)
                    flushCurrentToken(isQuoted: true, allowsScopedParsing: true)
                    index = quotedSegment.nextIndex
                    continue
                }

                if currentToken == "-" {
                    let valueStart = query.index(after: index)
                    let quotedSegment = readQuotedSegment(query, from: valueStart)
                    let trimmed = quotedSegment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        segments.append(
                            QuerySegment(
                                text: "-\(trimmed)",
                                isQuoted: true,
                                allowsScopedParsing: false
                            )
                        )
                    }
                    currentToken = ""
                    index = quotedSegment.nextIndex
                    continue
                }

                flushCurrentToken()
                let valueStart = query.index(after: index)
                let quotedSegment = readQuotedSegment(query, from: valueStart)
                let trimmed = quotedSegment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    segments.append(
                        QuerySegment(
                            text: trimmed,
                            isQuoted: true,
                            allowsScopedParsing: false
                        )
                    )
                }
                index = quotedSegment.nextIndex
                continue
            }

            currentToken.append(character)
            index = query.index(after: index)
        }

        flushCurrentToken()
        return segments
    }

    private static func readQuotedSegment(
        _ query: String,
        from startIndex: String.Index
    ) -> (text: String, nextIndex: String.Index) {
        var currentIndex = startIndex
        var value = ""

        while currentIndex < query.endIndex {
            let character = query[currentIndex]
            if character == "\"" {
                let nextIndex = query.index(after: currentIndex)
                return (value, nextIndex)
            }
            value.append(character)
            currentIndex = query.index(after: currentIndex)
        }

        return (value, currentIndex)
    }
}

// MARK: - Note Index

@Observable final class NoteIndex {
    private struct IndexedNote {
        let result: NoteSearchResult
        let normalizedTitle: String
        let normalizedContent: String
        let rawContentLowercased: String
        let titleTokens: [String]
        let contentTokenCounts: [String: Int]
        let previewLines: [String]
        let tags: Set<String>
        let mentions: Set<String>
        let modifiedAt: Date
    }

    struct LocalSearchQuery {
        let displayQuery: String
        let normalizedQuery: String
        let queryTokens: [String]
        let excludedQueryTokens: Set<String>
        let normalizedPhrases: [String]
        let excludedPhrases: [String]
        let requiredTags: Set<String>
        let excludedTags: Set<String>
        let requiredPeople: Set<String>
        let excludedPeople: Set<String>
        let requiredPaths: [String]
        let excludedPaths: [String]
        let requiredTitleTerms: [String]
        let excludedTitleTerms: [String]
        let requiredContentTerms: [String]
        let excludedContentTerms: [String]

        var hasSearchTerms: Bool {
            !queryTokens.isEmpty || !normalizedPhrases.isEmpty
        }
    }

    private static let searchableExtensions: Set<String> = ["md", "txt"]
    @ObservationIgnored private static let tagPattern = try? NSRegularExpression(
        pattern: "(?<![#\\w])#([a-zA-Z][a-zA-Z0-9_-]{1,49})(?=[^a-zA-Z0-9_-]|$)"
    )
    @ObservationIgnored private static let mentionPattern = try? NSRegularExpression(
        pattern: "(?<![\\w@])@([A-Za-z][A-Za-z0-9_-]*(?:\\s[A-Z][a-zA-Z0-9_-]*)*)(?=[^a-zA-Z0-9_-]|$)"
    )

    @ObservationIgnored private static let semanticMap: [String: Set<String>] = buildSemanticMap()
    private enum ScoreWeights {
        static let exactTitleMatch = 24_000
        static let partialTitleMatch = 9_000
        static let exactContentMatch = 2_400
        static let titleFuzzyMultiplier = 4
        static let titlePhraseMatch = 5_000
        static let contentPhraseMatch = 2_800
        static let titleTokenMatch = 1_600
        static let titlePrefixTokenMatch = 500
        static let maxContentFrequencyCount = 6
        static let contentTokenMatch = 220
        static let allTokensMatchBonus = 1_600
        static let partialTokenMatchBonus = 200
        static let filterOnlyQueryBonus = 800
    }

    private enum RecencyWeights {
        static let lastDay = 3_000
        static let lastWeek = 1_800
        static let lastMonth = 800
    }

    private static func buildSemanticMap() -> [String: Set<String>] {
        let groups: [[String]] = [
            ["recap", "summary", "overview", "synopsis"],
            ["todo", "task", "action", "followup", "nextstep"],
            ["idea", "concept", "brainstorm", "proposal"],
            ["meeting", "sync", "standup", "call", "discussion"],
            ["plan", "roadmap", "strategy", "timeline"],
            ["issue", "bug", "problem", "defect", "incident"],
            ["search", "find", "discover", "lookup"],
            ["learn", "study", "research", "explore"]
        ]

        var map: [String: Set<String>] = [:]
        for group in groups {
            let normalizedGroup = Set(group.compactMap { Self.normalizeToken($0) })
            for token in normalizedGroup {
                map[token, default: []].formUnion(normalizedGroup)
            }
        }
        return map
    }

    private(set) var notes: [NoteSearchResult] = []
    @ObservationIgnored private var allNotes: [IndexedNote] = []
    @ObservationIgnored private var documentFrequency: [String: Int] = [:]
    /// Whether the index has been populated at least once.
    @ObservationIgnored private(set) var isPopulated = false

    /// Rebuild from pre-read file contents (unified indexer path)
    func rebuild(from files: [UnifiedIndexer.FileContent], workspace: URL?) {
        allNotes = files.compactMap { file -> IndexedNote? in
            let ext = file.url.pathExtension.lowercased()
            guard Self.searchableExtensions.contains(ext) else { return nil }
            let title = file.url.deletingPathExtension().lastPathComponent
            let relativePath = Self.relativeDirectory(for: file.url, workspace: workspace)
            let values = try? file.url.resourceValues(forKeys: [.contentModificationDateKey])
            let modifiedAt = values?.contentModificationDate ?? Date.distantPast
            return Self.makeIndexedNote(
                url: file.url,
                title: title,
                relativePath: relativePath,
                content: file.content,
                modifiedAt: modifiedAt
            )
        }
        rebuildDocumentFrequency()
        notes = allNotes.map(\.result)
        isPopulated = true
    }

    func updateFile(_ url: URL, content: String) {
        guard let noteIndex = allNotes.firstIndex(where: { $0.result.url == url }) else { return }
        let previous = allNotes[noteIndex]
        let existing = allNotes[noteIndex].result
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        let modifiedAt = values?.contentModificationDate ?? Date()
        let updated = Self.makeIndexedNote(
            url: url,
            title: existing.title,
            relativePath: existing.relativePath,
            content: content,
            modifiedAt: modifiedAt
        )
        allNotes[noteIndex] = updated
        updateDocumentFrequency(previous: previous, updated: updated)
        notes = allNotes.map(\.result)
    }

    func addFile(_ url: URL, content: String, workspace: URL?) {
        let ext = url.pathExtension.lowercased()
        guard Self.searchableExtensions.contains(ext) else { return }
        // Don't add duplicates
        guard !allNotes.contains(where: { $0.result.url == url }) else {
            updateFile(url, content: content)
            return
        }
        let title = url.deletingPathExtension().lastPathComponent
        let relativePath = Self.relativeDirectory(
            for: url, workspace: workspace
        )
        let values = try? url.resourceValues(
            forKeys: [.contentModificationDateKey]
        )
        let modifiedAt = values?.contentModificationDate ?? Date()
        let indexed = Self.makeIndexedNote(
            url: url, title: title, relativePath: relativePath,
            content: content, modifiedAt: modifiedAt
        )
        allNotes.append(indexed)
        let tokens = uniqueTokens(for: indexed)
        for token in tokens {
            documentFrequency[token, default: 0] += 1
        }
        notes = allNotes.map(\.result)
    }

    func removeFile(_ url: URL) {
        guard let idx = allNotes.firstIndex(
            where: { $0.result.url == url }
        ) else { return }
        let removed = allNotes.remove(at: idx)
        let tokens = uniqueTokens(for: removed)
        for token in tokens {
            let count = documentFrequency[token] ?? 0
            if count <= 1 {
                documentFrequency.removeValue(forKey: token)
            } else {
                documentFrequency[token] = count - 1
            }
        }
        notes = allNotes.map(\.result)
    }

    /// Find notes whose raw content contains the given substring (case-insensitive).
    func notesContaining(_ substring: String) -> [(title: String, url: URL)] {
        let needle = substring.lowercased()
        return allNotes.compactMap { indexed in
            guard indexed.rawContentLowercased.contains(needle) else { return nil }
            return (title: indexed.result.title, url: indexed.result.url)
        }
    }

    func search(_ query: String) -> [NoteSearchResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty {
            return allNotes
                .sorted { $0.modifiedAt > $1.modifiedAt }
                .prefix(20)
                .map(\.result)
        }

        let parsedQuery = Self.parseLocalSearchQuery(trimmedQuery)
        let expandedTokens = Set(Self.expandQueryTokens(parsedQuery.queryTokens))

        let ranked: [(NoteSearchResult, Int)] = allNotes
            .compactMap { indexed -> (NoteSearchResult, Int)? in
                guard matchesFilters(indexed, query: parsedQuery) else { return nil }
                let rank = score(
                    indexed,
                    parsedQuery: parsedQuery,
                    queryTokens: expandedTokens
                )
                guard rank > 0 else { return nil }
                let preview = Self.preview(
                    from: indexed,
                    normalizedQuery: parsedQuery.normalizedQuery,
                    queryTokens: expandedTokens
                )
                let result = NoteSearchResult(
                    id: indexed.result.id,
                    title: indexed.result.title,
                    relativePath: indexed.result.relativePath,
                    url: indexed.result.url,
                    preview: preview,
                    score: rank
                )
                return (result, rank)
            }

        return ranked
            .sorted { first, second in
                if first.1 == second.1 {
                    return first.0.title.localizedCaseInsensitiveCompare(second.0.title) == .orderedAscending
                }
                return first.1 > second.1
            }
            .map { $0.0 }
    }

    func searchTitlesOnly(_ query: String) -> [NoteSearchResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty {
            return search("")
        }

        let parsedQuery = Self.parseLocalSearchQuery(trimmedQuery)
        let expandedTokens = Set(Self.expandQueryTokens(parsedQuery.queryTokens))

        let ranked: [(NoteSearchResult, Int)] = allNotes
            .compactMap { indexed -> (NoteSearchResult, Int)? in
                guard matchesFilters(indexed, query: parsedQuery) else { return nil }
                guard matchesTitleSearch(indexed, query: parsedQuery, queryTokens: expandedTokens) else {
                    return nil
                }
                let rank = score(
                    indexed,
                    parsedQuery: parsedQuery,
                    queryTokens: expandedTokens
                )
                guard rank > 0 else { return nil }
                let preview = Self.preview(
                    from: indexed,
                    normalizedQuery: parsedQuery.normalizedQuery,
                    queryTokens: expandedTokens
                )
                let result = NoteSearchResult(
                    id: indexed.result.id,
                    title: indexed.result.title,
                    relativePath: indexed.result.relativePath,
                    url: indexed.result.url,
                    preview: preview,
                    score: rank
                )
                return (result, rank)
            }

        return ranked
            .sorted { first, second in
                if first.1 == second.1 {
                    return first.0.title.localizedCaseInsensitiveCompare(second.0.title) == .orderedAscending
                }
                return first.1 > second.1
            }
            .map { $0.0 }
    }

    func findExact(_ title: String) -> NoteSearchResult? {
        allNotes.map(\.result).first { $0.title.lowercased() == title.lowercased() }
    }

    private func rebuildDocumentFrequency() {
        var frequency: [String: Int] = [:]
        for note in allNotes {
            let uniqueTokens = uniqueTokens(for: note)
            for token in uniqueTokens {
                frequency[token, default: 0] += 1
            }
        }
        documentFrequency = frequency
    }

    private func updateDocumentFrequency(previous: IndexedNote, updated: IndexedNote) {
        let previousTokens = uniqueTokens(for: previous)
        let updatedTokens = uniqueTokens(for: updated)
        let removedTokens = previousTokens.subtracting(updatedTokens)
        let addedTokens = updatedTokens.subtracting(previousTokens)

        for token in removedTokens {
            let currentCount = documentFrequency[token] ?? 0
            if currentCount <= 1 {
                documentFrequency.removeValue(forKey: token)
            } else {
                documentFrequency[token] = currentCount - 1
            }
        }

        for token in addedTokens {
            documentFrequency[token, default: 0] += 1
        }
    }

    private func uniqueTokens(for note: IndexedNote) -> Set<String> {
        Set(note.titleTokens).union(note.contentTokenCounts.keys)
    }

    private func score(
        _ indexed: IndexedNote,
        parsedQuery: LocalSearchQuery,
        queryTokens: Set<String>
    ) -> Int {
        let query = parsedQuery.displayQuery
        let normalizedQuery = parsedQuery.normalizedQuery
        let normalizedPhrases = parsedQuery.normalizedPhrases
        let hasSearchTerms = parsedQuery.hasSearchTerms
        var total = 0
        var titleSignals = 0
        var contentSignals = 0
        let lowerQuery = query.lowercased()

        // Title matches (strong signals)
        if !normalizedQuery.isEmpty && indexed.normalizedTitle == normalizedQuery {
            total += Self.ScoreWeights.exactTitleMatch
            titleSignals += 1
        } else if !normalizedQuery.isEmpty && indexed.normalizedTitle.contains(normalizedQuery) {
            total += Self.ScoreWeights.partialTitleMatch
            titleSignals += 1
        }

        if !lowerQuery.isEmpty, let titleFuzzy = indexed.result.title.fuzzyScore(lowerQuery) {
            total += titleFuzzy * Self.ScoreWeights.titleFuzzyMultiplier
            titleSignals += 1
        }

        // Content matches (weaker signals)
        if !normalizedQuery.isEmpty && indexed.normalizedContent.contains(normalizedQuery) {
            total += Self.ScoreWeights.exactContentMatch
            contentSignals += 1
        }

        for phrase in normalizedPhrases where !phrase.isEmpty {
            if indexed.normalizedTitle.contains(phrase) {
                total += Self.ScoreWeights.titlePhraseMatch
                titleSignals += 1
            }
            if indexed.normalizedContent.contains(phrase) {
                total += Self.ScoreWeights.contentPhraseMatch
                contentSignals += 1
            }
        }

        for token in queryTokens {
            let inverseDocumentWeight = inverseDocumentFrequency(for: token)
            let tokenWeight = max(inverseDocumentWeight, 1)
            if indexed.titleTokens.contains(token) {
                total += Self.ScoreWeights.titleTokenMatch * tokenWeight
                titleSignals += 1
            } else if indexed.titleTokens.contains(where: { $0.hasPrefix(token) || token.hasPrefix($0) }) {
                total += Self.ScoreWeights.titlePrefixTokenMatch * tokenWeight
                titleSignals += 1
            }

            let frequency = indexed.contentTokenCounts[token] ?? 0
            if frequency > 0 {
                total += min(frequency, Self.ScoreWeights.maxContentFrequencyCount)
                    * Self.ScoreWeights.contentTokenMatch
                    * tokenWeight
                contentSignals += 1
            }
        }

        let relevanceSignals = titleSignals + contentSignals

        let matchedTokenCount = queryTokens.filter { token in
            indexed.titleTokens.contains(token) || indexed.contentTokenCounts[token] != nil
        }.count

        if matchedTokenCount == queryTokens.count && !queryTokens.isEmpty {
            total += Self.ScoreWeights.allTokensMatchBonus
        } else if matchedTokenCount > 0 {
            total += matchedTokenCount * Self.ScoreWeights.partialTokenMatchBonus
        }

        if !hasSearchTerms {
            total += Self.ScoreWeights.filterOnlyQueryBonus
        }

        if hasSearchTerms && relevanceSignals == 0 {
            return 0
        }

        if titleSignals > 0 {
            total += recencyBoost(for: indexed.modifiedAt)
        }

        return total
    }

    private func matchesTitleSearch(
        _ indexed: IndexedNote,
        query: LocalSearchQuery,
        queryTokens: Set<String>
    ) -> Bool {
        if !query.requiredTitleTerms.isEmpty {
            return true
        }

        if !query.hasSearchTerms {
            return true
        }

        if !query.normalizedQuery.isEmpty {
            if indexed.normalizedTitle == query.normalizedQuery {
                return true
            }
            if indexed.normalizedTitle.contains(query.normalizedQuery) {
                return true
            }
        }

        for phrase in query.normalizedPhrases where !phrase.isEmpty {
            if indexed.normalizedTitle.contains(phrase) {
                return true
            }
        }

        for token in queryTokens {
            if indexed.titleTokens.contains(token) {
                return true
            }
            if indexed.titleTokens.contains(where: { $0.hasPrefix(token) || token.hasPrefix($0) }) {
                return true
            }
        }

        if !query.displayQuery.isEmpty, indexed.result.title.fuzzyScore(query.displayQuery) != nil {
            return true
        }

        return false
    }

    private func matchesFilters(_ indexed: IndexedNote, query: LocalSearchQuery) -> Bool {
        if !query.requiredTags.isEmpty {
            for filterTag in query.requiredTags where !containsTag(filterTag, in: indexed.tags) {
                return false
            }
        }
        if !query.excludedTags.isEmpty {
            for excludedTag in query.excludedTags where containsTag(excludedTag, in: indexed.tags) {
                return false
            }
        }

        if !query.requiredPeople.isEmpty {
            for filterPerson in query.requiredPeople where !containsPerson(filterPerson, in: indexed.mentions) {
                return false
            }
        }
        if !query.excludedPeople.isEmpty {
            for excludedPerson in query.excludedPeople where containsPerson(excludedPerson, in: indexed.mentions) {
                return false
            }
        }

        if !query.requiredPaths.isEmpty {
            let path = indexed.result.relativePath.lowercased()
            for requiredPath in query.requiredPaths where !path.contains(requiredPath) {
                return false
            }
        }
        if !query.excludedPaths.isEmpty {
            let path = indexed.result.relativePath.lowercased()
            for excludedPath in query.excludedPaths where path.contains(excludedPath) {
                return false
            }
        }

        for requiredTitle in query.requiredTitleTerms where !indexed.normalizedTitle.contains(requiredTitle) {
            return false
        }
        for excludedTitle in query.excludedTitleTerms where indexed.normalizedTitle.contains(excludedTitle) {
            return false
        }

        for requiredContent in query.requiredContentTerms where !indexed.normalizedContent.contains(requiredContent) {
            return false
        }
        for excludedContent in query.excludedContentTerms where indexed.normalizedContent.contains(excludedContent) {
            return false
        }

        if !query.normalizedPhrases.isEmpty {
            for phrase in query.normalizedPhrases {
                let inTitle = indexed.normalizedTitle.contains(phrase)
                let inContent = indexed.normalizedContent.contains(phrase)
                if !inTitle && !inContent {
                    return false
                }
            }
        }

        for excludedPhrase in query.excludedPhrases {
            let inTitle = indexed.normalizedTitle.contains(excludedPhrase)
            let inContent = indexed.normalizedContent.contains(excludedPhrase)
            if inTitle || inContent {
                return false
            }
        }

        for excludedToken in query.excludedQueryTokens {
            if indexed.titleTokens.contains(excludedToken) || indexed.contentTokenCounts[excludedToken] != nil {
                return false
            }
        }

        return true
    }

    private func containsTag(_ filterTag: String, in tags: Set<String>) -> Bool {
        tags.contains(filterTag) || tags.contains(where: { $0.hasPrefix(filterTag) })
    }

    private func containsPerson(_ filterPerson: String, in people: Set<String>) -> Bool {
        people.contains(filterPerson) || people.contains(where: { $0.hasPrefix(filterPerson) })
    }

    private func recencyBoost(for modifiedAt: Date) -> Int {
        let daysAgo = Date().timeIntervalSince(modifiedAt) / 86_400
        switch daysAgo {
        case ..<1:
            return Self.RecencyWeights.lastDay
        case ..<7:
            return Self.RecencyWeights.lastWeek
        case ..<30:
            return Self.RecencyWeights.lastMonth
        default:
            return 0
        }
    }

    private func inverseDocumentFrequency(for token: String) -> Int {
        let documents = max(allNotes.count, 1)
        let occurrences = max(documentFrequency[token] ?? 0, 1)
        let ratio = Double(documents) / Double(occurrences)
        switch ratio {
        case ..<1.5:
            return 1
        case ..<3.0:
            return 2
        case ..<6.0:
            return 3
        default:
            return 4
        }
    }

    private static func makeIndexedNote(
        url: URL,
        title: String,
        relativePath: String,
        content: String,
        modifiedAt: Date
    ) -> IndexedNote {
        let titleTokens = tokens(from: title)
        let contentTokens = tokens(from: content)
        let tags = extractTags(from: content)
        let mentions = extractMentions(from: content)

        var contentTokenCounts: [String: Int] = [:]
        for token in contentTokens {
            contentTokenCounts[token, default: 0] += 1
        }

        let previewLines = cleanedPreviewLines(from: content)
        let defaultPreview = previewLines.first ?? "No preview available."

        let result = NoteSearchResult(
            id: url,
            title: title,
            relativePath: relativePath,
            url: url,
            preview: defaultPreview
        )
        return IndexedNote(
            result: result,
            normalizedTitle: normalizeText(title),
            normalizedContent: normalizeText(content),
            rawContentLowercased: content.lowercased(),
            titleTokens: titleTokens,
            contentTokenCounts: contentTokenCounts,
            previewLines: previewLines,
            tags: tags,
            mentions: mentions,
            modifiedAt: modifiedAt
        )
    }

    private static func preview(
        from indexed: IndexedNote,
        normalizedQuery: String,
        queryTokens: Set<String>
    ) -> String {
        let lines = indexed.previewLines
        guard !lines.isEmpty else { return "No preview available." }

        var bestScore = Int.min
        var bestLine = lines[0]

        for line in lines {
            let normalizedLine = normalizeText(line)
            var lineScore = 0

            if !normalizedQuery.isEmpty && normalizedLine.contains(normalizedQuery) {
                lineScore += 1_200
            }

            for token in queryTokens where normalizedLine.contains(token) {
                lineScore += 150
            }

            if lineScore > bestScore {
                bestScore = lineScore
                bestLine = line
            }
        }

        return truncatedPreview(bestLine, limit: 200)
    }

    private static func cleanedPreviewLines(from content: String) -> [String] {
        content
            .components(separatedBy: .newlines)
            .map(cleanPreviewLine)
            .filter { !$0.isEmpty }
    }

    private static func cleanPreviewLine(_ line: String) -> String {
        let withoutListSyntax = line.replacingOccurrences(
            of: #"^\s{0,3}(#{1,6}|[-*+]|>\s?)\s*"#,
            with: "",
            options: .regularExpression
        )
        let withoutInlineCode = withoutListSyntax.replacingOccurrences(of: "`", with: "")
        let collapsed = withoutInlineCode.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func truncatedPreview(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        let cutoffIndex = text.index(text.startIndex, offsetBy: limit)
        return "\(text[..<cutoffIndex])..."
    }

    private static func relativeDirectory(for fileURL: URL, workspace: URL?) -> String {
        guard let workspace else {
            return fileURL.deletingLastPathComponent().lastPathComponent
        }

        let directoryURL = fileURL.deletingLastPathComponent().standardizedFileURL
        let workspaceURL = workspace.standardizedFileURL
        let workspacePrefix = workspaceURL.path + "/"
        let directoryPath = directoryURL.path

        if directoryPath == workspaceURL.path {
            return "root"
        }
        if directoryPath.hasPrefix(workspacePrefix) {
            return String(directoryPath.dropFirst(workspacePrefix.count))
        }
        return directoryURL.lastPathComponent
    }

    private static func normalizeTag(_ rawTag: String) -> String? {
        let cleaned = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .lowercased()
        guard cleaned.count >= 2 else { return nil }
        let allowed = cleaned.replacingOccurrences(
            of: "[^a-z0-9_-]",
            with: "",
            options: .regularExpression
        )
        guard !allowed.isEmpty else { return nil }
        return allowed
    }

    private static func normalizePerson(_ rawPerson: String) -> String? {
        let cleaned = rawPerson.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
            .lowercased()
        guard cleaned.count >= 2 else { return nil }
        let collapsed = cleaned.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        guard !collapsed.isEmpty else { return nil }
        return collapsed
    }

    private static func extractTags(from content: String) -> Set<String> {
        guard let regex = tagPattern else { return [] }
        let searchRange = NSRange(content.startIndex..<content.endIndex, in: content)
        let matches = regex.matches(in: content, range: searchRange)
        var tags: Set<String> = []
        for match in matches {
            guard let range = Range(match.range(at: 1), in: content) else { continue }
            if let tag = normalizeTag(String(content[range])) {
                tags.insert(tag)
            }
        }
        return tags
    }

    private static func extractMentions(from content: String) -> Set<String> {
        guard let regex = mentionPattern else { return [] }
        let searchRange = NSRange(content.startIndex..<content.endIndex, in: content)
        let matches = regex.matches(in: content, range: searchRange)
        var mentions: Set<String> = []
        for match in matches {
            guard let range = Range(match.range(at: 1), in: content) else { continue }
            if let mention = normalizePerson(String(content[range])) {
                mentions.insert(mention)
            }
        }
        return mentions
    }

    private static func tokens(from text: String) -> [String] {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .compactMap(normalizeToken(_:))
    }

    private static func normalizeText(_ text: String) -> String {
        tokens(from: text).joined(separator: " ")
    }

    private static func normalizeToken(_ rawToken: String) -> String? {
        let trimmed = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return nil }
        return stem(trimmed)
    }

    private static func stem(_ token: String) -> String {
        var stemmed = token
        if stemmed.hasSuffix("ies") && stemmed.count > 4 {
            stemmed.removeLast(3)
            stemmed.append("y")
            return stemmed
        }
        if stemmed.hasSuffix("ing") && stemmed.count > 5 {
            stemmed.removeLast(3)
            return stemmed
        }
        if stemmed.hasSuffix("ed") && stemmed.count > 4 {
            stemmed.removeLast(2)
            return stemmed
        }
        if stemmed.hasSuffix("ly") && stemmed.count > 4 {
            stemmed.removeLast(2)
            return stemmed
        }
        if stemmed.hasSuffix("es") && stemmed.count > 4 {
            stemmed.removeLast(2)
            return stemmed
        }
        if stemmed.hasSuffix("s") && stemmed.count > 3 {
            stemmed.removeLast(1)
            return stemmed
        }
        return stemmed
    }

    private static func expandQueryTokens(_ queryTokens: [String]) -> [String] {
        var expanded: Set<String> = []
        for token in queryTokens {
            expanded.insert(token)
            if let semanticTokens = semanticMap[token] {
                expanded.formUnion(semanticTokens)
            }
        }
        return Array(expanded)
    }
}
