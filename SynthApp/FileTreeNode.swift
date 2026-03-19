import Foundation
import UniformTypeIdentifiers
import CoreTransferable

struct FileTreeNode: Identifiable, Equatable, Transferable {
    let id: String
    let url: URL
    let isDirectory: Bool
    var children: [FileTreeNode]?

    var name: String { url.lastPathComponent }

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.url)
    }

    init(url: URL, isDirectory: Bool, children: [FileTreeNode]?) {
        self.id = url.path
        self.url = url
        self.isDirectory = isDirectory
        self.children = children
    }

    /// Synchronous scan (legacy, for compatibility)
    static func scan(_ url: URL) -> [FileTreeNode] {
        let keys: [URLResourceKey] = [.isDirectoryKey]
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: keys
        ) else { return [] }

        // Single resourceValues lookup per item, reused for
        // filtering, sorting, and mapping.
        struct AnnotatedItem {
            let url: URL
            let isDirectory: Bool
        }
        let annotated: [AnnotatedItem] = contents.compactMap { item in
            let name = item.lastPathComponent
            if name.hasPrefix(".") { return nil }
            if name == "daily" || name == "media" { return nil }
            let isDir = (try? item.resourceValues(
                forKeys: [.isDirectoryKey]
            ).isDirectory) ?? false
            return AnnotatedItem(url: item, isDirectory: isDir)
        }
        return annotated
            .sorted { first, second in
                if first.isDirectory != second.isDirectory {
                    return first.isDirectory
                }
                return first.url.lastPathComponent
                    .localizedCaseInsensitiveCompare(
                        second.url.lastPathComponent
                    ) == .orderedAscending
            }
            .map { item in
                FileTreeNode(
                    url: item.url,
                    isDirectory: item.isDirectory,
                    children: item.isDirectory
                        ? scan(item.url) : nil
                )
            }
    }

    /// Async scan - runs file I/O off main thread
    static func scanAsync(_ url: URL) async -> [FileTreeNode] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = scan(url)
                continuation.resume(returning: result)
            }
        }
    }
}
