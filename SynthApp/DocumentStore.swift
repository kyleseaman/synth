import SwiftUI
import AppKit
import Observation

private enum DiskDeleteResult {
    case deleted(URL)
    case notFound
    case failed(String)
}

private enum DiskDeleteScope {
    case workspace
    case media
}

enum DetailViewMode: Equatable {
    case editor
    case search
    case dailyNotes
    case links
    case media
    case kanban
}

enum ChatPlacement: String {
    case bottom
    case trailing
}

enum ActiveModal: Equatable {
    case fileLauncher
    case linkCapture
    case meetingNote
    case tagBrowser(String?)
    case peopleBrowser(String?)
}

@MainActor
@Observable
final class DocumentStore {
    var workspace: URL?
    var fileTreeVersion: Int = 0
    var fileTree: [FileTreeNode] = [] {
        didSet {
            fileTreeVersion &+= 1
        }
    }
    var openFiles: [Document] = []
    var currentIndex = -1
    var steeringFiles: [String] = []
    var customAgents: [AgentInfo] = []
    var recentFiles: [URL] = []
    var expandedFolders: Set<URL> = []
    var chatVisibleTabs: Set<URL> = []
    var chatPlacement: ChatPlacement = .bottom {
        didSet { UserDefaults.standard.set(chatPlacement.rawValue, forKey: "chatPlacement") }
    }
    var chatWidth: CGFloat = 360 {
        didSet { UserDefaults.standard.set(chatWidth, forKey: "chatWidth") }
    }
    var needsKiroSetup = false
    var detailMode: DetailViewMode = .editor
    var mediaFiles: [URL] = []
    var dedicatedSearch = DedicatedSearchState()

    // MARK: - Centralized UI State
    var columnVisibility: NavigationSplitViewVisibility = .all
    var activeModal: ActiveModal?
    var imageDetailURL: URL?
    var showBacklinks = false
    var dailyDateScrollTarget: String?
    var renameTarget: URL?
    var renameText: String = ""
    var newFolderParent: URL?
    var newFolderName: String = ""
    var pendingDeleteTarget: URL?
    var pendingDeleteName: String = ""
    var pendingDeleteIsDirectory = false
    var showWorkspacePicker = false
    var showDocxExport = false
    var docxExportData: Data?

    let noteIndex = NoteIndex()
    let backlinkIndex = BacklinkIndex()
    let tagIndex = TagIndex()
    let peopleIndex = PeopleIndex()
    let dailyNoteManager = DailyNoteManager()
    let mcpServer = MCPServerManager()
    var qmdClient: QmdClient?

