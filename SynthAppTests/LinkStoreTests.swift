import XCTest
import AppKit
@testable import Synth

final class LinkStoreTests: XCTestCase {
    private var storage: UserDefaults?
    private let storageSuite = "LinkStoreTests"
    private let storageKey = "tests.savedLinks"

    override func setUp() {
        super.setUp()
        storage = UserDefaults(suiteName: storageSuite)
        storage?.removePersistentDomain(forName: storageSuite)
    }

    override func tearDown() {
        storage?.removePersistentDomain(forName: storageSuite)
        storage = nil
        super.tearDown()
    }

    func testAddLinkNormalizesAndPersists() {
        guard let storage = storage else {
            XCTFail("Missing storage")
            return
        }

        let store = LinkStore(storage: storage, storageKey: storageKey)
        let created = store.addLink("example.com")

        XCTAssertNotNil(created)
        XCTAssertEqual(store.links.count, 1)
        XCTAssertEqual(store.links.first?.urlString, "https://example.com")

        let reloaded = LinkStore(storage: storage, storageKey: storageKey)
        XCTAssertEqual(reloaded.links.count, 1)
        XCTAssertEqual(reloaded.links.first?.urlString, "https://example.com")
    }

    func testAddLinkRejectsEmpty() {
        guard let storage = storage else {
            XCTFail("Missing storage")
            return
        }

        let store = LinkStore(storage: storage, storageKey: storageKey)
        let created = store.addLink("   ")

        XCTAssertNil(created)
        XCTAssertTrue(store.links.isEmpty)
    }

    func testAddLinkDeduplicatesAndMovesToTop() {
        guard let storage = storage else {
            XCTFail("Missing storage")
            return
        }

        let store = LinkStore(storage: storage, storageKey: storageKey)
        let first = store.addLink("https://example.com")
        let second = store.addLink("https://another.com")
        let duplicate = store.addLink("example.com")

        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        XCTAssertNotNil(duplicate)
        XCTAssertEqual(store.links.count, 2)
        XCTAssertEqual(store.links.first?.urlString, "https://example.com")
        XCTAssertEqual(store.links.first?.identifier, first?.identifier)
    }

    func testRemoveLinkPersistsAfterReload() {
        guard let storage = storage else {
            XCTFail("Missing storage")
            return
        }

        let store = LinkStore(storage: storage, storageKey: storageKey)
        _ = store.addLink("https://first.example")
        guard let secondLink = store.addLink("https://second.example") else {
            XCTFail("Second link was not created")
            return
        }

        store.removeLink(identifier: secondLink.identifier)
        XCTAssertEqual(store.links.count, 1)
        XCTAssertEqual(store.links.first?.urlString, "https://first.example")

        let reloaded = LinkStore(storage: storage, storageKey: storageKey)
        XCTAssertEqual(reloaded.links.count, 1)
        XCTAssertEqual(reloaded.links.first?.urlString, "https://first.example")
    }

    func testNormalizeSupportsHttpAndRejectsInvalidHosts() {
        XCTAssertEqual(
            LinkStore.normalize("http://example.com/path"),
            "http://example.com/path"
        )
        XCTAssertNil(LinkStore.normalize("mailto:test@example.com"))
        XCTAssertNil(LinkStore.normalize("https:///missing-host"))
        XCTAssertNil(LinkStore.normalize("   "))
    }

    func testLoadIgnoresCorruptStoredData() {
        guard let storage = storage else {
            XCTFail("Missing storage")
            return
        }

        storage.set(Data("invalid json".utf8), forKey: storageKey)
        let store = LinkStore(storage: storage, storageKey: storageKey)

        XCTAssertTrue(store.links.isEmpty)
    }
}

final class MediaManagerTests: XCTestCase {
    func testSaveScreenshotStoresInsideMediaAndReturnsRelativePath() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let notesDirectory = temporaryRoot.appendingPathComponent("notes", isDirectory: true)
        try FileManager.default.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
        let noteURL = notesDirectory.appendingPathComponent("daily.md")
        try "".write(to: noteURL, atomically: true, encoding: .utf8)

        let image = makeTestImage()
        let nowDate = Date(timeIntervalSince1970: 1_736_000_000)
        let savedMedia = try MediaManager.saveScreenshotImage(
            image,
            workspaceURL: temporaryRoot,
            noteURL: noteURL,
            now: nowDate
        )

