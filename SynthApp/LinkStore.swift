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