    private let saveQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        return queue
    }()

    private static let meetingDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    @ObservationIgnored private var chatStates: [URL: DocumentChatState] = [:]
    @ObservationIgnored private let maxRecentFiles = 20
    @ObservationIgnored private let watcher = WorkspaceWatcher()
    @ObservationIgnored private var fileTreeLoadTask: Task<Void, Never>?
    @ObservationIgnored private var pendingFileTreeReloadTask: Task<Void, Never>?
    @ObservationIgnored private var pendingWatcherReloadTask: Task<Void, Never>?
    @ObservationIgnored private var isFileTreeScanRunning = false
    @ObservationIgnored private var fileTreeRescanRequested = false
    @ObservationIgnored private var activeFileTreeScanID = UUID()
    /// Tracks recent saves to skip self-triggered FSEvents.
    @ObservationIgnored private var recentSaves: [URL: Date] = [:]

    init() {
        if let raw = UserDefaults.standard.string(forKey: "chatPlacement"),
           let saved = ChatPlacement(rawValue: raw) {
            chatPlacement = saved
        }
        let savedWidth = UserDefaults.standard.double(forKey: "chatWidth")
        if savedWidth > 0 { chatWidth = savedWidth }
        loadRecentFiles()
        dailyNoteManager.onSave = { [weak self] url, content in
            self?.updateIndexes(for: url, content: content)
        }
        if let path = UserDefaults.standard.string(forKey: "lastWorkspace"),
           FileManager.default.fileExists(atPath: path) {
            let restoredWorkspace = URL(fileURLWithPath: path)
            workspace = restoredWorkspace
            loadFileTree()
            startWatching()
            loadKiroConfig()
            checkKiroSetup()
            mcpServer.start(workspace: restoredWorkspace)
            initializeQmd(workspace: restoredWorkspace)
        }
    }

    func shutdownForTermination() {
        resetFileTreeScanState()
        saveAll()
        chatStates.values.forEach { chatState in
            chatState.stop()
        }
        stopWatching()
        mcpServer.stop()
    }

    private func initializeQmd(workspace: URL) {
        guard UserDefaults.standard.object(forKey: "qmdEnabled") as? Bool ?? true else {
            qmdClient = nil
            return
        }
        let client = QmdClient()
        guard client.isAvailable else {
            qmdClient = nil
            return
        }
        qmdClient = client
        Task {
            await client.refreshWorkspaceStatus(workspace: workspace)
        }
    }

    func enableQmd(workspace: URL) {
        initializeQmd(workspace: workspace)
    }

    func disableQmd() {
        qmdClient = nil
    }

    private func startWatching() {
        guard let workspace else { return }
        watcher.start(workspace: workspace) { [weak self] events in
            self?.handleWorkspaceEvents(events)
        }
    }

    private func stopWatching() {
        watcher.stop()
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
        resetFileTreeScanState()

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            workspace = url
            UserDefaults.standard.set(url.path, forKey: "lastWorkspace")
            fileTree = FileTreeNode.scan(url)
            openFiles.removeAll()
            currentIndex = -1
            detailMode = .editor
            mediaFiles = MediaManager.screenshotURLs(in: url)
            dedicatedSearch.clear()
            pendingDeleteTarget = nil
            pendingDeleteName = ""
            pendingDeleteIsDirectory = false
        }
        startWatching()
        loadKiroConfig()
        checkKiroSetup()
        dailyNoteManager.ensureFutureDays(workspace: url)
        mcpServer.start(workspace: url)
        initializeQmd(workspace: url)
        loadFileTree()
    }

    func loadFileTree() {
        guard let workspace = workspace else { return }
        fileTreeRescanRequested = true
        guard !isFileTreeScanRunning else { return }
        runFileTreeScan(for: workspace)
    }

    private struct WorkspaceScanResult {
        let tree: [FileTreeNode]
        let media: [URL]
    }

    private static func scanWorkspace(at workspace: URL) async -> WorkspaceScanResult {
        let tree = await FileTreeNode.scanAsync(workspace)
        let media = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = MediaManager.screenshotURLs(in: workspace)
                continuation.resume(returning: result)
            }
        }
        return WorkspaceScanResult(tree: tree, media: media)
    }

    private func runFileTreeScan(for workspace: URL) {
        guard fileTreeRescanRequested else { return }
        isFileTreeScanRunning = true
        fileTreeRescanRequested = false
        let scanID = UUID()
        activeFileTreeScanID = scanID

        fileTreeLoadTask?.cancel()
        fileTreeLoadTask = Task(priority: .userInitiated) { [weak self] in
            let scanResult = await Self.scanWorkspace(at: workspace)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self = self else { return }
                guard Self.shouldApplyFileTreeScanResult(
                    activeScanID: self.activeFileTreeScanID,
                    scanID: scanID,
                    currentWorkspace: self.workspace,
                    scanWorkspace: workspace
                ) else {
                    if self.activeFileTreeScanID == scanID {
                        self.isFileTreeScanRunning = false
                        self.fileTreeRescanRequested = false
                    }
                    return
                }
                self.applyScanResult(scanResult, workspace: workspace)
                self.isFileTreeScanRunning = false
                if self.fileTreeRescanRequested {
                    self.runFileTreeScan(for: workspace)
                }
            }
        }
    }

    private func applyScanResult(_ scanResult: WorkspaceScanResult, workspace: URL) {
        fileTree = scanResult.tree
        mediaFiles = scanResult.media
        // Use unified indexer - reads files in parallel off main thread
        let context = IndexContext(
            noteIndex: noteIndex,
            backlinkIndex: backlinkIndex,
            tagIndex: tagIndex,
            peopleIndex: peopleIndex
        )
        Task {
            await UnifiedIndexer.rebuildAllAsync(
                fileTree: scanResult.tree, workspace: workspace, context: context
            )
            // Clean orphaned media after indexes are populated
            let currentMedia = scanResult.media
            let index = self.noteIndex
            Task(priority: .utility) {
                let removed = Self.cleanOrphanedMedia(
                    mediaFiles: currentMedia, workspace: workspace, noteIndex: index
                )
                if !removed.isEmpty {
                    await MainActor.run { [weak self] in
                        self?.mediaFiles.removeAll { removed.contains($0) }
                    }
                }
            }
        }
    }

    private func rebuildIndexesFromCurrentTree() {
        guard let workspace else { return }
        let context = IndexContext(
            noteIndex: noteIndex,
            backlinkIndex: backlinkIndex,
            tagIndex: tagIndex,
            peopleIndex: peopleIndex
        )
        Task {
            await UnifiedIndexer.rebuildAllAsync(
                fileTree: fileTree, workspace: workspace, context: context
            )
        }
    }

    @discardableResult
    private static func cleanOrphanedMedia(
        mediaFiles: [URL], workspace: URL, noteIndex: NoteIndex
    ) -> Set<URL> {
        guard !mediaFiles.isEmpty else { return [] }

        var removed: Set<URL> = []
        for mediaURL in mediaFiles {
            let filename = mediaURL.lastPathComponent
            if noteIndex.notesContaining(filename).isEmpty {
                try? FileManager.default.trashItem(at: mediaURL, resultingItemURL: nil)
                removed.insert(mediaURL)
            }
        }
        return removed
    }

    func updateIndexes(for url: URL, content: String) {
        noteIndex.updateFile(url, content: content)
        backlinkIndex.updateFile(url, content: content)
        tagIndex.updateFile(url, content: content)
        peopleIndex.updateFile(url, content: content)
    }

    func loadKiroConfig() {
        guard let workspace else { return }
        let config = KiroConfigManager.loadConfig(workspace: workspace)
        steeringFiles = config.steeringFiles
        customAgents = config.agents
    }

    func checkKiroSetup() {
        guard let workspace else { return }
        needsKiroSetup = KiroConfigManager.needsSetup(workspace: workspace)
    }

    func bootstrapKiroConfig() {
        guard let workspace else { return }
        KiroConfigManager.bootstrap(workspace: workspace)
        needsKiroSetup = false
        loadKiroConfig()
        loadFileTree()
    }

    func activateDailyNotes() {
        if detailMode == .dailyNotes {
            dailyDateScrollTarget = DailyNoteManager.dateIdentifier(Date())
        }
        selectDailyNotesTab()
    }

    func requestDailyDateScroll(_ dateIdentifier: String) {
        activateDailyNotes()
        dailyDateScrollTarget = dateIdentifier
    }

    func selectDailyNotesTab() {
        guard workspace != nil else { return }
        detailMode = .dailyNotes
    }

    func selectSearchTab() {
        guard workspace != nil else { return }
        detailMode = .search
    }

    func open(_ url: URL) {
        openDocument(url, switchToEditorMode: true)
    }

    func openFromSearch(_ url: URL) {
        openDocument(url, switchToEditorMode: false)
    }

    private func openDocument(_ url: URL, switchToEditorMode: Bool) {
        saveAll()
        if switchToEditorMode {
            detailMode = .editor
        }
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

    func selectLinksTab() {
        detailMode = .links
    }

    func selectMediaTab() {
        detailMode = .media
    }

    func notesReferencing(
        mediaFilename: String
    ) -> [(title: String, url: URL)] {
        noteIndex.notesContaining(mediaFilename)
    }

    var currentDocumentURL: URL? {
        guard currentIndex >= 0, currentIndex < openFiles.count else { return nil }
        return openFiles[currentIndex].url
    }

    @discardableResult
    func reloadOpenDocumentFromDisk(_ fileURL: URL) -> Bool {
        let resolvedURL = Self.canonicalFileURL(fileURL)
        guard let fileIndex = openFiles.firstIndex(
            where: { Self.canonicalFileURL($0.url) == resolvedURL }
        ) else { return false }
        guard let reloadedDocument = Document.load(from: openFiles[fileIndex].url) else { return false }

        openFiles[fileIndex].content = reloadedDocument.content
        openFiles[fileIndex].isDirty = false

        let reloadedContent = reloadedDocument.content.string
        let reloadedURL = openFiles[fileIndex].url
        updateIndexes(for: reloadedURL, content: reloadedContent)
        return true
    }

    func savePastedImageToMedia(_ image: NSImage, noteURL: URL) -> String? {
        guard let workspace else { return nil }
        guard let savedMedia = try? MediaManager.saveScreenshotImage(
            image,
            workspaceURL: workspace,
            noteURL: noteURL
        ) else { return nil }
        // Add to media list directly instead of full rescan
        if !mediaFiles.contains(savedMedia.fileURL) {
            mediaFiles.append(savedMedia.fileURL)
        }
        return savedMedia.relativePath
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

    func saveSelectedRange(_ range: NSRange) {
        guard currentIndex >= 0 && currentIndex < openFiles.count else { return }
        openFiles[currentIndex].savedSelectedRange = range
    }

    func saveSelectedRange(_ range: NSRange, for url: URL) {
        guard let index = openFiles.firstIndex(where: { $0.url == url }) else { return }
        openFiles[index].savedSelectedRange = range
    }

    func savedSelectedRange() -> NSRange? {
        guard currentIndex >= 0 && currentIndex < openFiles.count else { return nil }
        return openFiles[currentIndex].savedSelectedRange
    }

    func save() {
        guard currentIndex >= 0 && currentIndex < openFiles.count else { return }
        let doc = openFiles[currentIndex]
        try? doc.save(doc.content)

        // Rename Untitled files based on first line
        if doc.url.lastPathComponent.hasPrefix("Untitled") {
            if let newURL = renamedURL(for: doc) {
                try? FileManager.default.moveItem(at: doc.url, to: newURL)
                openFiles[currentIndex] = Document(url: newURL, content: doc.content)
                loadFileTree()
            }
        }
        openFiles[currentIndex].isDirty = false

        // Mark save to skip self-triggered FSEvent
        let savedURL = openFiles[currentIndex].url
        recentSaves[savedURL] = Date()

        // Incremental index updates after save
        let savedContent = openFiles[currentIndex].content.string
        updateIndexes(for: savedURL, content: savedContent)
    }

    func exportAsDocx() {
        guard currentIndex >= 0, currentIndex < openFiles.count else { return }
        let doc = openFiles[currentIndex]
        let plainText = MarkdownFormat.restoreMarkup(in: doc.content)
        let rendered = MarkdownFormat().render(plainText)
        let range = NSRange(location: 0, length: rendered.length)
        let attrs: [NSAttributedString.DocumentAttributeKey: Any] = [
            .documentType: NSAttributedString.DocumentType.officeOpenXML
        ]
        guard let data = try? rendered.data(
            from: range, documentAttributes: attrs
        ) else { return }
        docxExportData = data
        showDocxExport = true
    }

    func saveAll() {
        // Collect documents to save on main thread
        var docsToSave: [(url: URL, content: String, isDocx: Bool, index: Int)] = []
        var renameOps: [(index: Int, oldURL: URL, newURL: URL)] = []

        for index in openFiles.indices where openFiles[index].isDirty {
            let doc = openFiles[index]
            let isDocx = doc.url.pathExtension.lowercased() == "docx"

            // For docx, save synchronously (needs attributed string)
            if isDocx {
                try? doc.save(doc.content)
            } else {
                docsToSave.append((doc.url, doc.content.string, isDocx, index))
            }

            // Check for rename
            if doc.url.lastPathComponent.hasPrefix("Untitled"),
               let newURL = renamedURL(for: doc) {
                renameOps.append((index, doc.url, newURL))
            }

            openFiles[index].isDirty = false

            // Mark save + update indexes
            let savedURL = openFiles[index].url
            recentSaves[savedURL] = Date()
            let savedContent = openFiles[index].content.string
            updateIndexes(for: savedURL, content: savedContent)
        }

        // Background save for plain text files
        if !docsToSave.isEmpty {
            let operation = BlockOperation { [docsToSave] in
                for doc in docsToSave {
                    try? doc.content.write(to: doc.url, atomically: true, encoding: .utf8)
                }
            }
            saveQueue.addOperation(operation)
        }

        // Handle renames on main thread
        for rename in renameOps {
            try? FileManager.default.moveItem(at: rename.oldURL, to: rename.newURL)
            let content = openFiles[rename.index].content
            openFiles[rename.index] = Document(url: rename.newURL, content: content)
        }
        if !renameOps.isEmpty { loadFileTree() }

        dailyNoteManager.saveAll()
    }

    private func renamedURL(for doc: Document) -> URL? {
        let firstLine = doc.content.string.components(separatedBy: "\n").first ?? ""
        let cleaned = firstLine
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "#", with: "")
            .trimmingCharacters(in: .whitespaces)
            .prefix(50)
        guard !cleaned.isEmpty else { return nil }
        let safeName = String(cleaned).replacingOccurrences(of: "/", with: "-")
        let ext = doc.url.pathExtension
        let newURL = doc.url.deletingLastPathComponent()
            .appendingPathComponent("\(safeName).\(ext)")
        guard !FileManager.default.fileExists(atPath: newURL.path) else { return nil }
        return newURL
    }

    private static func canonicalFileURL(_ fileURL: URL) -> URL {
        fileURL.standardizedFileURL.resolvingSymlinksInPath()
    }

    private static func equivalentFileURL(_ firstURL: URL, _ secondURL: URL) -> Bool {
        if firstURL.standardizedFileURL.path == secondURL.standardizedFileURL.path {
            return true
        }
        return canonicalFileURL(firstURL).path == canonicalFileURL(secondURL).path
    }

    private static func deletionCandidates(for url: URL) -> [URL] {
        let standardized = url.standardizedFileURL
        let canonical = canonicalFileURL(url)
        if standardized.path == canonical.path {
            return [standardized]
        }
        return [standardized, canonical]
    }

    private func removeFileFromInMemoryTree(_ fileURL: URL) {
        fileTree = Self.removingNode(fileURL, from: fileTree)
    }

    func addFileToInMemoryTree(_ fileURL: URL) {
        guard let workspace else { return }
        let relativePath = fileURL.path.replacingOccurrences(
            of: workspace.path + "/", with: ""
        )
        let components = relativePath.split(separator: "/").map(String.init)
        guard !components.isEmpty else { return }
        fileTree = Self.insertingNode(fileURL, path: components, into: fileTree)
    }

    private static func insertingNode(
        _ target: URL,
        path: [String],
        into nodes: [FileTreeNode]
    ) -> [FileTreeNode] {
        guard let first = path.first else { return nodes }
        let rest = Array(path.dropFirst())

        for (index, node) in nodes.enumerated() where node.url.lastPathComponent == first {
            if rest.isEmpty {
                return nodes // Already exists
            }
            if node.isDirectory, let children = node.children {
                var updated = nodes
                updated[index] = FileTreeNode(
                    url: node.url,
                    isDirectory: true,
                    children: insertingNode(target, path: rest, into: children)
                )
                return updated
            }
            return nodes
        }

        // Not found — add new node
        if rest.isEmpty {
            let newNode = FileTreeNode(url: target, isDirectory: false, children: nil)
            return (nodes + [newNode]).sorted { $0.url.lastPathComponent < $1.url.lastPathComponent }
        }
        return nodes
    }

    private static func removingNode(_ target: URL, from nodes: [FileTreeNode]) -> [FileTreeNode] {
        nodes.compactMap { node in
            if equivalentFileURL(node.url, target) {
                return nil
            }

            if node.isDirectory, let children = node.children {
                let prunedChildren = removingNode(target, from: children)
                return FileTreeNode(url: node.url, isDirectory: true, children: prunedChildren)
            }

            return node
        }
    }

    private func scheduleFileTreeReload(delaySeconds: TimeInterval = 0.3) {
        pendingFileTreeReloadTask?.cancel()
        pendingFileTreeReloadTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.loadFileTree()
        }
    }

    private func handleWorkspaceEvents(_ events: [FileEvent]) {
        guard let workspace else { return }
        let workspacePath = workspace.standardizedFileURL.path

        // Clean stale recent saves
        let staleThreshold = Date().addingTimeInterval(-2)
        recentSaves = recentSaves.filter { $0.value > staleThreshold }

        // Filter to relevant events
        let relevant = events.filter { event in
            WorkspaceWatcher.shouldRefreshSidebar(
                forWorkspace: workspacePath,
                eventPath: event.path
            )
        }
        guard !relevant.isEmpty else { return }

        // Fallback to full rescan for large batches
        if relevant.count > 10 {
            scheduleFullRescan()
            return
        }

        let indexContext = IndexContext(
            noteIndex: noteIndex,
            backlinkIndex: backlinkIndex,
            tagIndex: tagIndex,
            peopleIndex: peopleIndex
        )
        let validExtensions: Set<String> = ["md", "txt"]
        var treeChanged = false

        for event in relevant {
            let url = event.url

            // Skip self-triggered events
            if let saveDate = recentSaves[url],
               Date().timeIntervalSince(saveDate) < 0.5 {
                continue
            }

            if event.isDirectory {
                if event.dirCreated || event.dirRemoved || event.dirRenamed {
                    scheduleFullRescan()
                    return
                }
                continue
            }

            let ext = url.pathExtension.lowercased()
            let isIndexable = validExtensions.contains(ext)
            let changed = handleFileEvent(
                event, url: url, isIndexable: isIndexable,
                workspace: workspace, indexContext: indexContext
            )
            if changed { treeChanged = true }
        }

        // No need to manually bump fileTreeVersion here — the
        // fileTree property's didSet already increments it when
        // nodes are added/removed via the in-memory helpers.
    }

    private func scheduleFullRescan() {
        pendingWatcherReloadTask?.cancel()
        pendingWatcherReloadTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            self?.loadFileTree()
        }
    }

    /// Returns true if the file tree was modified.
    private func handleFileEvent(
        _ event: FileEvent,
        url: URL,
        isIndexable: Bool,
        workspace: URL,
        indexContext: IndexContext
    ) -> Bool {
        if event.fileRemoved {
            removeFileFromInMemoryTree(url)
            if isIndexable {
                UnifiedIndexer.removeFile(url, context: indexContext)
            }
            if let tabIdx = openFiles.firstIndex(where: { $0.url == url }) {
                closeTab(at: tabIdx)
            }
            return true
        }

        if event.fileRenamed {
            let exists = FileManager.default.fileExists(atPath: url.path)
            if exists {
                addFileToInMemoryTree(url)
                if isIndexable,
                   let content = try? String(contentsOf: url, encoding: .utf8) {
                    UnifiedIndexer.addFile(
                        url, content: content,
                        workspace: workspace,
                        context: indexContext
                    )
                }
            } else {
                removeFileFromInMemoryTree(url)
                if isIndexable {
                    UnifiedIndexer.removeFile(url, context: indexContext)
                }
            }
            return true
        }

        if event.fileCreated {
            addFileToInMemoryTree(url)
            if isIndexable,
               let content = try? String(contentsOf: url, encoding: .utf8) {
                UnifiedIndexer.addFile(
                    url, content: content,
                    workspace: workspace,
                    context: indexContext
                )
            }
            return true
        }

        if event.fileModified {
            if isIndexable,
               let content = try? String(contentsOf: url, encoding: .utf8) {
                UnifiedIndexer.updateFile(url, content: content, context: indexContext)
            }
            if openFiles.contains(where: { $0.url == url }) {
                reloadOpenDocumentFromDisk(url)
                NotificationCenter.default.post(name: .reloadEditor, object: nil)
            }
            return false
        }

        return false
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
}

