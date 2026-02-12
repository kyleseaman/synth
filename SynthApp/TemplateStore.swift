import Foundation
import Observation

struct SavedTemplate: Codable, Equatable, Identifiable {
    let identifier: UUID
    let name: String
    let content: String
    let shortcutSlot: Int?
    let category: String?
    let description: String?
    let usageCount: Int
    let createdAt: Date
    let updatedAt: Date

    var id: UUID { identifier }

    /// Legacy initializer for backward compatibility with existing data
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        identifier = try container.decode(UUID.self, forKey: .identifier)
        name = try container.decode(String.self, forKey: .name)
        content = try container.decode(String.self, forKey: .content)
        shortcutSlot = try container.decodeIfPresent(Int.self, forKey: .shortcutSlot)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        usageCount = try container.decodeIfPresent(Int.self, forKey: .usageCount) ?? 0
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    init(
        identifier: UUID,
        name: String,
        content: String,
        shortcutSlot: Int?,
        category: String?,
        description: String?,
        usageCount: Int,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.identifier = identifier
        self.name = name
        self.content = content
        self.shortcutSlot = shortcutSlot
        self.category = category
        self.description = description
        self.usageCount = usageCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Template Variable Expansion

/// Result of expanding a template, including the expanded content and cursor position
struct ExpandedTemplate {
    let content: String
    let cursorOffset: Int?
}

/// Handles template variable expansion with support for date/time formatting
enum TemplateExpander {
    /// Supported variable patterns:
    /// - `{{date}}` - Current date in default format (MMMM d, yyyy)
    /// - `{{date:FORMAT}}` - Current date with custom format (e.g., {{date:yyyy-MM-dd}})
    /// - `{{time}}` - Current time in default format (h:mm a)
    /// - `{{time:FORMAT}}` - Current time with custom format (e.g., {{time:HH:mm:ss}})
    /// - `{{datetime}}` - Current date and time
    /// - `{{datetime:FORMAT}}` - Custom date/time format
    /// - `{{year}}` - Current year (yyyy)
    /// - `{{month}}` - Current month name (MMMM)
    /// - `{{day}}` - Day of month (d)
    /// - `{{weekday}}` - Day of week (EEEE)
    /// - `{{title}}` - Document title (passed in context)
    /// - `{{filename}}` - Document filename without extension
    /// - `{{cursor}}` - Position cursor here after expansion (removed from output)
    /// - `{{uuid}}` - Generate a unique identifier
    /// - `{{random:N}}` - Random N-digit number

    static func expand(
        _ template: String,
        title: String? = nil,
        filename: String? = nil,
        date: Date = Date()
    ) -> ExpandedTemplate {
        var result = template
        var cursorOffset: Int?

        // Process {{cursor}} placeholder first to track position
        if let cursorRange = result.range(of: "{{cursor}}") {
            cursorOffset = result.distance(from: result.startIndex, to: cursorRange.lowerBound)
            result.replaceSubrange(cursorRange, with: "")
        }

        // Date/time variables with optional custom format
        result = expandDateVariable(result, pattern: "date", defaultFormat: "MMMM d, yyyy", date: date)
        result = expandDateVariable(result, pattern: "time", defaultFormat: "h:mm a", date: date)
        result = expandDateVariable(result, pattern: "datetime", defaultFormat: "MMMM d, yyyy 'at' h:mm a", date: date)

        // Simple date components
        result = expandSimpleDateComponent(result, variable: "year", format: "yyyy", date: date)
        result = expandSimpleDateComponent(result, variable: "month", format: "MMMM", date: date)
        result = expandSimpleDateComponent(result, variable: "day", format: "d", date: date)
        result = expandSimpleDateComponent(result, variable: "weekday", format: "EEEE", date: date)

        // Context variables
        if let title = title {
            result = result.replacingOccurrences(of: "{{title}}", with: title)
        }
        if let filename = filename {
            result = result.replacingOccurrences(of: "{{filename}}", with: filename)
        }

        // UUID generation
        while result.contains("{{uuid}}") {
            result = result.replacingOccurrences(
                of: "{{uuid}}",
                with: UUID().uuidString,
                options: [],
                range: result.range(of: "{{uuid}}")
            )
        }

        // Random number generation {{random:N}}
        result = expandRandomNumbers(result)

        return ExpandedTemplate(content: result, cursorOffset: cursorOffset)
    }

    private static func expandDateVariable(
        _ input: String,
        pattern: String,
        defaultFormat: String,
        date: Date
    ) -> String {
        var result = input

        // Handle format with custom pattern: {{pattern:FORMAT}}
        let customPattern = "\\{\\{\(pattern):([^}]+)\\}\\}"
        if let regex = try? NSRegularExpression(pattern: customPattern, options: []) {
            let range = NSRange(result.startIndex..., in: result)
            let matches = regex.matches(in: result, options: [], range: range)

            // Process matches in reverse order to maintain string indices
            for match in matches.reversed() {
                if let formatRange = Range(match.range(at: 1), in: result),
                   let fullRange = Range(match.range, in: result) {
                    let customFormat = String(result[formatRange])
                    let formatter = DateFormatter()
                    formatter.dateFormat = customFormat
                    formatter.locale = Locale(identifier: "en_US_POSIX")
                    let replacement = formatter.string(from: date)
                    result.replaceSubrange(fullRange, with: replacement)
                }
            }
        }

        // Handle simple pattern: {{pattern}}
        let simpleReplacement = "{{\(pattern)}}"
        if result.contains(simpleReplacement) {
            let formatter = DateFormatter()
            formatter.dateFormat = defaultFormat
            formatter.locale = Locale(identifier: "en_US_POSIX")
            result = result.replacingOccurrences(of: simpleReplacement, with: formatter.string(from: date))
        }

        return result
    }

    private static func expandSimpleDateComponent(
        _ input: String,
        variable: String,
        format: String,
        date: Date
    ) -> String {
        let placeholder = "{{\(variable)}}"
        guard input.contains(placeholder) else { return input }

        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return input.replacingOccurrences(of: placeholder, with: formatter.string(from: date))
    }

    private static func expandRandomNumbers(_ input: String) -> String {
        var result = input
        let pattern = "\\{\\{random:(\\d+)\\}\\}"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return result
        }

        while true {
            let range = NSRange(result.startIndex..., in: result)
            guard let match = regex.firstMatch(in: result, options: [], range: range),
                  let digitsRange = Range(match.range(at: 1), in: result),
                  let fullRange = Range(match.range, in: result),
                  let digitCount = Int(result[digitsRange]),
                  digitCount > 0, digitCount <= 20 else {
                break
            }

            var randomNumber = ""
            for _ in 0..<digitCount {
                randomNumber += String(Int.random(in: 0...9))
            }
            result.replaceSubrange(fullRange, with: randomNumber)
        }

        return result
    }

    /// Returns a list of all supported variables with descriptions for UI display
    static var supportedVariables: [(variable: String, description: String)] {
        [
            ("{{date}}", "Current date (e.g., January 15, 2026)"),
            ("{{date:yyyy-MM-dd}}", "Date with custom format"),
            ("{{time}}", "Current time (e.g., 2:30 PM)"),
            ("{{time:HH:mm}}", "Time with custom format"),
            ("{{datetime}}", "Date and time combined"),
            ("{{year}}", "Current year"),
            ("{{month}}", "Current month name"),
            ("{{day}}", "Day of month"),
            ("{{weekday}}", "Day of week"),
            ("{{title}}", "Document title"),
            ("{{filename}}", "Document filename"),
            ("{{cursor}}", "Cursor position after insertion"),
            ("{{uuid}}", "Unique identifier"),
            ("{{random:4}}", "Random N-digit number")
        ]
    }
}

@Observable final class TemplateStore {
    private(set) var templates: [SavedTemplate] = []

