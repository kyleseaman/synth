import Foundation

struct FileTreeNode: Identifiable, Equatable {
    let id: String
    let url: URL
    let isDirectory: Bool
    var children: [FileTreeNode]?

    var name: String { url.lastPathComponent }

    init(url: URL, isDirectory: Bool, children: [FileTreeNode]?) {
        self.id = url.path
        self.url = url
        self.isDirectory = isDirectory
        self.children = children
    }

    static func == (lhs: FileTreeNode, rhs: FileTreeNode) -> Bool {
        lhs.id == rhs.id
    }

    static func scan(_ url: URL) -> [FileTreeNode] {
        let keys: [URLResourceKey] = [.isDirectoryKey]
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: keys
        ) else { return [] }
        return contents
            .filter { !$0.lastPathComponent.hasPrefix(".") || $0.lastPathComponent == ".kiro" }
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
}