// MARK: - File Operations

extension DocumentStore {
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

        try? "# \n".write(to: url, atomically: true, encoding: .utf8)
        loadFileTree()
        open(url)
    }

    func newEmailNote(from emlURL: URL) {
        guard let workspace = workspace else { return }
        guard let emlContent = try? String(
            contentsOf: emlURL, encoding: .utf8
        ) else { return }

        let parsed = EmailParser.parse(emlContent: emlContent)

        let emailsDir = workspace.appendingPathComponent("emails")
        try? FileManager.default.createDirectory(
            at: emailsDir, withIntermediateDirectories: true
        )

        let sanitizedSubject = parsed.subject.replacingOccurrences(
            of: "[/:\\x00-\\x1F\\x7F]",
            with: "-",
            options: .regularExpression
        )

        let datePrefix = parsed.date.isEmpty
            ? "" : "\(parsed.date) "
        let baseName = "\(datePrefix)\(sanitizedSubject)"
            .trimmingCharacters(in: .whitespaces)
        let safeName = baseName.isEmpty ? "Email Note" : baseName

        var fileName = "\(safeName).md"
        var counter = 2
        while FileManager.default.fileExists(
            atPath: emailsDir.appendingPathComponent(fileName).path
        ) {
            fileName = "\(safeName) \(counter).md"
            counter += 1
        }

        let noteURL = emailsDir.appendingPathComponent(fileName)
        let titleText = parsed.subject.isEmpty
            ? "Email Note" : parsed.subject
        let template = """
        # \(titleText)

        **From:** \(parsed.sender)
        **Date:** \(parsed.date)

        ---

        \(parsed.body)
        """
        try? template.write(
            to: noteURL, atomically: true, encoding: .utf8
        )
        loadFileTree()
        open(noteURL)
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
            let content = "# \(sanitized)\n"
            try? content.write(
                to: url, atomically: true, encoding: .utf8
            )
        }
        loadFileTree()
        if openAfter {
            open(url)
        }
    }

    @discardableResult
    func delete(_ url: URL) -> Bool {
        let candidates = Self.deletionCandidates(for: url)

        // Close if open (canonical path match prevents stale tabs)
        if let idx = openFiles.firstIndex(
            where: { openFile in
                candidates.contains { Self.equivalentFileURL(openFile.url, $0) }
            }
        ) {
            closeTab(at: idx)
        }

        switch deleteFromDisk(url, scope: .workspace) {
        case .deleted(let deletedURL):
            resetFileTreeScanState()
            removeFileFromInMemoryTree(deletedURL)
            rebuildIndexesFromCurrentTree()
            scheduleFileTreeReload(delaySeconds: 0.6)
            return true
        case .notFound:
            resetFileTreeScanState()
            removeFileFromInMemoryTree(url)
            rebuildIndexesFromCurrentTree()
            scheduleFileTreeReload(delaySeconds: 0.6)
            return false
        case .failed(let message):
            print("[DocumentStore] Failed to delete \(url.path): \(message)")
            return false
        }
    }

    func requestDelete(_ targetURL: URL, isDirectory: Bool) {
        if isDirectory {
            pendingDeleteTarget = targetURL
            pendingDeleteName = targetURL.lastPathComponent
            pendingDeleteIsDirectory = true
            return
        }

        _ = delete(targetURL)
        pendingDeleteTarget = nil
        pendingDeleteName = ""
        pendingDeleteIsDirectory = false
    }

    func cancelPendingDelete() {
        pendingDeleteTarget = nil
        pendingDeleteName = ""
        pendingDeleteIsDirectory = false
    }

    @discardableResult
    func confirmPendingDelete() -> Bool {
        guard let targetURL = pendingDeleteTarget else { return false }
        let didDelete = delete(targetURL)
        pendingDeleteTarget = nil
        pendingDeleteName = ""
        pendingDeleteIsDirectory = false
        return didDelete
    }

    func promptRename(_ url: URL) {
        renameTarget = url
        renameText = url.lastPathComponent
    }

    func confirmRename() {
        guard let url = renameTarget else { return }
        let newName = renameText.trimmingCharacters(in: .whitespaces)
        guard !newName.isEmpty, newName != url.lastPathComponent else {
            renameTarget = nil
            return
        }
        let newURL = url.deletingLastPathComponent().appendingPathComponent(newName)
        do {
            try FileManager.default.moveItem(at: url, to: newURL)
            if let idx = openFiles.firstIndex(where: { $0.url == url }) {
                openFiles[idx] = Document(url: newURL, content: openFiles[idx].content)
            }
            loadFileTree()
        } catch {}
        renameTarget = nil
    }

    func moveFile(from sourceURL: URL, to destinationFolder: URL) -> URL? {
        let targetURL = destinationFolder.appendingPathComponent(sourceURL.lastPathComponent)
        guard sourceURL != targetURL,
              sourceURL.deletingLastPathComponent() != destinationFolder else { return nil }
        // Prevent moving a folder into itself or its own subtree
        if sourceURL.hasDirectoryPath || (try? sourceURL.resourceValues(
            forKeys: [.isDirectoryKey]
        ).isDirectory) == true {
            let sourcePath = sourceURL.standardizedFileURL.path
            let destPath = destinationFolder.standardizedFileURL.path
            if destPath.hasPrefix(sourcePath) { return nil }
        }
        do {
            try FileManager.default.moveItem(at: sourceURL, to: targetURL)
            if let idx = openFiles.firstIndex(where: { $0.url == sourceURL }) {
                openFiles[idx] = Document(url: targetURL, content: openFiles[idx].content)
            }
            loadFileTree()
            return targetURL
        } catch {
            return nil
        }
    }

    func promptNewFolder(in parent: URL) {
        newFolderParent = parent
        newFolderName = "New Folder"
    }

    func confirmNewFolder() {
        guard let parent = newFolderParent else { return }
        let name = newFolderName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { newFolderParent = nil; return }
        let folderURL = parent.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            expandedFolders.insert(folderURL)
            loadFileTree()
        } catch {}
        newFolderParent = nil
    }
    func pickWorkspace() {
        showWorkspacePicker = true
    }
}

