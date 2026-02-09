import SwiftUI
import AppKit
import ImageIO
import Observation
import CoreServices

struct StoredMediaAsset {
    let fileURL: URL
    let relativePath: String
}

enum MediaManagerError: Error {
    case imageEncodingFailed
}

enum MediaManager {
    private static let supportedExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "gif", "webp"
    ]

    private static let filenameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    static func saveScreenshotImage(
        _ image: NSImage,
        workspaceURL: URL,
        noteURL: URL,
        now: Date = Date()
    ) throws -> StoredMediaAsset {
        let fileManager = FileManager.default
        let mediaDirectory = workspaceURL.appendingPathComponent("media", isDirectory: true)
        try fileManager.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)

        guard let imageData = image.pngDataRepresentation else {
            throw MediaManagerError.imageEncodingFailed
        }

        let timestamp = filenameFormatter.string(from: now)
        let baseName = "screenshot-\(timestamp)"
        var suffixNumber = 1
        var fileName = "\(baseName).png"
        var fileURL = mediaDirectory.appendingPathComponent(fileName)

        while fileManager.fileExists(atPath: fileURL.path) {
            suffixNumber += 1
            fileName = "\(baseName)-\(suffixNumber).png"
            fileURL = mediaDirectory.appendingPathComponent(fileName)
        }

        try imageData.write(to: fileURL, options: [.atomic])

        let noteDirectory = noteURL.deletingLastPathComponent()
        let relativePath = relativePath(from: noteDirectory, to: fileURL)
        return StoredMediaAsset(fileURL: fileURL, relativePath: relativePath)
    }

    static func screenshotURLs(in workspaceURL: URL) -> [URL] {
        let mediaDirectory = workspaceURL.appendingPathComponent("media", isDirectory: true)
        let properties: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey]

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: mediaDirectory,
            includingPropertiesForKeys: properties
        ) else { return [] }

        return contents
            .filter { mediaURL in
                guard isSupportedImageFile(mediaURL) else { return false }
                return mediaURL.deletingPathExtension()
                    .lastPathComponent
                    .lowercased()
                    .contains("screenshot")
            }
            .sorted { firstURL, secondURL in
                let firstValues = try? firstURL.resourceValues(forKeys: [.contentModificationDateKey])
                let secondValues = try? secondURL.resourceValues(forKeys: [.contentModificationDateKey])
                let firstDate = firstValues?.contentModificationDate ?? .distantPast
                let secondDate = secondValues?.contentModificationDate ?? .distantPast
                return firstDate > secondDate
            }
    }

    static func relativePath(from baseDirectoryURL: URL, to destinationURL: URL) -> String {
        let baseParts = baseDirectoryURL.standardizedFileURL.pathComponents
        let destinationParts = destinationURL.standardizedFileURL.pathComponents
        let sharedCount = sharedPathPrefixCount(first: baseParts, second: destinationParts)

        let parentSegments = Array(repeating: "..", count: baseParts.count - sharedCount)
        let destinationSegments = Array(destinationParts.dropFirst(sharedCount))
        let fullSegments = parentSegments + destinationSegments
        return fullSegments.isEmpty ? "." : fullSegments.joined(separator: "/")
    }

    static func resolvedImageURL(from path: String, baseDirectoryURL: URL?) -> URL? {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return nil }

        if let absoluteURL = URL(string: trimmedPath), absoluteURL.scheme != nil {
            return absoluteURL
        }

        guard let baseDirectoryURL else { return nil }
        return URL(fileURLWithPath: trimmedPath, relativeTo: baseDirectoryURL).standardizedFileURL
    }

    static func isSupportedImageFile(_ mediaURL: URL) -> Bool {
        let ext = mediaURL.pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else { return false }
        let isDirectory = (try? mediaURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        return !isDirectory
    }

    private static func sharedPathPrefixCount(first: [String], second: [String]) -> Int {
        let countLimit = min(first.count, second.count)
        var sharedCount = 0
        while sharedCount < countLimit && first[sharedCount] == second[sharedCount] {
            sharedCount += 1
        }
        return sharedCount
    }
}

private extension NSImage {
    var pngDataRepresentation: Data? {
        guard let tiffData = tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData) else { return nil }
        return bitmapRep.representation(using: .png, properties: [:])
    }
}

private final class WorkspaceWatcherContext {
    weak var store: DocumentStore?

    init(store: DocumentStore) {
        self.store = store
    }
}