        XCTAssertTrue(savedMedia.fileURL.path.hasPrefix(temporaryRoot.path))
        XCTAssertEqual(savedMedia.fileURL.deletingLastPathComponent().lastPathComponent, "media")
        XCTAssertEqual(savedMedia.fileURL.pathExtension.lowercased(), "png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: savedMedia.fileURL.path))
        XCTAssertTrue(savedMedia.relativePath.hasPrefix("../media/"))
    }

    func testSaveScreenshotAddsCounterWhenFilenameExists() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let noteURL = temporaryRoot.appendingPathComponent("note.md")
        try "".write(to: noteURL, atomically: true, encoding: .utf8)

        let image = makeTestImage()
        let nowDate = Date(timeIntervalSince1970: 1_736_000_000)
        let firstSave = try MediaManager.saveScreenshotImage(
            image,
            workspaceURL: temporaryRoot,
            noteURL: noteURL,
            now: nowDate
        )
        let secondSave = try MediaManager.saveScreenshotImage(
            image,
            workspaceURL: temporaryRoot,
            noteURL: noteURL,
            now: nowDate
        )

        XCTAssertNotEqual(firstSave.fileURL.lastPathComponent, secondSave.fileURL.lastPathComponent)
        XCTAssertTrue(secondSave.fileURL.lastPathComponent.contains("-2"))
        XCTAssertTrue(secondSave.relativePath.hasPrefix("media/"))
    }

    private func makeTestImage() -> NSImage {
        let imageSize = NSSize(width: 16, height: 16)
        let image = NSImage(size: imageSize)
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: imageSize)).fill()
        image.unlockFocus()
        return image
    }
}