// MARK: - UI State Methods

extension DocumentStore {
    func toggleSidebar() {
        columnVisibility = columnVisibility == .all ? .detailOnly : .all
    }

    func toggleBacklinks() {
        showBacklinks.toggle()
    }

    func showFileLauncherModal() {
        activeModal = .fileLauncher
    }

    func showLinkCaptureModal() {
        activeModal = .linkCapture
    }

    func showMeetingNoteModal() {
        activeModal = .meetingNote
    }

    func showTagBrowserModal(tag: String? = nil) {
        activeModal = .tagBrowser(tag)
    }

    func showPeopleBrowserModal(person: String? = nil) {
        activeModal = .peopleBrowser(person)
    }

    func selectSearchTabWithTagFilter(tag: String? = nil) {
        guard workspace != nil else { return }
        detailMode = .search
        dedicatedSearch.initialTagFocusRequested = true
        if let tag, !tag.isEmpty {
            dedicatedSearch.tagFilterText = tag
        }
    }

    func showKanbanModal() {
        detailMode = detailMode == .kanban ? .editor : .kanban
    }

    // MARK: - Kanban Board

    static let kanbanColumns = ["Ideas", "Drafts", "Ready for Review"]
    static let kanbanArchive = "Archive"

    func bootstrapKanbanFolders() {
        guard let workspace else { return }
        let allFolders = Self.kanbanColumns + [Self.kanbanArchive]
        for folder in allFolders {
            let url = workspace.appendingPathComponent(folder)
            if !FileManager.default.fileExists(atPath: url.path) {
                do {
                    try FileManager.default.createDirectory(
                        at: url, withIntermediateDirectories: true
                    )
                } catch {
                    print("Error creating Kanban folder at \(url.path): \(error.localizedDescription)")
                }
            }
        }
        loadFileTree()
    }

