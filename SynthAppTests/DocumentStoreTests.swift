import XCTest
@testable import Synth

final class DocumentStoreTests: XCTestCase {
    private var lastWorkspacePath: String?
    private var recentPaths: [String]?

    override func setUp() {
        super.setUp()
        lastWorkspacePath = UserDefaults.standard.string(forKey: "lastWorkspace")
        recentPaths = UserDefaults.standard.stringArray(forKey: "recentFiles")
        UserDefaults.standard.removeObject(forKey: "lastWorkspace")
        UserDefaults.standard.removeObject(forKey: "recentFiles")
    }

    override func tearDown() {
        if let lastWorkspacePath {
            UserDefaults.standard.set(lastWorkspacePath, forKey: "lastWorkspace")
        } else {
            UserDefaults.standard.removeObject(forKey: "lastWorkspace")
        }

        if let recentPaths {
            UserDefaults.standard.set(recentPaths, forKey: "recentFiles")
        } else {
            UserDefaults.standard.removeObject(forKey: "recentFiles")
        }
        super.tearDown()
    }

    @MainActor
    func testAddToRecentDeduplicatesAndTrimsToTwentyItems() {
        let store = DocumentStore()
        let urls = (1...22).map { number in
            URL(fileURLWithPath: "/tmp/recent-\(number).md")
        }

        for fileURL in urls {
            store.addToRecent(fileURL)
        }

        XCTAssertEqual(store.recentFiles.count, 20)
        XCTAssertEqual(store.recentFiles.first, urls.last)

        if let repeatedURL = urls.dropFirst(5).first {
            store.addToRecent(repeatedURL)
            XCTAssertEqual(store.recentFiles.first, repeatedURL)
            XCTAssertEqual(Set(store.recentFiles).count, store.recentFiles.count)
        } else {
            XCTFail("Missing repeated URL")
        }
    }

