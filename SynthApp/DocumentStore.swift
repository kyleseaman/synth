import SwiftUI
import Combine

class DocumentStore: ObservableObject {
    @Published var workspace: URL?
    @Published var fileTree: [FileTreeNode] = []
    @Published var openFiles: [Document] = []
    @Published var currentIndex = -1
    @Published var steeringFiles: [String] = []
    @Published var customAgents: [AgentInfo] = []
    @Published var recentFiles: [URL] = []
    @Published var expandedFolders: Set<URL> = []

    private let maxRecentFiles = 20
    private var fileWatcher: DispatchSourceFileSystemObject?
    private var watcherFD: Int32 = -1

    init() {
        loadRecentFiles()
        if let path = UserDefaults.standard.string(forKey: "lastWorkspace"),
           FileManager.default.fileExists(atPath: path) {
            workspace = URL(fileURLWithPath: path)
            loadFileTree()
            startWatching()
        }
    }

    deinit {
        stopWatching()
    }

    private func startWatching() {
        guard let workspace = workspace else { return }
        stopWatching()

        watcherFD = Darwin.open(workspace.path, O_EVTONLY)
        guard watcherFD >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: watcherFD,
            eventMask: .write,
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.loadFileTree()
        }
        source.setCancelHandler { [weak self] in
            if let fileDesc = self?.watcherFD, fileDesc >= 0 { close(fileDesc) }
            self?.watcherFD = -1
        }
        source.resume()
        fileWatcher = source
    }

    private func stopWatching() {
        fileWatcher?.cancel()
        fileWatcher = nil
    }

    func loadRecentFiles() {
        if let paths = UserDefaults.standard.stringArray(forKey: "recentFiles") {
            recentFiles = paths.compactMap { URL(fileURLWithPath: $0) }
                .filter { FileManager.default.fileExists(atPath: $0.path) }
        }
    }

    func addToRecent(_ url: URL) {
        recentFiles.removeAll { $0 == url }
        recentFiles.insert(url, at: 0)
        if recentFiles.count > maxRecentFiles {
            recentFiles = Array(recentFiles.prefix(maxRecentFiles))
        }
        UserDefaults.standard.set(recentFiles.map { $0.path }, forKey: "recentFiles")
    }

    func setWorkspace(_ url: URL) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            workspace = url
            UserDefaults.standard.set(url.path, forKey: "lastWorkspace")
            fileTree = FileTreeNode.scan(url)
            openFiles.removeAll()
            currentIndex = -1
        }
        startWatching()
    }

    func loadFileTree() {
        guard let workspace = workspace else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            fileTree = FileTreeNode.scan(workspace)
        }
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
            addToRecent(url)
            return
        }
        guard let doc = Document.load(from: url) else { return }
        openFiles.append(doc)
        currentIndex = openFiles.count - 1
        addToRecent(url)
    }

    func switchTo(_ index: Int) {
        guard index >= 0 && index < openFiles.count else { return }
        currentIndex = index
    }

    func updateContent(_ content: NSAttributedString) {
        guard currentIndex >= 0 && currentIndex < openFiles.count else { return }
        let current = openFiles[currentIndex].content.string
        let new = content.string
        if current != new {
            openFiles[currentIndex].content = content
            openFiles[currentIndex].isDirty = true
        }
    }

    func save() {
        guard currentIndex >= 0 && currentIndex < openFiles.count else { return }
        try? openFiles[currentIndex].save(openFiles[currentIndex].content)
        openFiles[currentIndex].isDirty = false
    }

    func saveAll() {
        for index in openFiles.indices where openFiles[index].isDirty {
            try? openFiles[index].save(openFiles[index].content)
            openFiles[index].isDirty = false
        }
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

        // Find next available Untitled number
        var num = 1
        var url = drafts.appendingPathComponent("Untitled.md")
        while FileManager.default.fileExists(atPath: url.path) {
            num += 1
            url = drafts.appendingPathComponent("Untitled \(num).md")
        }

        try? "".write(to: url, atomically: true, encoding: .utf8)
        loadFileTree()
        open(url)
    }

    func delete(_ url: URL) {
        // Close if open
        if let idx = openFiles.firstIndex(where: { $0.url == url }) {
            closeTab(at: idx)
        }
        try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        loadFileTree()
    }

    func promptRename(_ url: URL) {
        let alert = NSAlert()
        alert.messageText = "Rename"
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        input.stringValue = url.lastPathComponent
        alert.accessoryView = input

        if alert.runModal() == .alertFirstButtonReturn {
            let newName = input.stringValue.trimmingCharacters(in: .whitespaces)
            guard !newName.isEmpty, newName != url.lastPathComponent else { return }
            let newURL = url.deletingLastPathComponent().appendingPathComponent(newName)
            do {
                try FileManager.default.moveItem(at: url, to: newURL)
                // Update open file if renamed
                if let idx = openFiles.firstIndex(where: { $0.url == url }) {
                    openFiles[idx] = Document(url: newURL, content: openFiles[idx].content)
                }
                loadFileTree()
            } catch {}
        }
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
        let keys: [URLResourceKey] = [.isDirectoryKey]
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys
        ) else { return [] }
        return contents
            .filter { !$0.lastPathComponent.hasPrefix(".") || $0.lastPathComponent == ".kiro" }
            .sorted { first, second in
                let firstDir = (try? first.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                let secondDir = (try? second.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if firstDir != secondDir { return firstDir }
                let cmp = first.lastPathComponent.localizedCaseInsensitiveCompare(second.lastPathComponent)
                return cmp == .orderedAscending
            }
            .map { item in
                let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                return FileTreeNode(url: item, isDirectory: isDir, children: isDir ? scan(item) : nil)
            }
    }
}