final class NoteIndexSearchTests: XCTestCase {
    func testSearchHandlesTypoInTitleUsingFuzzyMatching() throws {
        let workspaceURL = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspaceURL) }

        try write(
            "Architecture Decisions.md",
            content: """
            # Architecture Decisions

            Notes on design and implementation tradeoffs.
            """,
            in: workspaceURL
        )
        try write(
            "Groceries.md",
            content: """
            # Groceries

            Apples, rice, and tea.
            """,
            in: workspaceURL
        )

        let noteIndex = NoteIndex()
        noteIndex.rebuild(from: FileTreeNode.scan(workspaceURL), workspace: workspaceURL)
        let results = noteIndex.search("archtecture")

        XCTAssertEqual(results.first?.title, "Architecture Decisions")
    }

    func testSearchMatchesSemanticSynonymsInContent() throws {
        let workspaceURL = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspaceURL) }

        try write(
            "Team Catchup.md",
            content: """
            # Team Catchup

            A concise summary of product updates and blockers.
            """,
            in: workspaceURL
        )
        try write(
            "Cooking.md",
            content: """
            # Cooking

            Braise onions until golden.
            """,
            in: workspaceURL
        )

        let noteIndex = NoteIndex()
        noteIndex.rebuild(from: FileTreeNode.scan(workspaceURL), workspace: workspaceURL)
        let results = noteIndex.search("status recap")

        XCTAssertEqual(results.first?.title, "Team Catchup")
    }

    func testSearchReturnsPreviewSnippetFromMatchingContent() throws {
        let workspaceURL = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspaceURL) }

        try write(
            "Search Ideas.md",
            content: """
            # Search Ideas

            Neural search makes retrieval smarter for long-form notes.
            Keep the preview focused around matching terms.
            """,
            in: workspaceURL
        )

        let noteIndex = NoteIndex()
        noteIndex.rebuild(from: FileTreeNode.scan(workspaceURL), workspace: workspaceURL)
        let results = noteIndex.search("neural retrieval")

        XCTAssertEqual(results.first?.title, "Search Ideas")
        XCTAssertTrue(results.first?.preview.contains("Neural search makes retrieval smarter") == true)
    }

    func testSearchSupportsTagFilterSyntax() throws {
        let workspaceURL = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspaceURL) }

        try write(
            "Roadmap.md",
            content: """
            # Roadmap

            #project Q3 milestones and rollout plan.
            """,
            in: workspaceURL
        )
        try write(
            "Journal.md",
            content: """
            # Journal

            Personal notes and reflections.
            """,
            in: workspaceURL
        )

        let noteIndex = NoteIndex()
        noteIndex.rebuild(from: FileTreeNode.scan(workspaceURL), workspace: workspaceURL)
        let results = noteIndex.search("plan tag:project")

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.title, "Roadmap")
    }

    func testSearchSupportsPersonFilterSyntax() throws {
        let workspaceURL = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspaceURL) }

        try write(
            "Standup.md",
            content: """
            # Standup

            Follow up with @Alex on integration tests.
            """,
            in: workspaceURL
        )
        try write(
            "Errands.md",
            content: """
            # Errands

            Pick up groceries.
            """,
            in: workspaceURL
        )

        let noteIndex = NoteIndex()
        noteIndex.rebuild(from: FileTreeNode.scan(workspaceURL), workspace: workspaceURL)
        let results = noteIndex.search("person:alex")

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.title, "Standup")
    }

    func testSearchSupportsPathFilterSyntax() throws {
        let workspaceURL = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspaceURL) }

        let meetingsFolder = workspaceURL.appendingPathComponent("meetings", isDirectory: true)
        try FileManager.default.createDirectory(at: meetingsFolder, withIntermediateDirectories: true)
        try write(
            "Weekly.md",
            content: """
            # Weekly

            Team status update and blockers.
            """,
            at: meetingsFolder
        )
        try write(
            "Random.md",
            content: """
            # Random

            Team status update and blockers.
            """,
            in: workspaceURL
        )

        let noteIndex = NoteIndex()
        noteIndex.rebuild(from: FileTreeNode.scan(workspaceURL), workspace: workspaceURL)
        let results = noteIndex.search("status path:meetings")

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.title, "Weekly")
    }

    func testSearchSupportsQuotedPhraseMatching() throws {
        let workspaceURL = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspaceURL) }

        try write(
            "Alpha.md",
            content: """
            # Alpha

            The exact phrase appears here: resilient search pipeline.
            """,
            in: workspaceURL
        )
        try write(
            "Beta.md",
            content: """
            # Beta

            These words are separate and not adjacent.
            """,
            in: workspaceURL
        )

        let noteIndex = NoteIndex()
        noteIndex.rebuild(from: FileTreeNode.scan(workspaceURL), workspace: workspaceURL)
        let results = noteIndex.search("\"resilient search pipeline\"")

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.title, "Alpha")
    }

    private func makeWorkspace() throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        return rootURL
    }

    private func write(_ name: String, content: String, in workspaceURL: URL) throws {
        let fileURL = workspaceURL.appendingPathComponent(name)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func write(_ name: String, content: String, at folderURL: URL) throws {
        let fileURL = folderURL.appendingPathComponent(name)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}

final class ACPProtocolAdapterTests: XCTestCase {
    func testSessionUpdateMethodDetectionSupportsLegacyAndKiro() {
        XCTAssertTrue(ACPProtocolAdapter.isSessionUpdateMethod("session/update"))
        XCTAssertTrue(ACPProtocolAdapter.isSessionUpdateMethod("session/notification"))
        XCTAssertFalse(ACPProtocolAdapter.isSessionUpdateMethod("session/new"))
    }

    func testUpdateKindParsingSupportsSnakeAndPascalCase() {
        XCTAssertEqual(ACPProtocolAdapter.parseUpdateKind("agent_message_chunk"), .agentMessageChunk)
        XCTAssertEqual(ACPProtocolAdapter.parseUpdateKind("AgentMessageChunk"), .agentMessageChunk)
        XCTAssertEqual(ACPProtocolAdapter.parseUpdateKind("tool_call"), .toolCall)
        XCTAssertEqual(ACPProtocolAdapter.parseUpdateKind("ToolCall"), .toolCall)
        XCTAssertEqual(ACPProtocolAdapter.parseUpdateKind("tool_call_update"), .toolCallUpdate)
        XCTAssertEqual(ACPProtocolAdapter.parseUpdateKind("ToolCallUpdate"), .toolCallUpdate)
        XCTAssertEqual(ACPProtocolAdapter.parseUpdateKind("turn_end"), .turnEnd)
        XCTAssertEqual(ACPProtocolAdapter.parseUpdateKind("TurnEnd"), .turnEnd)
        XCTAssertNil(ACPProtocolAdapter.parseUpdateKind("unknown_update"))
    }

    func testPromptRequestUsesPromptField() {
        let contentBlocks: [[String: AnyCodable]] = [[
            "type": AnyCodable("text"),
            "text": AnyCodable("Explain this file")
        ]]

        let params = ACPProtocolAdapter.promptParams(sessionId: "sess_test", contentBlocks: contentBlocks)

        XCTAssertEqual(params["sessionId"]?.stringValue, "sess_test")
        XCTAssertNotNil(params["prompt"]?.arrayValue)
        XCTAssertNil(params["content"])
    }
}
