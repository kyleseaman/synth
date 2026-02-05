import SwiftUI
import Combine

class DocumentStore: ObservableObject {
    @Published var workspace: URL?
    @Published var fileTree: [FileTreeNode] = []
    @Published var openFiles: [Document] = []
    @Published var currentIndex = -1
    @Published var steeringFiles: [String] = []
    @Published var customAgents: [AgentInfo] = []

    init() {
        if let path = UserDefaults.standard.string(forKey: "lastWorkspace"),
           FileManager.default.fileExists(atPath: path) {
            workspace = URL(fileURLWithPath: path)
            loadFileTree()
        }
    }

    func setWorkspace(_ url: URL) {
        workspace = url
        UserDefaults.standard.set(url.path, forKey: "lastWorkspace")
        loadFileTree()
        openFiles.removeAll()
        currentIndex = -1
    }

    func loadFileTree() {
        guard let workspace = workspace else { return }
        fileTree = FileTreeNode.scan(workspace)
    }

    func loadKiroConfig() {
        guard let workspace = workspace else { return }
        let kiroDir = workspace.appendingPathComponent(".kiro")

        // Load steering files
        steeringFiles = []
        let steeringDir = kiroDir.appendingPathComponent("steering")
        if let files = try? FileManager.default.contentsOfDirectory(atPath: steeringDir.path) {
            steeringFiles = files.filter { $0.hasSuffix(".md") }
        }

        // Load custom agents
        customAgents = []
        let agentsDir = kiroDir.appendingPathComponent("agents")
        if let files = try? FileManager.default.contentsOfDirectory(at: agentsDir, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension == "json" {
                if let data = try? Data(contentsOf: file),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let name = (json["name"] as? String) ?? file.deletingPathExtension().lastPathComponent
                    let desc = json["description"] as? String
                    customAgents.append(AgentInfo(name: name, description: desc))
                }
            }
        }
    }

    func open(_ url: URL) {
        if let idx = openFiles.firstIndex(where: { $0.url == url }) {
            currentIndex = idx
            return
        }
        guard let doc = Document.load(from: url) else { return }
        openFiles.append(doc)
        currentIndex = openFiles.count - 1
    }

    func switchTo(_ index: Int) {
        guard index >= 0 && index < openFiles.count else { return }
        currentIndex = index
    }

    func updateContent(_ content: NSAttributedString) {
        guard currentIndex >= 0 && currentIndex < openFiles.count else { return }
        openFiles[currentIndex].content = content
    }

    func save() {
        guard currentIndex >= 0 && currentIndex < openFiles.count else { return }
        try? openFiles[currentIndex].save(openFiles[currentIndex].content)
    }

    func closeCurrentTab() {
        guard currentIndex >= 0 && currentIndex < openFiles.count else { return }
        closeTab(at: currentIndex)
    }

    func closeTab(at index: Int) {
        guard index >= 0 && index < openFiles.count else { return }
        openFiles.remove(at: index)
        if openFiles.isEmpty {
            currentIndex = -1
        } else if currentIndex >= index {
            currentIndex = max(0, currentIndex - 1)
        }
    }

    func newDraft() {
        guard let workspace = workspace else { return }
        let drafts = workspace.appendingPathComponent("drafts")
        try? FileManager.default.createDirectory(at: drafts, withIntermediateDirectories: true)
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = drafts.appendingPathComponent("untitled-\(timestamp).md")
        try? "".write(to: url, atomically: true, encoding: .utf8)
        loadFileTree()
        open(url)
    }

    func pickWorkspace() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.prompt = "Open Workspace"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                self.setWorkspace(url)
            }
        }
    }
}

struct FileTreeNode: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let isDirectory: Bool
    var children: [FileTreeNode]?

    var name: String { url.lastPathComponent }

    static func == (lhs: FileTreeNode, rhs: FileTreeNode) -> Bool {
        lhs.id == rhs.id
    }

    static func scan(_ url: URL) -> [FileTreeNode] {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        return contents
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .sorted { first, second in
                let firstDir = (try? first.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                let secondDir = (try? second.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if firstDir != secondDir { return firstDir }
                return a.lastPathComponent.localizedCaseInsensitiveCompare(b.lastPathComponent) == .orderedAscending
            }
            .map { item in
                let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                return FileTreeNode(url: item, isDirectory: isDir, children: isDir ? scan(item) : nil)
            }
    }
}