    @MainActor
    func testCreateNoteIfNeededSanitizesNameAndOptionallyDoesNotOpen() throws {
        let workspaceURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: workspaceURL) }
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)

        let store = DocumentStore()
        store.workspace = workspaceURL

        store.createNoteIfNeeded(title: "  My/Note..  ", openAfter: false)

        let expectedURL = workspaceURL.appendingPathComponent("My-Note-.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedURL.path))
        XCTAssertTrue(store.openFiles.isEmpty)
    }

    @MainActor
    func testPromptAndConfirmRenameUpdatesOpenDocument() throws {
        let workspaceURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: workspaceURL) }
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)

        let originalURL = workspaceURL.appendingPathComponent("original.md")
        try "# Original\n".write(to: originalURL, atomically: true, encoding: .utf8)

        let store = DocumentStore()
        store.workspace = workspaceURL
        store.open(originalURL)

        store.promptRename(originalURL)
        store.renameText = "renamed.md"
        store.confirmRename()

        let renamedURL = workspaceURL.appendingPathComponent("renamed.md")
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamedURL.path))
        XCTAssertEqual(store.openFiles.first?.url, renamedURL)
        XCTAssertNil(store.renameTarget)
    }

    @MainActor
    func testTabManagementAndUiStateHelpers() throws {
        let workspaceURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: workspaceURL) }
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)

        let firstURL = workspaceURL.appendingPathComponent("first.md")
        let secondURL = workspaceURL.appendingPathComponent("second.md")
        try "# First\n".write(to: firstURL, atomically: true, encoding: .utf8)
        try "# Second\n".write(to: secondURL, atomically: true, encoding: .utf8)

        let store = DocumentStore()
        store.workspace = workspaceURL
        store.open(firstURL)
        store.open(secondURL)

        XCTAssertEqual(store.currentIndex, 1)
        store.switchTo(0)
        XCTAssertEqual(store.currentIndex, 0)

        store.closeTab(at: 0)
        XCTAssertEqual(store.openFiles.count, 1)
        XCTAssertEqual(store.currentIndex, 0)

        store.closeCurrentTab()
        XCTAssertTrue(store.openFiles.isEmpty)
        XCTAssertEqual(store.currentIndex, -1)

        let initialVisibility = store.columnVisibility
        store.toggleSidebar()
        XCTAssertNotEqual(store.columnVisibility, initialVisibility)

        let initialBacklinks = store.showBacklinks
        store.toggleBacklinks()
        XCTAssertEqual(store.showBacklinks, !initialBacklinks)

        store.showFileLauncherModal()
        XCTAssertEqual(store.activeModal, .fileLauncher)
        store.showTagBrowserModal(tag: "swift")
        XCTAssertEqual(store.activeModal, .tagBrowser("swift"))
        store.showPeopleBrowserModal(person: "alice")
        XCTAssertEqual(store.activeModal, .peopleBrowser("alice"))

        store.showImageDetailModal(secondURL)
        XCTAssertEqual(store.imageDetailURL, secondURL)
    }

    @MainActor
    func testNewDraftCreatesIncrementingUntitledFiles() throws {
        let workspaceURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: workspaceURL) }
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)

        let store = DocumentStore()
        store.workspace = workspaceURL

        store.newDraft()
        store.newDraft()

        let firstDraftURL = workspaceURL.appendingPathComponent("drafts/Untitled.md")
        let secondDraftURL = workspaceURL.appendingPathComponent("drafts/Untitled 2.md")

        XCTAssertTrue(FileManager.default.fileExists(atPath: firstDraftURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondDraftURL.path))
        XCTAssertEqual(store.openFiles.count, 2)
        XCTAssertEqual(store.openFiles.last?.url, secondDraftURL)
    }

    @MainActor
    func testSaveRenamesUntitledFileBasedOnFirstLine() throws {
        let workspaceURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: workspaceURL) }
        let draftsDirectory = workspaceURL.appendingPathComponent("drafts", isDirectory: true)
        try FileManager.default.createDirectory(at: draftsDirectory, withIntermediateDirectories: true)

        let untitledURL = draftsDirectory.appendingPathComponent("Untitled.md")
        try "# \\n\\n".write(to: untitledURL, atomically: true, encoding: .utf8)

        let store = DocumentStore()
        store.workspace = workspaceURL
        store.open(untitledURL)
        guard let currentIndex = store.currentIndex >= 0 ? Optional(store.currentIndex) : nil else {
            XCTFail("Missing current document")
            return
        }

        store.openFiles[currentIndex].content = NSAttributedString(string: "# Project Plan\n\nDetails")
        store.openFiles[currentIndex].isDirty = true
        store.save()

        let renamedURL = draftsDirectory.appendingPathComponent("Project Plan.md")
        XCTAssertFalse(FileManager.default.fileExists(atPath: untitledURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamedURL.path))
        XCTAssertEqual(store.openFiles[currentIndex].url, renamedURL)
    }

    @MainActor
    func testNewMeetingNoteCreatesTemplateAndUniqueFilename() throws {
        let workspaceURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: workspaceURL) }
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)

        let store = DocumentStore()
        store.workspace = workspaceURL

        store.newMeetingNote(name: "Planning/Sync")
        store.newMeetingNote(name: "Planning/Sync")

        let meetingDirectory = workspaceURL.appendingPathComponent("meetings", isDirectory: true)
        let meetingFiles = try FileManager.default.contentsOfDirectory(
            at: meetingDirectory,
            includingPropertiesForKeys: nil
        )
        let matchingFiles = meetingFiles.filter { fileURL in
            fileURL.lastPathComponent.contains("Planning-Sync")
        }

        XCTAssertEqual(matchingFiles.count, 2)
        let templateText = try String(contentsOf: matchingFiles[0], encoding: .utf8)
        XCTAssertTrue(templateText.contains("# Planning/Sync"))
        XCTAssertTrue(templateText.contains("### Agenda"))
    }

    @MainActor
    func testNotesReferencingReturnsMatchingMarkdownFiles() throws {
        let workspaceURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: workspaceURL) }
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)

        let firstURL = workspaceURL.appendingPathComponent("first.md")
        let secondURL = workspaceURL.appendingPathComponent("second.md")
        let thirdURL = workspaceURL.appendingPathComponent("third.md")
        try "![Shot](media/screenshot.png)".write(to: firstURL, atomically: true, encoding: .utf8)
        try "reference screenshot.png here".write(to: secondURL, atomically: true, encoding: .utf8)
        try "no match".write(to: thirdURL, atomically: true, encoding: .utf8)

        let store = DocumentStore()
        store.workspace = workspaceURL

        let notes = store.notesReferencing(mediaFilename: "screenshot.png")
        let returnedPaths = Set(notes.map { $0.url.standardizedFileURL.path })
        let expectedPaths = Set([
            firstURL.standardizedFileURL.path,
            secondURL.standardizedFileURL.path
        ])

        XCTAssertEqual(returnedPaths, expectedPaths)
    }
}