    @ObservationIgnored private let storage: UserDefaults
    @ObservationIgnored private let storageKey: String
    @ObservationIgnored private let contentMatchScore = 50
    @ObservationIgnored private let categoryMatchScore = 40
    @ObservationIgnored private let descriptionMatchScore = 30

    /// All unique categories currently in use
    var categories: [String] {
        Array(Set(templates.compactMap { $0.category })).sorted()
    }

    init(storage: UserDefaults = .standard, storageKey: String = "synth.savedTemplates") {
        self.storage = storage
        self.storageKey = storageKey
        load()
    }

    // MARK: - CRUD Operations

    func addTemplate(
        name: String,
        content: String,
        shortcutSlot: Int?,
        category: String? = nil,
        description: String? = nil
    ) -> SavedTemplate? {
        guard let normalizedName = Self.normalizeName(name),
              let normalizedContent = Self.normalizeContent(content) else { return nil }
        let normalizedSlot = Self.normalizeShortcut(shortcutSlot)
        let normalizedCategory = Self.normalizeOptionalString(category)
        let normalizedDescription = Self.normalizeOptionalString(description)
        let nowDate = Date()

        if let existingIndex = templates.firstIndex(
            where: { $0.name.lowercased() == normalizedName.lowercased() }
        ) {
            let existing = templates[existingIndex]
            let updated = SavedTemplate(
                identifier: existing.identifier,
                name: normalizedName,
                content: normalizedContent,
                shortcutSlot: normalizedSlot,
                category: normalizedCategory,
                description: normalizedDescription,
                usageCount: existing.usageCount,
                createdAt: existing.createdAt,
                updatedAt: nowDate
            )
            templates[existingIndex] = updated
            finalizeTemplateMutation(identifier: updated.identifier, slot: normalizedSlot)
            return updated
        }

        let template = SavedTemplate(
            identifier: UUID(),
            name: normalizedName,
            content: normalizedContent,
            shortcutSlot: normalizedSlot,
            category: normalizedCategory,
            description: normalizedDescription,
            usageCount: 0,
            createdAt: nowDate,
            updatedAt: nowDate
        )
        templates.append(template)
        finalizeTemplateMutation(identifier: template.identifier, slot: normalizedSlot)
        return template
    }

