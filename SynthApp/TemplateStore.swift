import Foundation
import Observation

struct SavedTemplate: Codable, Equatable, Identifiable {
    let identifier: UUID
    let name: String
    let content: String
    let shortcutSlot: Int?
    let createdAt: Date
    let updatedAt: Date

    var id: UUID { identifier }
}

@Observable final class TemplateStore {
    private(set) var templates: [SavedTemplate] = []

    @ObservationIgnored private let storage: UserDefaults
    @ObservationIgnored private let storageKey: String
    @ObservationIgnored private let contentMatchScore = 50

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
            finalizeTemplateMutation(identifier: updated.identifier, slot: normalizedSlot)
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
        finalizeTemplateMutation(identifier: template.identifier, slot: normalizedSlot)
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
        templates[templateIndex] = SavedTemplate(
            identifier: existing.identifier,
            name: normalizedName,
            content: normalizedContent,
            shortcutSlot: normalizedSlot,
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
                    return (template, contentMatchScore)
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
