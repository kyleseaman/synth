import Foundation
import os.log

/// Persists ACP session IDs per document URL so conversations survive app restarts.
enum ACPSessionStore {
    private static let fileName = "acp-sessions.json"
    private static let maxEntries = 500
    private static let logger = Logger(subsystem: "com.synth", category: "ACPSessionStore")

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
        do {
            let data = try Data(contentsOf: storeURL)
            return try JSONDecoder().decode([String: String].self, from: data)
        } catch {
            if (error as NSError).domain == NSCocoaErrorDomain,
               (error as NSError).code == NSFileReadNoSuchFileError {
                return [:]
            }
            logger.warning("Failed to load session store: \(error.localizedDescription)")
            return [:]
        }
    }

    private static func saveMap(_ map: [String: String]) {
        var pruned = map
        if pruned.count > maxEntries {
            let fileManager = FileManager.default
            let staleKeys = pruned.keys.filter { !fileManager.fileExists(atPath: $0) }
            for staleKey in staleKeys {
                pruned.removeValue(forKey: staleKey)
            }
            if pruned.count > maxEntries {
                let excess = pruned.count - maxEntries
                for dropKey in pruned.keys.prefix(excess) {
                    pruned.removeValue(forKey: dropKey)
                }
            }
        }

        let directory = storeURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(pruned)
            try data.write(to: storeURL, options: .atomic)
        } catch {
            logger.error("Failed to save session store: \(error.localizedDescription)")
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
