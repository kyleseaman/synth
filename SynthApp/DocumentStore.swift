import SwiftUI
import Combine
import AppKit
import ImageIO

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

final class WorkspaceImageLoader {
    static let shared = WorkspaceImageLoader()

    private let decodeQueue = DispatchQueue(
        label: "synth.workspace-image-loader.decode",
        qos: .userInitiated,
        attributes: .concurrent
    )
    private let stateQueue = DispatchQueue(label: "synth.workspace-image-loader.state")
    private let imageCache = NSCache<NSString, NSImage>()
    private var inFlight: [NSString: [(NSImage?) -> Void]] = [:]

    private init() {}

    func cachedImage(at imageURL: URL, maxSize: NSSize) -> NSImage? {
        let cacheKey = key(for: imageURL, maxSize: maxSize)
        return stateQueue.sync {
            imageCache.object(forKey: cacheKey)
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
                    self.imageCache.setObject(decoded, forKey: cacheKey)
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

    private func key(for imageURL: URL, maxSize: NSSize) -> NSString {
        let width = Int(maxSize.width.rounded())
        let height = Int(maxSize.height.rounded())
        return "\(imageURL.path)#\(width)x\(height)" as NSString
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
    @Published var isMediaTabSelected = false
    @Published var mediaFiles: [URL] = []

    let noteIndex = NoteIndex()
    let backlinkIndex = BacklinkIndex()
    let tagIndex = TagIndex()
    let peopleIndex = PeopleIndex()
    let mcpServer = MCPServerManager()

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
            isMediaTabSelected = false
            mediaFiles = MediaManager.screenshotURLs(in: url)
        }
        startWatching()
        loadKiroConfig()
        checkKiroSetup()
        mcpServer.start(workspace: url)
    }

    func loadFileTree() {
        guard let workspace = workspace else { return }
        Task.detached(priority: .userInitiated) {
            let tree = FileTreeNode.scan(workspace)
            let media = MediaManager.screenshotURLs(in: workspace)
            await MainActor.run {
                self.fileTree = tree
                self.noteIndex.rebuild(from: tree, workspace: workspace)
                self.mediaFiles = media
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

    func openDailyNote() {
        guard let workspace = workspace else { return }
        guard let url = DailyNoteResolver.resolve("today", workspace: workspace) else { return }
        DailyNoteResolver.ensureExists(at: url)
        loadFileTree()
        open(url)
    }

    func open(_ url: URL) {
        isLinksTabSelected = false
        isMediaTabSelected = false
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
        isMediaTabSelected = false
    }

    func selectLinksTab() {
        isLinksTabSelected = true
        isMediaTabSelected = false
    }

    func selectMediaTab() {
        isLinksTabSelected = false
        isMediaTabSelected = true
    }

    var currentDocumentURL: URL? {
        guard currentIndex >= 0, currentIndex < openFiles.count else { return nil }
        return openFiles[currentIndex].url
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

        try? "".write(to: url, atomically: true, encoding: .utf8)
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
