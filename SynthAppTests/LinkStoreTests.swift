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

final class TemplateStoreTests: XCTestCase {
    private var storage: UserDefaults?
    private let storageSuite = "TemplateStoreTests"
    private let storageKey = "tests.savedTemplates"

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

    func testAddTemplatePersistsAndSearchesByName() {
        guard let storage = storage else {
            XCTFail("Missing storage")
            return
        }

        let store = TemplateStore(storage: storage, storageKey: storageKey)
        let template = store.addTemplate(
            name: "Daily Note",
            content: "# Daily\n\n- Wins\n- Todos",
            shortcutSlot: nil
        )

        XCTAssertNotNil(template)
        XCTAssertEqual(store.templates.count, 1)
        XCTAssertEqual(store.search("daily").first?.name, "Daily Note")

        let reloaded = TemplateStore(storage: storage, storageKey: storageKey)
        XCTAssertEqual(reloaded.templates.count, 1)
        XCTAssertEqual(reloaded.templates.first?.name, "Daily Note")
    }

    func testShortcutSlotIsUniqueAcrossTemplates() {
        guard let storage = storage else {
            XCTFail("Missing storage")
            return
        }

        let store = TemplateStore(storage: storage, storageKey: storageKey)
        _ = store.addTemplate(name: "First", content: "one", shortcutSlot: 1)
        _ = store.addTemplate(name: "Second", content: "two", shortcutSlot: 1)

        let firstTemplate = store.templates.first(where: { $0.name == "First" })
        let secondTemplate = store.templates.first(where: { $0.name == "Second" })

        XCTAssertEqual(secondTemplate?.shortcutSlot, 1)
        XCTAssertNil(firstTemplate?.shortcutSlot)
        XCTAssertEqual(store.templateForShortcut(1)?.name, "Second")
    }

    func testUpdateTemplateChangesContentAndShortcut() {
        guard let storage = storage else {
            XCTFail("Missing storage")
            return
        }

        let store = TemplateStore(storage: storage, storageKey: storageKey)
        guard let created = store.addTemplate(
            name: "Meeting",
            content: "old",
            shortcutSlot: nil
        ) else {
            XCTFail("Template creation failed")
            return
        }

        let didUpdate = store.updateTemplate(
            identifier: created.identifier,
            name: "Meeting",
            content: "## Agenda\n-",
            shortcutSlot: 3
        )

        XCTAssertTrue(didUpdate)
        XCTAssertEqual(store.templateForShortcut(3)?.content, "## Agenda\n-")
    }

    func testAddTemplateRejectsBlankValuesAndNormalizesInvalidShortcut() {
        guard let storage = storage else {
            XCTFail("Missing storage")
            return
        }

        let store = TemplateStore(storage: storage, storageKey: storageKey)

        XCTAssertNil(store.addTemplate(name: "  ", content: "body", shortcutSlot: 1))
        XCTAssertNil(store.addTemplate(name: "Name", content: "   ", shortcutSlot: 1))

        let created = store.addTemplate(name: "Quick Note", content: "body", shortcutSlot: 99)
        XCTAssertNotNil(created)
        XCTAssertNil(created?.shortcutSlot)
    }

    func testUpdateTemplateRejectsMissingIdentifierAndInvalidValues() {
        guard let storage = storage else {
            XCTFail("Missing storage")
            return
        }

        let store = TemplateStore(storage: storage, storageKey: storageKey)
        let missingIdentifier = UUID()

        XCTAssertFalse(store.updateTemplate(
            identifier: missingIdentifier,
            name: "Name",
            content: "Body",
            shortcutSlot: 1
        ))

        guard let created = store.addTemplate(name: "Keep", content: "Body", shortcutSlot: nil) else {
            XCTFail("Template creation failed")
            return
        }

        XCTAssertFalse(store.updateTemplate(
            identifier: created.identifier,
            name: "   ",
            content: "Body",
            shortcutSlot: 1
        ))
        XCTAssertFalse(store.updateTemplate(
            identifier: created.identifier,
            name: "Keep",
            content: "   ",
            shortcutSlot: 1
        ))
    }

    func testRemoveTemplateTemplateNamedAndSearchByContent() {
        guard let storage = storage else {
            XCTFail("Missing storage")
            return
        }

        let store = TemplateStore(storage: storage, storageKey: storageKey)
        let firstTemplate = store.addTemplate(
            name: "Retro",
            content: "Team retrospective notes",
            shortcutSlot: nil
        )
        _ = store.addTemplate(name: "Daily", content: "standup", shortcutSlot: 2)

        XCTAssertEqual(store.template(named: "retro")?.name, "Retro")
        XCTAssertEqual(store.search("retrospective").first?.name, "Retro")

        guard let firstIdentifier = firstTemplate?.identifier else {
            XCTFail("Missing template identifier")
            return
        }
        store.removeTemplate(identifier: firstIdentifier)
        XCTAssertNil(store.template(named: "Retro"))

        let reloaded = TemplateStore(storage: storage, storageKey: storageKey)
        XCTAssertEqual(reloaded.templates.count, 1)
        XCTAssertEqual(reloaded.templates.first?.name, "Daily")
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

    func testPromptRequestUsesContentField() {
        let contentBlocks: [[String: AnyCodable]] = [[
            "type": AnyCodable("text"),
            "text": AnyCodable("Explain this file")
        ]]

        let params = ACPProtocolAdapter.promptParams(sessionId: "sess_test", contentBlocks: contentBlocks)

        XCTAssertEqual(params["sessionId"]?.stringValue, "sess_test")
        XCTAssertNotNil(params["content"]?.arrayValue)
        XCTAssertNil(params["prompt"])
    }
}