    func kanbanFiles(in folderName: String) -> [URL] {
        guard let workspace else { return [] }
        let folder = workspace.appendingPathComponent(folderName)
        let contents: [URL]
        do {
            contents = try FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: nil
            )
        } catch {
            print("Error reading Kanban folder \(folderName): \(error.localizedDescription)")
            return []
        }
        let validExtensions: Set<String> = ["md", "txt"]
        return contents
            .filter { validExtensions.contains($0.pathExtension.lowercased()) }
            .sorted {
                $0.lastPathComponent.localizedCaseInsensitiveCompare(
                    $1.lastPathComponent
                ) == .orderedAscending
            }
    }

    func showImageDetailModal(_ url: URL) {
        imageDetailURL = url
    }
}

extension DocumentStore {
    @discardableResult
    func deleteMedia(_ mediaURL: URL) -> Bool {
        switch deleteFromDisk(mediaURL, scope: .media) {
        case .deleted(let deletedURL):
            resetFileTreeScanState()
            mediaFiles.removeAll { itemURL in
                Self.equivalentFileURL(itemURL, deletedURL)
                    || Self.equivalentFileURL(itemURL, mediaURL)
            }
            scheduleFileTreeReload(delaySeconds: 0.6)
            return true
        case .notFound:
            resetFileTreeScanState()
            mediaFiles.removeAll { itemURL in
                Self.equivalentFileURL(itemURL, mediaURL)
            }
            scheduleFileTreeReload(delaySeconds: 0.6)
            return false
        case .failed(let message):
            print("[DocumentStore] Failed to delete media \(mediaURL.path): \(message)")
            return false
        }
    }

