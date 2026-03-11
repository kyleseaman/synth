import Foundation
import Observation

// MARK: - QMD Data Types

struct QmdSearchResult: Identifiable {
    let id: String  // docid
    let path: String
    let title: String
    let score: Double
    let snippet: String
    let displayPath: String?
    let context: String?
}

struct QmdStatus {
    let collections: [String]
    let documentCount: Int
    let hasEmbeddings: Bool
}

// MARK: - QMD Client

@Observable final class QmdClient: @unchecked Sendable {
    var isAvailable: Bool { qmdPath != nil }
    var isWorkspaceIndexed = false

    @ObservationIgnored private let qmdPath: String?
    @ObservationIgnored private let queue = DispatchQueue(
        label: "com.synth.qmd",
        qos: .userInitiated
    )
    @ObservationIgnored private static let timeoutSeconds: TimeInterval = 5

    init() {
        self.qmdPath = QmdResolver.resolve()
    }

    // MARK: - Search

    func search(
        query: String,
        collection: String? = nil,
        limit: Int = 20
    ) async -> [QmdSearchResult] {
        guard let path = qmdPath else { return [] }
        var args = ["query", query, "--json", "-n", String(limit)]
        if let collection {
            args += ["-c", collection]
        }
        guard let output = await run(path, arguments: args,
                                     timeout: 15) else {
            return []
        }
        return Self.parseSearchResults(output)
    }

    // MARK: - Status

    func checkStatus() async -> QmdStatus? {
        guard let path = qmdPath else { return nil }
        guard let output = await run(path, arguments: ["status", "--json"]) else {
            return nil
        }
        return Self.parseStatus(output)
    }

    func refreshWorkspaceStatus(workspace: URL) async {
        guard let status = await checkStatus() else {
            await MainActor.run { isWorkspaceIndexed = false }
            return
        }
        let workspacePath = workspace.path
        let indexed = status.collections.contains { collection in
            workspacePath.hasSuffix(collection) || collection == workspacePath
        }
        await MainActor.run { isWorkspaceIndexed = indexed }
    }

    // MARK: - Collection Management

    func collectionAdd(path: String, name: String) async -> Bool {
        guard let qmd = qmdPath else { return false }
        let output = await run(qmd, arguments: [
            "collection", "add", path, "--name", name
        ])
        return output != nil
    }

    func embed() async -> Bool {
        guard let qmd = qmdPath else { return false }
        // Embed can take a while — use longer timeout
        let output = await run(qmd, arguments: ["embed"], timeout: 120)
        return output != nil
    }

    // MARK: - Process Execution

    private func run(
        _ executable: String,
        arguments: [String],
        timeout: TimeInterval = timeoutSeconds
    ) async -> Data? {
        await withCheckedContinuation { continuation in
            queue.async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: executable)
                proc.arguments = arguments
                let stdout = Pipe()
                proc.standardOutput = stdout
                proc.standardError = FileHandle.nullDevice

                do {
                    try proc.run()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }

                let deadline = DispatchTime.now() + timeout
                let done = DispatchSemaphore(value: 0)
                proc.terminationHandler = { _ in done.signal() }

                if done.wait(timeout: deadline) == .timedOut {
                    proc.terminate()
                    continuation.resume(returning: nil)
                    return
                }

                guard proc.terminationStatus == 0 else {
                    continuation.resume(returning: nil)
                    return
                }

                let data = stdout.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: data)
            }
        }
    }

    // MARK: - JSON Parsing

    static func parseSearchResults(_ data: Data) -> [QmdSearchResult] {
        // QMD --json outputs an array of result objects
        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }

        // Handle both array-of-results and wrapper object formats
        let results: [[String: Any]]
        if let array = json as? [[String: Any]] {
            results = array
        } else if let wrapper = json as? [String: Any],
                  let array = wrapper["results"] as? [[String: Any]] {
            results = array
        } else {
            return []
        }

        return results.compactMap { entry -> QmdSearchResult? in
            guard let path = entry["path"] as? String
                    ?? entry["file"] as? String else {
                return nil
            }
            let docid = (entry["docid"] as? String)
                ?? (entry["id"] as? String)
                ?? path
            let title = (entry["title"] as? String)
                ?? URL(fileURLWithPath: path)
                    .deletingPathExtension().lastPathComponent
            let score = (entry["score"] as? Double) ?? 0
            let snippet = (entry["snippet"] as? String)
                ?? (entry["context"] as? String)
                ?? ""
            let displayPath = entry["displayPath"] as? String
            let context = entry["context"] as? String
            return QmdSearchResult(
                id: docid,
                path: path,
                title: title,
                score: score,
                snippet: snippet,
                displayPath: displayPath,
                context: context
            )
        }
    }

    static func parseStatus(_ data: Data) -> QmdStatus? {
        guard let json = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any] else {
            return nil
        }
        let collections: [String]
        if let colls = json["collections"] as? [[String: Any]] {
            collections = colls.compactMap {
                $0["path"] as? String ?? $0["name"] as? String
            }
        } else {
            collections = []
        }
        let docCount = (json["documents"] as? Int)
            ?? (json["document_count"] as? Int)
            ?? 0
        let hasEmbed = (json["embeddings"] as? Bool)
            ?? (json["has_embeddings"] as? Bool)
            ?? (docCount > 0)
        return QmdStatus(
            collections: collections,
            documentCount: docCount,
            hasEmbeddings: hasEmbed
        )
    }
}