private let watcherContextRetain: CFAllocatorRetainCallBack = { info in
    guard let info else { return nil }
    let rawPointer = UnsafeMutableRawPointer(mutating: info)
    let context = Unmanaged<WorkspaceWatcherContext>.fromOpaque(rawPointer)
    return UnsafeRawPointer(context.retain().toOpaque())
}

private let watcherContextRelease: CFAllocatorReleaseCallBack = { info in
    guard let info else { return }
    let rawPointer = UnsafeMutableRawPointer(mutating: info)
    Unmanaged<WorkspaceWatcherContext>.fromOpaque(rawPointer).release()
}

private enum DiskDeleteResult {
    case deleted(URL)
    case notFound
    case failed(String)
}

private enum DiskDeleteScope {
    case workspace
    case media
}

final class WorkspaceImageLoader: @unchecked Sendable {
    static let shared = WorkspaceImageLoader()

    private let decodeQueue = DispatchQueue(
        label: "synth.workspace-image-loader.decode",
        qos: .userInitiated,
        attributes: .concurrent
    )
    private let stateQueue = DispatchQueue(label: "synth.workspace-image-loader.state")
    private let imageCache = NSCache<NSString, NSImage>()
    private var inFlight: [String: [(NSImage?) -> Void]] = [:]

    private init() {}

    func cachedImage(at imageURL: URL, maxSize: NSSize) -> NSImage? {
        let cacheKey = key(for: imageURL, maxSize: maxSize)
        return stateQueue.sync {
            imageCache.object(forKey: cacheKey as NSString)
        }
    }

    func loadImage(at imageURL: URL, maxSize: NSSize, completion: @escaping (NSImage?) -> Void) {
        let cacheKey = key(for: imageURL, maxSize: maxSize)

        if let cached = cachedImage(at: imageURL, maxSize: maxSize) {
            completion(cached)
            return
        }

        var shouldStartDecode = false
        stateQueue.sync {
            if var callbacks = inFlight[cacheKey] {
                callbacks.append(completion)
                inFlight[cacheKey] = callbacks
            } else {
                inFlight[cacheKey] = [completion]
                shouldStartDecode = true
            }
        }

        guard shouldStartDecode else { return }

        decodeQueue.async {
            let decoded = Self.decodeImage(at: imageURL, maxSize: maxSize)

            let callbacks: [(NSImage?) -> Void] = self.stateQueue.sync {
                if let decoded {
                    self.imageCache.setObject(decoded, forKey: cacheKey as NSString)
                }
                return self.inFlight.removeValue(forKey: cacheKey) ?? []
            }

            DispatchQueue.main.async {
                callbacks.forEach { callback in
                    callback(decoded)
                }
            }
        }
    }

    private func key(for imageURL: URL, maxSize: NSSize) -> String {
        let width = Int(maxSize.width.rounded())
        let height = Int(maxSize.height.rounded())
        return "\(imageURL.path)#\(width)x\(height)"
    }

    private static func decodeImage(at imageURL: URL, maxSize: NSSize) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil) else { return nil }

        let maxPixelSize = max(Int(maxSize.width), Int(maxSize.height))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(maxPixelSize, 1),
            kCGImageSourceShouldCacheImmediately: true
        ]

        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else { return nil }

        let imageSize = NSSize(width: thumbnail.width, height: thumbnail.height)
        return NSImage(cgImage: thumbnail, size: imageSize)
    }
}

enum DetailViewMode: Equatable {
    case editor
    case dailyNotes
    case links
    case media
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
    var needsKiroSetup = false
    var detailMode: DetailViewMode = .editor
    var mediaFiles: [URL] = []

    // MARK: - Centralized UI State
    var columnVisibility: NavigationSplitViewVisibility = .all
    var activeModal: ActiveModal?
    var imageDetailURL: URL?
    var showBacklinks = true
    var dailyDateScrollTarget: String?
    var renameTarget: URL?
    var renameText: String = ""
    var pendingDeleteTarget: URL?
    var pendingDeleteName: String = ""
    var pendingDeleteIsDirectory = false
    var showWorkspacePicker = false

    let noteIndex = NoteIndex()
    let backlinkIndex = BacklinkIndex()
    let tagIndex = TagIndex()
    let peopleIndex = PeopleIndex()
    let dailyNoteManager = DailyNoteManager()
    let mcpServer = MCPServerManager()