    static func shouldApplyFileTreeScanResult(
        activeScanID: UUID,
        scanID: UUID,
        currentWorkspace: URL?,
        scanWorkspace: URL
    ) -> Bool {
        guard activeScanID == scanID else { return false }
        guard let currentWorkspace else { return false }
        return currentWorkspace.standardizedFileURL.path == scanWorkspace.standardizedFileURL.path
    }
}

private extension DocumentStore {
    func resetFileTreeScanState() {
        fileTreeLoadTask?.cancel()
        pendingFileTreeReloadTask?.cancel()
        pendingWatcherReloadTask?.cancel()
        isFileTreeScanRunning = false
        fileTreeRescanRequested = false
        activeFileTreeScanID = UUID()
    }

    func deleteFromDisk(_ sourceURL: URL, scope: DiskDeleteScope) -> DiskDeleteResult {
        guard isDeletionTargetInAllowedScope(sourceURL, scope: scope) else {
            return .failed("Refusing to delete outside workspace scope")
        }

        let candidates = Self.deletionCandidates(for: sourceURL)
        var didFindExistingCandidate = false
        var latestErrorMessage: String?
        var visitedPaths: Set<String> = []

        for candidateURL in candidates {
            let normalizedPath = candidateURL.standardizedFileURL.path
            guard visitedPaths.insert(normalizedPath).inserted else { continue }
            guard FileManager.default.fileExists(atPath: candidateURL.path) else { continue }
            didFindExistingCandidate = true

            if deleteFilesystemEntry(at: candidateURL) {
                return .deleted(candidateURL)
            }

            latestErrorMessage = "Unable to remove \(candidateURL.path)"
        }

        if didFindExistingCandidate {
            return .failed(latestErrorMessage ?? "Unable to remove file")
        }
        return .notFound
    }

