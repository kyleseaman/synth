import SwiftUI
import Combine

// swiftlint:disable:next type_body_length
class DocumentStore: ObservableObject {
    @Published var workspace: URL?
    @Published var fileTree: [FileTreeNode] = []
    @Published var openFiles: [Document] = []
    @Published var currentIndex = -1
    @Published var steeringFiles: [String] = []
    @Published var customAgents: [AgentInfo] = []
    @Published var recentFiles: [URL] = []
    @Published var expandedFolders: Set<URL> = []
    @Published var chatVisibleTabs: Set<URL> = []
    @Published var needsKiroSetup = false
    @Published var isLinksTabSelected = false
    @Published var isDailyNotesViewActive = false

    let noteIndex = NoteIndex()
    let backlinkIndex = BacklinkIndex()
    let tagIndex = TagIndex()
    let peopleIndex = PeopleIndex()
    let dailyNoteManager = DailyNoteManager()

    private static let meetingDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private var chatStates: [URL: DocumentChatState] = [:]
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
            isLinksTabSelected = false
            isDailyNotesViewActive = false
        }
        startWatching()
        loadKiroConfig()
        checkKiroSetup()
        dailyNoteManager.ensureFutureDays(workspace: url)
        loadFileTree()
    }

    func loadFileTree() {
        guard let workspace = workspace else { return }
        Task.detached(priority: .userInitiated) {
            let tree = FileTreeNode.scan(workspace)
            await MainActor.run {
                self.fileTree = tree
                self.noteIndex.rebuild(from: tree, workspace: workspace)
            }
            // Rebuild backlink and tag indexes on background thread
            let treeSnapshot = tree
            self.backlinkIndex.rebuild(fileTree: treeSnapshot)
            self.tagIndex.rebuild(fileTree: treeSnapshot)
            self.peopleIndex.rebuild(fileTree: treeSnapshot)
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

    func checkKiroSetup() {
        guard let workspace = workspace else { return }
        let kiroDir = workspace.appendingPathComponent(".kiro")
        needsKiroSetup = !FileManager.default.fileExists(atPath: kiroDir.path)
    }

    func bootstrapKiroConfig() {
        guard let workspace = workspace else { return }
        let kiroDir = workspace.appendingPathComponent(".kiro")
        let steeringDir = kiroDir.appendingPathComponent("steering")
        let agentsDir = kiroDir.appendingPathComponent("agents")
        let fileManager = FileManager.default

        try? fileManager.createDirectory(at: steeringDir, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: agentsDir, withIntermediateDirectories: true)

        // Bootstrap product.md steering file
        let productMd = """
        # Product Overview

        Describe your project here. This file provides context to the AI.

        ## Purpose
        What does this project do?

        ## Target Users
        Who is this for?
        """
        let productPath = steeringDir.appendingPathComponent("product.md")
        if !fileManager.fileExists(atPath: productPath.path) {
            try? productMd.write(to: productPath, atomically: true, encoding: .utf8)
        }

        // Bootstrap doc-writer agent
        let writerAgent: [String: Any] = [
            "name": "doc-writer",
            "description": "Document writer — drafts and generates content",
            "prompt": """
                You are a document writer integrated into Synth. \
                Draft new documents, expand outlines into prose, \
                write in various styles (technical, creative, business). \
                Start with structure, then fill in content. \
                Use markdown formatting. Be concise and direct.
                """,
            "tools": ["fs_read", "fs_write"],
            "allowedTools": ["fs_read", "fs_write"]
        ]
        let writerPath = agentsDir.appendingPathComponent("doc-writer.json")
        if !fileManager.fileExists(atPath: writerPath.path),
           let data = try? JSONSerialization.data(
               withJSONObject: writerAgent, options: [.prettyPrinted, .sortedKeys]
           ) {
            try? data.write(to: writerPath)
        }

        needsKiroSetup = false
        loadKiroConfig()
        loadFileTree()
    }

    func activateDailyNotes() {
        selectDailyNotesTab()
    }

    func selectDailyNotesTab() {
        guard workspace != nil else { return }
        isDailyNotesViewActive = true
        isLinksTabSelected = false
    }

    func open(_ url: URL) {
        isLinksTabSelected = false
        isDailyNotesViewActive = false
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

    // MARK: - Per-Document Chat State

    func chatState(for url: URL) -> DocumentChatState {
        if let existing = chatStates[url] { return existing }
        let state = DocumentChatState()
        chatStates[url] = state
        return state
    }

    func toggleChatForCurrentTab() {
        guard currentIndex >= 0, currentIndex < openFiles.count else { return }
        let url = openFiles[currentIndex].url
        if chatVisibleTabs.contains(url) {
            chatVisibleTabs.remove(url)
        } else {
            chatVisibleTabs.insert(url)
        }
    }

    var isChatVisibleForCurrentTab: Bool {
        guard currentIndex >= 0, currentIndex < openFiles.count else { return false }
        return chatVisibleTabs.contains(openFiles[currentIndex].url)
    }

    func switchTo(_ index: Int) {
        guard index >= 0 && index < openFiles.count else { return }
        currentIndex = index
        isLinksTabSelected = false
        isDailyNotesViewActive = false
    }

    func selectLinksTab() {
        isLinksTabSelected = true
        isDailyNotesViewActive = false
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
        let doc = openFiles[currentIndex]
        try? doc.save(doc.content)

        // Rename Untitled files based on first line
        if doc.url.lastPathComponent.hasPrefix("Untitled") {
            let firstLine = doc.content.string.components(separatedBy: "\n").first ?? ""
            let cleaned = firstLine
                .trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "#", with: "")
                .trimmingCharacters(in: .whitespaces)
                .prefix(50)
            if !cleaned.isEmpty {
                let safeName = String(cleaned).replacingOccurrences(of: "/", with: "-")
                let ext = doc.url.pathExtension
                let newURL = doc.url.deletingLastPathComponent().appendingPathComponent("\(safeName).\(ext)")
                if !FileManager.default.fileExists(atPath: newURL.path) {
                    try? FileManager.default.moveItem(at: doc.url, to: newURL)
                    openFiles[currentIndex] = Document(url: newURL, content: doc.content)
                    loadFileTree()
                }
            }
        }
        openFiles[currentIndex].isDirty = false

        // Incremental index updates after save
        let savedContent = openFiles[currentIndex].content.string
        let savedURL = openFiles[currentIndex].url
        backlinkIndex.updateFile(savedURL, content: savedContent)
        tagIndex.updateFile(savedURL, content: savedContent)
        peopleIndex.updateFile(savedURL, content: savedContent)
    }

    func saveAll() {
        for index in openFiles.indices where openFiles[index].isDirty {
            try? openFiles[index].save(openFiles[index].content)
            openFiles[index].isDirty = false
        }
        dailyNoteManager.saveAll()
    }

    func closeCurrentTab() {
        guard currentIndex >= 0 && currentIndex < openFiles.count else { return }
        closeTab(at: currentIndex)
    }

    func closeTab(at index: Int) {
        guard index >= 0 && index < openFiles.count else { return }
        let url = openFiles[index].url

        // Clean up chat state for this tab
        chatStates[url]?.stop()
        chatStates.removeValue(forKey: url)
        chatVisibleTabs.remove(url)

        openFiles.remove(at: index)
        if openFiles.isEmpty {
            currentIndex = -1
        } else if currentIndex == index {
            currentIndex = min(index, openFiles.count - 1)
        } else if currentIndex > index {
            currentIndex -= 1
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

        try? "# \n\n".write(to: url, atomically: true, encoding: .utf8)
        loadFileTree()
        open(url)
    }

    func newMeetingNote(name: String) {
        guard let workspace = workspace else { return }
        let meetingDir = workspace.appendingPathComponent("meetings")
        try? FileManager.default.createDirectory(at: meetingDir, withIntermediateDirectories: true)

        let sanitized = name.replacingOccurrences(
            of: "[/:\\x00-\\x1F\\x7F]",
            with: "-",
            options: .regularExpression
        )

        let dateString = Self.meetingDateFormatter.string(from: Date())

        let baseName = "\(dateString) \(sanitized)"
        var fileName = "\(baseName).md"
        var counter = 2
        while FileManager.default.fileExists(atPath: meetingDir.appendingPathComponent(fileName).path) {
            fileName = "\(baseName) \(counter).md"
            counter += 1
        }

        let url = meetingDir.appendingPathComponent(fileName)
        let template = """
        # \(name)

        **Date:** \(dateString)

        ### Agenda

        -

        ### Attendees

        -

        ### Notes



        ### TODOs

        - [ ]
        """
        try? template.write(to: url, atomically: true, encoding: .utf8)
        loadFileTree()
        open(url)
    }

    func createNoteIfNeeded(title: String, openAfter: Bool = true) {
        guard let workspace = workspace else { return }
        let sanitized = title
            .replacingOccurrences(
                of: "[/:\\x00-\\x1F\\x7F]",
                with: "-", options: .regularExpression
            )
            .replacingOccurrences(of: "..", with: "-")
            .trimmingCharacters(in: .whitespaces)
        guard !sanitized.isEmpty else { return }
        let url = workspace.appendingPathComponent("\(sanitized).md")
        guard url.standardizedFileURL.path.hasPrefix(
            workspace.standardizedFileURL.path
        ) else { return }
        if !FileManager.default.fileExists(atPath: url.path) {
            let content = "# \(sanitized)\n\n"
            try? content.write(
                to: url, atomically: true, encoding: .utf8
            )
        }
        loadFileTree()
        if openAfter {
            open(url)
        }
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