    private static let meetingDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    @ObservationIgnored private var chatStates: [URL: DocumentChatState] = [:]
    @ObservationIgnored private let maxRecentFiles = 20
    @ObservationIgnored private var fileEventStream: FSEventStreamRef?
    @ObservationIgnored private var watcherContext: WorkspaceWatcherContext?
    @ObservationIgnored private var fileTreeLoadTask: Task<Void, Never>?
    @ObservationIgnored private var pendingFileTreeReloadTask: Task<Void, Never>?
    @ObservationIgnored private var pendingWatcherReloadTask: Task<Void, Never>?
    @ObservationIgnored private var isFileTreeScanRunning = false
    @ObservationIgnored private var fileTreeRescanRequested = false
    @ObservationIgnored private var activeFileTreeScanID = UUID()

    init() {
        loadRecentFiles()
        dailyNoteManager.onSave = { [weak self] url, content in
            self?.backlinkIndex.updateFile(url, content: content)
            self?.tagIndex.updateFile(url, content: content)
            self?.peopleIndex.updateFile(url, content: content)
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

    private func startWatching() {
        guard let workspace = workspace else { return }
        stopWatching()

        let context = WorkspaceWatcherContext(store: self)
        watcherContext = context

        var streamContext = FSEventStreamContext(
            version: 0,
            info: UnsafeMutableRawPointer(Unmanaged.passRetained(context).toOpaque()),
            retain: watcherContextRetain,
            release: watcherContextRelease,
            copyDescription: nil
        )

        let watchPaths = [workspace.path] as CFArray
        let streamFlags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagNoDefer
                | kFSEventStreamCreateFlagUseCFTypes
        )

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            Self.workspaceEventCallback,
            &streamContext,
            watchPaths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.2,
            streamFlags
        ) else {
            return
        }

        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        if FSEventStreamStart(stream) {
            fileEventStream = stream
        } else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            watcherContext = nil
        }
    }

    private func stopWatching() {
        guard let stream = fileEventStream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        fileEventStream = nil
        watcherContext = nil
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
            pendingDeleteTarget = nil
            pendingDeleteName = ""
            pendingDeleteIsDirectory = false
        }
        startWatching()
        loadKiroConfig()
        checkKiroSetup()
        dailyNoteManager.ensureFutureDays(workspace: url)
        mcpServer.start(workspace: url)
        loadFileTree()
        // Clean orphaned media only on workspace open, not every scan
        Task(priority: .utility) { [weak self] in
            let removed = Self.cleanOrphanedMedia(
                mediaFiles: MediaManager.screenshotURLs(in: url),
                workspace: url
            )
            if !removed.isEmpty {
                await MainActor.run {
                    self?.mediaFiles.removeAll { removed.contains($0) }
                }
            }
        }
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

    private static func scanWorkspace(at workspace: URL) -> WorkspaceScanResult {
        let tree = FileTreeNode.scan(workspace)
        let media = MediaManager.screenshotURLs(in: workspace)
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
            let scanResult = Self.scanWorkspace(at: workspace)
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
        noteIndex.rebuild(from: scanResult.tree, workspace: workspace)
        mediaFiles = scanResult.media
        backlinkIndex.rebuild(fileTree: scanResult.tree)
        tagIndex.rebuild(fileTree: scanResult.tree)
        peopleIndex.rebuild(fileTree: scanResult.tree)
    }

    private func rebuildIndexesFromCurrentTree() {
        guard let workspace else { return }
        noteIndex.rebuild(from: fileTree, workspace: workspace)
        backlinkIndex.rebuild(fileTree: fileTree)
        tagIndex.rebuild(fileTree: fileTree)
        peopleIndex.rebuild(fileTree: fileTree)
    }

    @discardableResult
    private static func cleanOrphanedMedia(
        mediaFiles: [URL], workspace: URL
    ) -> Set<URL> {
        var removed: Set<URL> = []
        for mediaURL in mediaFiles {
            let filename = mediaURL.lastPathComponent
            var isReferenced = false
            let enumerator = FileManager.default.enumerator(
                at: workspace,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            while let fileURL = enumerator?.nextObject() as? URL {
                guard fileURL.pathExtension == "md",
                      let content = try? String(
                          contentsOf: fileURL, encoding: .utf8
                      ),
                      content.contains(filename)
                else { continue }
                isReferenced = true
                break
            }
            if !isReferenced {
                try? FileManager.default.trashItem(
                    at: mediaURL, resultingItemURL: nil
                )
                removed.insert(mediaURL)
            }
        }
        return removed
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

    func open(_ url: URL) {
        saveAll()
        detailMode = .editor
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
        detailMode = .editor
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
        guard let workspace else { return [] }
        var results: [(title: String, url: URL)] = []
        let enumerator = FileManager.default.enumerator(
            at: workspace,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "md",
                  let content = try? String(
                      contentsOf: fileURL, encoding: .utf8
                  ),
                  content.contains(mediaFilename)
            else { continue }
            let title = fileURL.deletingPathExtension()
                .lastPathComponent
            results.append((title: title, url: fileURL))
        }
        return results
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
        noteIndex.updateFile(reloadedURL, content: reloadedContent)
        backlinkIndex.updateFile(reloadedURL, content: reloadedContent)
        tagIndex.updateFile(reloadedURL, content: reloadedContent)
        peopleIndex.updateFile(reloadedURL, content: reloadedContent)
        return true
    }

    func savePastedImageToMedia(_ image: NSImage, noteURL: URL) -> String? {
        guard let workspace else { return nil }
        guard let savedMedia = try? MediaManager.saveScreenshotImage(
            image,
            workspaceURL: workspace,
            noteURL: noteURL
        ) else { return nil }
        loadFileTree()
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

        // Incremental index updates after save
        let savedContent = openFiles[currentIndex].content.string
        let savedURL = openFiles[currentIndex].url
        noteIndex.updateFile(savedURL, content: savedContent)
        backlinkIndex.updateFile(savedURL, content: savedContent)
        tagIndex.updateFile(savedURL, content: savedContent)
        peopleIndex.updateFile(savedURL, content: savedContent)
    }

    func saveAll() {
        var didRename = false
        for index in openFiles.indices where openFiles[index].isDirty {
            let doc = openFiles[index]
            try? doc.save(doc.content)

            // Rename Untitled files based on first line
            if doc.url.lastPathComponent.hasPrefix("Untitled") {
                if let newURL = renamedURL(for: doc) {
                    try? FileManager.default.moveItem(at: doc.url, to: newURL)
                    openFiles[index] = Document(url: newURL, content: doc.content)
                    didRename = true
                }
            }
            openFiles[index].isDirty = false

            // Incremental index updates
            let savedURL = openFiles[index].url
            let savedContent = openFiles[index].content.string
            noteIndex.updateFile(savedURL, content: savedContent)
            backlinkIndex.updateFile(savedURL, content: savedContent)
            tagIndex.updateFile(savedURL, content: savedContent)
            peopleIndex.updateFile(savedURL, content: savedContent)
        }
        if didRename { loadFileTree() }
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

    private func handleWorkspaceEvents(_ eventPaths: [String]) {
        guard let workspace else { return }
        let workspacePath = workspace.standardizedFileURL.path
        let shouldRefresh = eventPaths.isEmpty || eventPaths.contains { eventPath in
            Self.shouldRefreshSidebar(forWorkspace: workspacePath, eventPath: eventPath)
        }
        guard shouldRefresh else { return }

        pendingWatcherReloadTask?.cancel()
        pendingWatcherReloadTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            self?.loadFileTree()
        }
    }

    static func shouldRefreshSidebar(forWorkspace workspacePath: String, eventPath: String) -> Bool {
        let normalizedWorkspace = URL(fileURLWithPath: workspacePath).standardizedFileURL.path
        let normalizedEvent = URL(fileURLWithPath: eventPath).standardizedFileURL.path
        guard normalizedEvent.hasPrefix(normalizedWorkspace) else { return false }

        let relativePath = String(normalizedEvent.dropFirst(normalizedWorkspace.count))
        if relativePath == "/.kiro" || relativePath.hasPrefix("/.kiro/") {
            return false
        }
        if relativePath == "/daily" || relativePath.hasPrefix("/daily/") {
            return false
        }
        if relativePath == "/media" || relativePath.hasPrefix("/media/") {
            return false
        }
        return true
    }

    private static let workspaceEventCallback: FSEventStreamCallback = { _, clientInfo, _, eventPathsPointer, _, _ in
        guard let clientInfo else { return }
        let context = Unmanaged<WorkspaceWatcherContext>
            .fromOpaque(clientInfo)
            .takeUnretainedValue()
        guard let store = context.store else { return }

        let eventPathArray = Unmanaged<CFArray>
            .fromOpaque(eventPathsPointer)
            .takeUnretainedValue() as NSArray
        let eventPaths = eventPathArray.compactMap { $0 as? String }

        store.handleWorkspaceEvents(eventPaths)
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

        try? "# \n".write(to: url, atomically: true, encoding: .utf8)
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

    func pickWorkspace() {
        showWorkspacePicker = true
    }

    // MARK: - UI State Methods

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