    @discardableResult
    func updateTemplate(
        identifier: UUID,
        name: String,
        content: String,
        shortcutSlot: Int?,
        category: String? = nil,
        description: String? = nil
    ) -> Bool {
        guard let templateIndex = templates.firstIndex(where: { $0.identifier == identifier }),
              let normalizedName = Self.normalizeName(name),
              let normalizedContent = Self.normalizeContent(content) else { return false }

        let normalizedSlot = Self.normalizeShortcut(shortcutSlot)
        let normalizedCategory = Self.normalizeOptionalString(category)
        let normalizedDescription = Self.normalizeOptionalString(description)
        let existing = templates[templateIndex]
        templates[templateIndex] = SavedTemplate(
            identifier: existing.identifier,
            name: normalizedName,
            content: normalizedContent,
            shortcutSlot: normalizedSlot,
            category: normalizedCategory,
            description: normalizedDescription,
            usageCount: existing.usageCount,
            createdAt: existing.createdAt,
            updatedAt: Date()
        )
        finalizeTemplateMutation(identifier: identifier, slot: normalizedSlot)
        return true
    }

    func removeTemplate(identifier: UUID) {
        templates.removeAll { $0.identifier == identifier }
        save()
    }

    /// Duplicates a template with a new name
    func duplicateTemplate(identifier: UUID, newName: String? = nil) -> SavedTemplate? {
        guard let source = templates.first(where: { $0.identifier == identifier }) else {
            return nil
        }

        let duplicateName = newName ?? "\(source.name) (Copy)"
        return addTemplate(
            name: duplicateName,
            content: source.content,
            shortcutSlot: nil,  // Don't copy shortcut to avoid conflicts
            category: source.category,
            description: source.description
        )
    }

    /// Records that a template was used, incrementing its usage count
    func recordUsage(identifier: UUID) {
        guard let templateIndex = templates.firstIndex(where: { $0.identifier == identifier }) else {
            return
        }
        let existing = templates[templateIndex]
        templates[templateIndex] = SavedTemplate(
            identifier: existing.identifier,
            name: existing.name,
            content: existing.content,
            shortcutSlot: existing.shortcutSlot,
            category: existing.category,
            description: existing.description,
            usageCount: existing.usageCount + 1,
            createdAt: existing.createdAt,
            updatedAt: existing.updatedAt
        )
        save()
    }

    // MARK: - Lookup Methods

    func template(named name: String) -> SavedTemplate? {
        templates.first { $0.name.lowercased() == name.lowercased() }
    }

    func templateForShortcut(_ slotNumber: Int) -> SavedTemplate? {
        templates.first { $0.shortcutSlot == slotNumber }
    }

    func templatesInCategory(_ category: String?) -> [SavedTemplate] {
        if let category = category {
            return templates.filter { $0.category?.lowercased() == category.lowercased() }
        } else {
            return templates.filter { $0.category == nil }
        }
    }

