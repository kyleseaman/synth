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
        return contents
            .filter {
                let name = $0.lastPathComponent
                if name.hasPrefix(".") { return false }
                if name == "daily" || name == "media" { return false }
                return true
            }
            .sorted { first, second in
                let firstDir = (try? first.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                let secondDir = (try? second.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if firstDir != secondDir { return firstDir }
                return first.lastPathComponent.localizedCaseInsensitiveCompare(
                    second.lastPathComponent
                ) == .orderedAscending
            }
            .map { item in
                let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                return FileTreeNode(url: item, isDirectory: isDir, children: isDir ? scan(item) : nil)
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
