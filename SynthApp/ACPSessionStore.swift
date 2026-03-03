import Foundation

/// Persists ACP session IDs per document URL so conversations survive app restarts.
enum ACPSessionStore {
    private static let fileName = "acp-sessions.json"

    private static var storeURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return appSupport
            .appendingPathComponent("Synth", isDirectory: true)
            .appendingPathComponent(fileName)
    }

    private static func loadMap() -> [String: String] {
        guard let data = try? Data(contentsOf: storeURL),
              let map = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return map
    }

    private static func saveMap(_ map: [String: String]) {
        let directory = storeURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(map) {
            try? data.write(to: storeURL, options: .atomic)
        }
    }

    private static func key(for documentURL: URL) -> String {
        documentURL.standardizedFileURL.resolvingSymlinksInPath().path
    }

    static func sessionId(for documentURL: URL) -> String? {
        loadMap()[key(for: documentURL)]
    }

    static func save(sessionId: String, for documentURL: URL) {
        var map = loadMap()
        map[key(for: documentURL)] = sessionId
        saveMap(map)
    }

    static func remove(for documentURL: URL) {
        var map = loadMap()
        map.removeValue(forKey: key(for: documentURL))
        saveMap(map)
    }
}