    func deleteFilesystemEntry(at url: URL) -> Bool {
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            if !FileManager.default.fileExists(atPath: url.path) {
                return true
            }
        } catch {
            print("[DocumentStore] Failed to trash \(url.path): \(error)")
        }

        do {
            try FileManager.default.removeItem(at: url)
            return !FileManager.default.fileExists(atPath: url.path)
        } catch {
            print("[DocumentStore] Failed to remove \(url.path): \(error)")
        }

        return false
    }

    func isDeletionTargetInAllowedScope(_ sourceURL: URL, scope: DiskDeleteScope) -> Bool {
        guard let workspace else { return false }

        let workspaceURL = workspace.standardizedFileURL
        let canonicalWorkspaceURL = Self.canonicalFileURL(workspace)
        let mediaURL = workspaceURL.appendingPathComponent("media", isDirectory: true)
        let canonicalMediaURL = Self.canonicalFileURL(mediaURL)

        let allowedRoots: [String]
        switch scope {
        case .workspace:
            allowedRoots = [
                workspaceURL.path,
                canonicalWorkspaceURL.path
            ]
        case .media:
            allowedRoots = [
                mediaURL.path,
                canonicalMediaURL.path
            ]
        }

        let uniqueRoots = Array(Set(allowedRoots))
        let targetPaths = [
            sourceURL.standardizedFileURL.path,
            Self.canonicalFileURL(sourceURL).path
        ]
        let uniqueTargetPaths = Array(Set(targetPaths))

        for targetPath in uniqueTargetPaths {
            guard uniqueRoots.contains(where: { rootPath in
                Self.pathIsWithinDirectory(targetPath, directoryPath: rootPath)
            }) else {
                return false
            }
        }

        return true
    }

    static func pathIsWithinDirectory(_ path: String, directoryPath: String) -> Bool {
        path == directoryPath || path.hasPrefix(directoryPath + "/")
    }
}
