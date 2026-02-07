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