    // MARK: - Search

    func search(_ query: String) -> [SavedTemplate] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty {
            return templates
        }

        return templates
            .compactMap { template -> (SavedTemplate, Int)? in
                // Name match (highest priority with fuzzy matching)
                if let score = template.name.fuzzyScore(trimmedQuery) {
                    return (template, score)
                }
                // Category match
                if let category = template.category,
                   category.lowercased().contains(trimmedQuery.lowercased()) {
                    return (template, categoryMatchScore)
                }
                // Description match
                if let description = template.description,
                   description.lowercased().contains(trimmedQuery.lowercased()) {
                    return (template, descriptionMatchScore)
                }
                // Content match (lowest priority)
                if template.content.lowercased().contains(trimmedQuery.lowercased()) {
                    return (template, contentMatchScore)
                }
                return nil
            }
            .sorted { firstItem, secondItem in
                if firstItem.1 == secondItem.1 {
                    // Secondary sort by usage count (more used = higher)
                    if firstItem.0.usageCount != secondItem.0.usageCount {
                        return firstItem.0.usageCount > secondItem.0.usageCount
                    }
                    return firstItem.0.updatedAt > secondItem.0.updatedAt
                }
                return firstItem.1 > secondItem.1
            }
            .map { $0.0 }
    }

    // MARK: - Template Expansion

    /// Expands template variables and returns the expanded content with optional cursor position
    func expandTemplate(
        _ template: SavedTemplate,
        title: String? = nil,
        filename: String? = nil
    ) -> ExpandedTemplate {
        recordUsage(identifier: template.identifier)
        return TemplateExpander.expand(template.content, title: title, filename: filename)
    }

    /// Expands template content without tracking usage (for previews)
    static func previewExpansion(_ content: String) -> String {
        TemplateExpander.expand(content).content
    }

    // MARK: - Private Helpers

    private func finalizeTemplateMutation(identifier: UUID, slot: Int?) {
        enforceUniqueShortcut(slot: slot, for: identifier)
        sortTemplates()
        save()
    }

    private func enforceUniqueShortcut(slot: Int?, for identifier: UUID) {
        guard let slot else { return }
        templates = templates.map { template in
            guard template.identifier != identifier, template.shortcutSlot == slot else { return template }
            return SavedTemplate(
                identifier: template.identifier,
                name: template.name,
                content: template.content,
                shortcutSlot: nil,
                category: template.category,
                description: template.description,
                usageCount: template.usageCount,
                createdAt: template.createdAt,
                updatedAt: template.updatedAt
            )
        }
    }

    private func sortTemplates() {
        templates.sort { firstTemplate, secondTemplate in
            // Primary sort: by category (uncategorized last)
            let firstCategory = firstTemplate.category ?? "zzz_uncategorized"
            let secondCategory = secondTemplate.category ?? "zzz_uncategorized"
            if firstCategory != secondCategory {
                return firstCategory.localizedCaseInsensitiveCompare(secondCategory) == .orderedAscending
            }
            // Secondary sort: by usage count (higher first)
            if firstTemplate.usageCount != secondTemplate.usageCount {
                return firstTemplate.usageCount > secondTemplate.usageCount
            }
            // Tertiary sort: by update date (recent first)
            if firstTemplate.updatedAt != secondTemplate.updatedAt {
                return firstTemplate.updatedAt > secondTemplate.updatedAt
            }
            // Fallback: alphabetical by name
            return firstTemplate.name.localizedCaseInsensitiveCompare(
                secondTemplate.name
            ) == .orderedAscending
        }
    }

    private func load() {
        guard let data = storage.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([SavedTemplate].self, from: data) else { return }
        templates = decoded
        sortTemplates()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(templates) else { return }
        storage.set(data, forKey: storageKey)
    }

    private static func normalizeName(_ rawName: String) -> String? {
        let trimmedName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? nil : trimmedName
    }

    private static func normalizeContent(_ rawContent: String) -> String? {
        let hasAnyContent = !rawContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasAnyContent ? rawContent : nil
    }

    private static func normalizeShortcut(_ slot: Int?) -> Int? {
        guard let slot else { return nil }
        return (1...9).contains(slot) ? slot : nil
    }

    private static func normalizeOptionalString(_ value: String?) -> String? {
        guard let value = value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
