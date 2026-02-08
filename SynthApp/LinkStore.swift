import Foundation
import Combine

struct SavedLink: Codable, Equatable {
    let identifier: UUID
    let urlString: String
    let createdAt: Date
}

final class LinkStore: ObservableObject {
    @Published private(set) var links: [SavedLink] = []

    private let storage: UserDefaults
    private let storageKey: String

    init(storage: UserDefaults = .standard, storageKey: String = "synth.savedLinks") {
        self.storage = storage
        self.storageKey = storageKey
        load()
    }

    func addLink(_ rawText: String) -> SavedLink? {
        guard let normalized = Self.normalize(rawText) else { return nil }

        if let existingIndex = links.firstIndex(where: { $0.urlString == normalized }) {
            let existing = links.remove(at: existingIndex)
            let refreshed = SavedLink(
                identifier: existing.identifier,
                urlString: existing.urlString,
                createdAt: Date()
            )
            links.insert(refreshed, at: 0)
            save()
            return refreshed
        }

        let link = SavedLink(identifier: UUID(), urlString: normalized, createdAt: Date())
        links.insert(link, at: 0)
        save()
        return link
    }

    func removeLink(identifier: UUID) {
        links.removeAll { $0.identifier == identifier }
        save()
    }

    static func normalize(_ rawText: String) -> String? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let direct = URL(string: trimmed),
           let scheme = direct.scheme,
           !scheme.isEmpty,
           direct.host != nil {
            return direct.absoluteString
        }

        if let inferred = URL(string: "https://\(trimmed)"), inferred.host != nil {
            return inferred.absoluteString
        }

        return nil
    }

    private func load() {
        guard let data = storage.data(forKey: storageKey) else { return }
        guard let decoded = try? JSONDecoder().decode([SavedLink].self, from: data) else { return }
        links = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(links) else { return }
        storage.set(data, forKey: storageKey)
    }
}

struct SavedTemplate: Codable, Equatable, Identifiable {
    let identifier: UUID
    let name: String
    let content: String
    let shortcutSlot: Int?
    let createdAt: Date
    let updatedAt: Date

    var id: UUID { identifier }
}

final class TemplateStore: ObservableObject {
    @Published private(set) var templates: [SavedTemplate] = []

    private let storage: UserDefaults
    private let storageKey: String

    init(storage: UserDefaults = .standard, storageKey: String = "synth.savedTemplates") {
        self.storage = storage
        self.storageKey = storageKey
        load()
    }

    func addTemplate(name: String, content: String, shortcutSlot: Int?) -> SavedTemplate? {
        guard let normalizedName = Self.normalizeName(name),
              let normalizedContent = Self.normalizeContent(content) else { return nil }
        let normalizedSlot = Self.normalizeShortcut(shortcutSlot)
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
                createdAt: existing.createdAt,
                updatedAt: nowDate
            )
            templates[existingIndex] = updated
            enforceUniqueShortcut(slot: normalizedSlot, for: updated.identifier)
            sortTemplates()
            save()
            return updated
        }

        let template = SavedTemplate(
            identifier: UUID(),
            name: normalizedName,
            content: normalizedContent,
            shortcutSlot: normalizedSlot,
            createdAt: nowDate,
            updatedAt: nowDate
        )
        templates.append(template)
        enforceUniqueShortcut(slot: normalizedSlot, for: template.identifier)
        sortTemplates()
        save()
        return template
    }

    @discardableResult
    func updateTemplate(
        identifier: UUID,
        name: String,
        content: String,
        shortcutSlot: Int?
    ) -> Bool {
        guard let templateIndex = templates.firstIndex(where: { $0.identifier == identifier }),
              let normalizedName = Self.normalizeName(name),
              let normalizedContent = Self.normalizeContent(content) else { return false }

        let normalizedSlot = Self.normalizeShortcut(shortcutSlot)
        let existing = templates[templateIndex]
        let updated = SavedTemplate(
            identifier: existing.identifier,
            name: normalizedName,
            content: normalizedContent,
            shortcutSlot: normalizedSlot,
            createdAt: existing.createdAt,
            updatedAt: Date()
        )
        templates[templateIndex] = updated
        enforceUniqueShortcut(slot: normalizedSlot, for: identifier)
        sortTemplates()
        save()
        return true
    }

    func removeTemplate(identifier: UUID) {
        templates.removeAll { $0.identifier == identifier }
        save()
    }

    func template(named name: String) -> SavedTemplate? {
        templates.first { $0.name.lowercased() == name.lowercased() }
    }

    func templateForShortcut(_ slotNumber: Int) -> SavedTemplate? {
        templates.first { $0.shortcutSlot == slotNumber }
    }

    func search(_ query: String) -> [SavedTemplate] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty {
            return templates
        }
        return templates
            .compactMap { template -> (SavedTemplate, Int)? in
                if let score = template.name.fuzzyScore(trimmedQuery) {
                    return (template, score)
                }
                if template.content.lowercased().contains(trimmedQuery.lowercased()) {
                    return (template, 50)
                }
                return nil
            }
            .sorted { firstItem, secondItem in
                if firstItem.1 == secondItem.1 {
                    return firstItem.0.updatedAt > secondItem.0.updatedAt
                }
                return firstItem.1 > secondItem.1
            }
            .map { $0.0 }
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
                createdAt: template.createdAt,
                updatedAt: template.updatedAt
            )
        }
    }

    private func sortTemplates() {
        templates.sort { firstTemplate, secondTemplate in
            if firstTemplate.updatedAt == secondTemplate.updatedAt {
                return firstTemplate.name.localizedCaseInsensitiveCompare(
                    secondTemplate.name
                ) == .orderedAscending
            }
            return firstTemplate.updatedAt > secondTemplate.updatedAt
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
}
