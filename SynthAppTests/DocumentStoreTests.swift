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
        let createdContent = try String(contentsOf: expectedURL, encoding: .utf8)
        XCTAssertEqual(createdContent, "# My-Note-\n")
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
        store.currentIndex = 0
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
    func testSelectSearchTabRequiresWorkspaceAndActivatesSearchMode() throws {
        let workspaceURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: workspaceURL) }
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)

        let store = DocumentStore()
        store.detailMode = .editor

        store.selectSearchTab()
        XCTAssertEqual(store.detailMode, .editor)

        store.workspace = workspaceURL
        store.selectSearchTab()
        XCTAssertEqual(store.detailMode, .search)
    }

    @MainActor
    func testOpenFromSearchKeepsSearchModeAndOpensDocument() throws {
        let workspaceURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: workspaceURL) }
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)

        let noteURL = workspaceURL.appendingPathComponent("search-note.md")
        try "# Search Note\n".write(to: noteURL, atomically: true, encoding: .utf8)

        let store = DocumentStore()
        store.workspace = workspaceURL
        store.selectSearchTab()

        store.openFromSearch(noteURL)

        XCTAssertEqual(store.detailMode, .search)
        XCTAssertEqual(store.openFiles.count, 1)
        XCTAssertEqual(store.openFiles.first?.url, noteURL)
    }

    @MainActor
    func testDedicatedSearchStateComposesQueryWithFacetFilters() {
        let state = DedicatedSearchState()
        state.textQuery = "release checklist"
        state.titleFilterText = "weekly sync"
        state.contentFilterText = "deployment"
        state.pathFilterText = "meeting notes"
        state.tagFilterText = "project, q1 plan"
        state.personFilterText = "alex"

        XCTAssertEqual(
            state.composedQuery,
            "release checklist title:\"weekly sync\" content:deployment " +
                "path:\"meeting notes\" tag:project tag:\"q1 plan\" person:alex"
        )
    }

    @MainActor
    func testDedicatedSearchStateRemoveFacetUpdatesBackingFilter() {
        let state = DedicatedSearchState()
        state.tagFilterText = "project, q1-plan, ops"

        let removableFacet = SearchFacetToken(kind: .tag, value: "q1-plan")
        state.removeFacet(removableFacet)

        XCTAssertEqual(state.tagFilterText, "project, ops")
    }

    @MainActor
    func testDedicatedSearchStateStepSelectionMovesPredictably() {
        let identifiers = ["note:alpha", "file:beta", "tag:gamma"]

        XCTAssertEqual(
            DedicatedSearchState.stepSelection(
                currentIdentifier: "note:alpha",
                availableIdentifiers: identifiers,
                direction: .next
            ),
            "file:beta"
        )
        XCTAssertEqual(
            DedicatedSearchState.stepSelection(
                currentIdentifier: "tag:gamma",
                availableIdentifiers: identifiers,
                direction: .next
            ),
            "tag:gamma"
        )
        XCTAssertEqual(
            DedicatedSearchState.stepSelection(
                currentIdentifier: "file:beta",
                availableIdentifiers: identifiers,
                direction: .previous
            ),
            "note:alpha"
        )
        XCTAssertEqual(
            DedicatedSearchState.stepSelection(
                currentIdentifier: nil,
                availableIdentifiers: identifiers,
                direction: .next
            ),
            "note:alpha"
        )
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
        let firstDraftContent = try String(contentsOf: firstDraftURL, encoding: .utf8)
        let secondDraftContent = try String(contentsOf: secondDraftURL, encoding: .utf8)
        XCTAssertEqual(firstDraftContent, "# \n")
        XCTAssertEqual(secondDraftContent, "# \n")
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

        // Populate the note index so notesReferencing can query it
        let context = IndexContext(
            noteIndex: store.noteIndex,
            backlinkIndex: store.backlinkIndex,
            tagIndex: store.tagIndex,
            peopleIndex: store.peopleIndex
        )
        UnifiedIndexer.rebuildAll(
            fileTree: FileTreeNode.scan(workspaceURL),
            workspace: workspaceURL,
            context: context
        )

        let notes = store.notesReferencing(mediaFilename: "screenshot.png")
        let returnedPaths = Set(notes.map { $0.url.standardizedFileURL.path })
        let expectedPaths = Set([
            firstURL.standardizedFileURL.path,
            secondURL.standardizedFileURL.path
        ])

        XCTAssertEqual(returnedPaths, expectedPaths)
    }

    @MainActor
    func testDeleteClosesOpenTabAndRemovesFile() throws {
        let workspaceURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: workspaceURL) }
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)

        let notesDirectory = workspaceURL.appendingPathComponent("notes", isDirectory: true)
        try FileManager.default.createDirectory(at: notesDirectory, withIntermediateDirectories: true)

        let canonicalURL = notesDirectory.appendingPathComponent("deletable.md")
        try "# Delete me\n".write(to: canonicalURL, atomically: true, encoding: .utf8)

        let nonCanonicalURL = URL(
            fileURLWithPath: notesDirectory.path + "/../notes/deletable.md"
        )

        let store = DocumentStore()
        store.workspace = workspaceURL
        store.open(canonicalURL)
        XCTAssertEqual(store.openFiles.count, 1)

        let didDelete = store.delete(nonCanonicalURL)

        XCTAssertTrue(didDelete)
        XCTAssertFalse(FileManager.default.fileExists(atPath: canonicalURL.path))
        XCTAssertTrue(store.openFiles.isEmpty)
        XCTAssertEqual(store.currentIndex, -1)
    }

    @MainActor
    func testDeletePrunesDraftFromInMemoryTreeImmediately() throws {
        let workspaceURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: workspaceURL) }
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)

        let draftsDirectory = workspaceURL.appendingPathComponent("drafts", isDirectory: true)
        try FileManager.default.createDirectory(at: draftsDirectory, withIntermediateDirectories: true)
        let draftURL = draftsDirectory.appendingPathComponent("Untitled.md")
        try "# draft\n".write(to: draftURL, atomically: true, encoding: .utf8)

        let store = DocumentStore()
        store.workspace = workspaceURL
        store.fileTree = FileTreeNode.scan(workspaceURL)

        func flatten(_ nodes: [FileTreeNode]) -> [URL] {
            nodes.flatMap { node in
                if let children = node.children {
                    return [node.url] + flatten(children)
                }
                return [node.url]
            }
        }

        let canonicalDraftURL = draftURL.standardizedFileURL.resolvingSymlinksInPath()
        func containsCanonical(_ nodes: [FileTreeNode], url: URL) -> Bool {
            flatten(nodes)
                .map { $0.standardizedFileURL.resolvingSymlinksInPath() }
                .contains(url)
        }

        XCTAssertTrue(
            containsCanonical(store.fileTree, url: canonicalDraftURL),
            "Expected draft file in initial in-memory tree"
        )
        let didDelete = store.delete(draftURL)
        XCTAssertTrue(didDelete, "Expected delete() to return true for draft file")
        XCTAssertFalse(
            containsCanonical(store.fileTree, url: canonicalDraftURL),
            "Expected draft file to be removed from in-memory tree immediately"
        )
    }

    @MainActor
    func testDeleteIncrementsFileTreeVersionForSidebarRefresh() throws {
        let workspaceURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: workspaceURL) }
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)

        let draftURL = workspaceURL.appendingPathComponent("Untitled.md")
        try "# draft\n".write(to: draftURL, atomically: true, encoding: .utf8)

        let store = DocumentStore()
        store.workspace = workspaceURL
        store.fileTree = FileTreeNode.scan(workspaceURL)
        let versionBeforeDelete = store.fileTreeVersion

        let didDelete = store.delete(draftURL)

        XCTAssertTrue(didDelete)
        XCTAssertNotEqual(store.fileTreeVersion, versionBeforeDelete)
    }

    @MainActor
    func testDeleteRemovesFileViaSymlinkPath() throws {
        let workspaceURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: workspaceURL) }
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)

        let realDirectory = workspaceURL.appendingPathComponent("real-drafts", isDirectory: true)
        try FileManager.default.createDirectory(at: realDirectory, withIntermediateDirectories: true)
        let linkDirectory = workspaceURL.appendingPathComponent("drafts-link", isDirectory: true)
        try FileManager.default.createSymbolicLink(
            at: linkDirectory,
            withDestinationURL: realDirectory
        )

        let canonicalURL = realDirectory.appendingPathComponent("linked-note.md")
        try "# Linked\n".write(to: canonicalURL, atomically: true, encoding: .utf8)
        let symlinkURL = linkDirectory.appendingPathComponent("linked-note.md")

        let store = DocumentStore()
        store.workspace = workspaceURL
        store.open(canonicalURL)

        let didDelete = store.delete(symlinkURL)

        XCTAssertTrue(didDelete)
        XCTAssertFalse(FileManager.default.fileExists(atPath: canonicalURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: symlinkURL.path))
    }

    @MainActor
    func testDeleteRejectsPathsOutsideWorkspaceBoundary() throws {
        let rootDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)

        let workspaceURL = rootDirectory.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        let externalURL = rootDirectory.appendingPathComponent("outside.md")
        try "keep".write(to: externalURL, atomically: true, encoding: .utf8)

        let store = DocumentStore()
        store.workspace = workspaceURL

        let didDelete = store.delete(externalURL)

        XCTAssertFalse(didDelete)
        XCTAssertTrue(FileManager.default.fileExists(atPath: externalURL.path))
    }

    @MainActor
    func testRequestDeleteFolderStagesConfirmationBeforeDeleting() throws {
        let workspaceURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: workspaceURL) }
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)

        let folderURL = workspaceURL.appendingPathComponent("projects", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let nestedFileURL = folderURL.appendingPathComponent("note.md")
        try "# Folder note\n".write(to: nestedFileURL, atomically: true, encoding: .utf8)

        let store = DocumentStore()
        store.workspace = workspaceURL

        store.requestDelete(folderURL, isDirectory: true)

        XCTAssertEqual(store.pendingDeleteTarget, folderURL)
        XCTAssertEqual(store.pendingDeleteName, "projects")
        XCTAssertTrue(store.pendingDeleteIsDirectory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folderURL.path))

        let didDelete = store.confirmPendingDelete()

        XCTAssertTrue(didDelete)
        XCTAssertNil(store.pendingDeleteTarget)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folderURL.path))
    }

    @MainActor
    func testRequestDeleteFileDeletesImmediatelyWithoutConfirmation() throws {
        let workspaceURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: workspaceURL) }
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)

        let fileURL = workspaceURL.appendingPathComponent("quick-delete.md")
        try "# Delete now\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let store = DocumentStore()
        store.workspace = workspaceURL

        store.requestDelete(fileURL, isDirectory: false)

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertNil(store.pendingDeleteTarget)
        XCTAssertFalse(store.pendingDeleteIsDirectory)
    }

    @MainActor
    func testDeleteMediaRemovesFileAndPrunesMediaListImmediately() throws {
        let workspaceURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: workspaceURL) }
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)

        let mediaDirectory = workspaceURL.appendingPathComponent("media", isDirectory: true)
        try FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        let mediaURL = mediaDirectory.appendingPathComponent("screenshot-1.png")
        try Data("image".utf8).write(to: mediaURL)

        let store = DocumentStore()
        store.workspace = workspaceURL
        store.mediaFiles = [mediaURL]

        let didDelete = store.deleteMedia(mediaURL)

        XCTAssertTrue(didDelete)
        XCTAssertFalse(FileManager.default.fileExists(atPath: mediaURL.path))
        XCTAssertFalse(store.mediaFiles.contains(mediaURL))
    }

    @MainActor
    func testDeleteMediaMissingFilePrunesMediaListAndReturnsFalse() throws {
        let workspaceURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: workspaceURL) }
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)

        let missingMediaURL = workspaceURL
            .appendingPathComponent("media", isDirectory: true)
            .appendingPathComponent("missing.png")

        let store = DocumentStore()
        store.workspace = workspaceURL
        store.mediaFiles = [missingMediaURL]

        let didDelete = store.deleteMedia(missingMediaURL)

        XCTAssertFalse(didDelete)
        XCTAssertFalse(store.mediaFiles.contains(missingMediaURL))
    }

    @MainActor
    func testDeleteMediaRejectsPathsOutsideMediaDirectory() throws {
        let workspaceURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: workspaceURL) }
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)

        let outsideMediaURL = workspaceURL.appendingPathComponent("outside-media.png")
        try Data("image".utf8).write(to: outsideMediaURL)

        let store = DocumentStore()
        store.workspace = workspaceURL
        store.mediaFiles = [outsideMediaURL]

        let didDelete = store.deleteMedia(outsideMediaURL)

        XCTAssertFalse(didDelete)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outsideMediaURL.path))
        XCTAssertTrue(store.mediaFiles.contains(outsideMediaURL))
    }

    func testFileTreeScanHidesKiroDirectoryFromSidebarTree() throws {
        let workspaceURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: workspaceURL) }
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)

        let kiroDirectory = workspaceURL.appendingPathComponent(".kiro", isDirectory: true)
        let steeringDirectory = kiroDirectory.appendingPathComponent("steering", isDirectory: true)
        try FileManager.default.createDirectory(at: steeringDirectory, withIntermediateDirectories: true)
        let steeringFile = steeringDirectory.appendingPathComponent("product.md")
        try "# Product".write(to: steeringFile, atomically: true, encoding: .utf8)

        let noteURL = workspaceURL.appendingPathComponent("notes.md")
        try "# Notes".write(to: noteURL, atomically: true, encoding: .utf8)

        let scannedNodes = FileTreeNode.scan(workspaceURL)
        let scannedNames = Set(scannedNodes.map(\.name))

        XCTAssertFalse(scannedNames.contains(".kiro"))
        XCTAssertTrue(scannedNames.contains("notes.md"))
    }

    @MainActor
    func testLoadKiroConfigSurfacesSteeringFilesAndCustomAgents() throws {
        let workspaceURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: workspaceURL) }
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)

        let steeringDirectory = workspaceURL
            .appendingPathComponent(".kiro", isDirectory: true)
            .appendingPathComponent("steering", isDirectory: true)
        let agentsDirectory = workspaceURL
            .appendingPathComponent(".kiro", isDirectory: true)
            .appendingPathComponent("agents", isDirectory: true)

        try FileManager.default.createDirectory(at: steeringDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: agentsDirectory, withIntermediateDirectories: true)

        let steeringFile = steeringDirectory.appendingPathComponent("voice.md")
        try "# Voice".write(to: steeringFile, atomically: true, encoding: .utf8)

        let agentFile = agentsDirectory.appendingPathComponent("doc-editor.json")
        let agentJSON: [String: Any] = [
            "name": "doc-editor",
            "description": "Edits and improves document prose"
        ]
        let agentData = try JSONSerialization.data(withJSONObject: agentJSON)
        try agentData.write(to: agentFile)

        let store = DocumentStore()
        store.workspace = workspaceURL
        store.loadKiroConfig()

        XCTAssertEqual(store.steeringFiles, ["voice.md"])
        XCTAssertEqual(store.customAgents.map(\.name), ["doc-editor"])
        XCTAssertEqual(store.customAgents.first?.description, "Edits and improves document prose")
    }

    @MainActor
    func testNewEmailNoteCreatesFileFromEml() throws {
        let workspaceURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: workspaceURL) }
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)

        let emlContent = """
        From: alice@example.com
        Subject: Project Update
        Date: Mon, 10 Jun 2024 09:00:00 -0400

        Here is the update for the project.
        """
        let emlURL = workspaceURL.appendingPathComponent("test-email.eml")
        try emlContent.write(to: emlURL, atomically: true, encoding: .utf8)

        let store = DocumentStore()
        store.workspace = workspaceURL

        store.newEmailNote(from: emlURL)

        let emailsDirectory = workspaceURL.appendingPathComponent("emails", isDirectory: true)
        let emailFiles = try FileManager.default.contentsOfDirectory(
            at: emailsDirectory,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(emailFiles.count, 1)

        let createdFile = emailFiles[0]
        XCTAssertTrue(createdFile.lastPathComponent.hasSuffix(".md"))

        let fileContent = try String(contentsOf: createdFile, encoding: .utf8)
        XCTAssertTrue(fileContent.contains("# Project Update"))
        XCTAssertTrue(fileContent.contains("**From:** alice@example.com"))
        XCTAssertTrue(fileContent.contains("update for the project"))
        XCTAssertEqual(store.openFiles.count, 1)
    }

    @MainActor
    func testReloadOpenDocumentFromDiskRefreshesContentAndClearsDirtyFlag() throws {
        let workspaceURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: workspaceURL) }
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)

        let noteURL = workspaceURL.appendingPathComponent("note.md")
        try "Original text".write(to: noteURL, atomically: true, encoding: .utf8)

        let store = DocumentStore()
        store.workspace = workspaceURL
        store.open(noteURL)

        guard let openIndex = store.currentIndex >= 0 ? Optional(store.currentIndex) : nil else {
            XCTFail("Missing open document index")
            return
        }

        store.openFiles[openIndex].content = NSAttributedString(string: "Unsaved local change")
        store.openFiles[openIndex].isDirty = true

        try "Edited by agent".write(to: noteURL, atomically: true, encoding: .utf8)

        let didReload = store.reloadOpenDocumentFromDisk(noteURL)

        XCTAssertTrue(didReload)
        XCTAssertEqual(store.openFiles[openIndex].content.string, "Edited by agent")
        XCTAssertFalse(store.openFiles[openIndex].isDirty)
    }

    @MainActor
    func testShowKanbanModalSetsDetailMode() {
        let store = DocumentStore()
        store.showKanbanModal()
        XCTAssertEqual(store.detailMode, .kanban)
    }

    @MainActor
    func testBootstrapKanbanFoldersCreatesDirectories() throws {
        let workspaceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: workspaceURL) }
        try FileManager.default.createDirectory(
            at: workspaceURL, withIntermediateDirectories: true
        )

        let store = DocumentStore()
        store.workspace = workspaceURL
        store.bootstrapKanbanFolders()

        for folder in ["Ideas", "Drafts", "Ready for Review", "Archive"] {
            let folderURL = workspaceURL.appendingPathComponent(folder)
            var isDir: ObjCBool = false
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDir)
            )
            XCTAssertTrue(isDir.boolValue)
        }
    }

    @MainActor
    func testKanbanFilesReturnsSortedMarkdownFiles() throws {
        let workspaceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: workspaceURL) }
        let ideasDir = workspaceURL.appendingPathComponent("Ideas")
        try FileManager.default.createDirectory(
            at: ideasDir, withIntermediateDirectories: true
        )
        try "# Bravo".write(
            to: ideasDir.appendingPathComponent("Bravo.md"),
            atomically: true, encoding: .utf8
        )
        try "# Alpha".write(
            to: ideasDir.appendingPathComponent("Alpha.txt"),
            atomically: true, encoding: .utf8
        )
        try Data("img".utf8).write(
            to: ideasDir.appendingPathComponent("photo.png")
        )

        let store = DocumentStore()
        store.workspace = workspaceURL
        let files = store.kanbanFiles(in: "Ideas")

        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(files[0].lastPathComponent, "Alpha.txt")
        XCTAssertEqual(files[1].lastPathComponent, "Bravo.md")
    }

    @MainActor
    func testMoveFileReturnsDestinationURLAndUpdatesOpenDocumentPath() throws {
        let workspaceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: workspaceURL) }

        let ideasDirectory = workspaceURL.appendingPathComponent("Ideas", isDirectory: true)
        let draftsDirectory = workspaceURL.appendingPathComponent("Drafts", isDirectory: true)
        try FileManager.default.createDirectory(
            at: ideasDirectory, withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: draftsDirectory, withIntermediateDirectories: true
        )

        let sourceURL = ideasDirectory.appendingPathComponent("Moved Note.md")
        try "# Move me".write(to: sourceURL, atomically: true, encoding: .utf8)

        let store = DocumentStore()
        store.workspace = workspaceURL
        store.open(sourceURL)

        let movedURL = store.moveFile(from: sourceURL, to: draftsDirectory)

        let expectedURL = draftsDirectory.appendingPathComponent("Moved Note.md")
        XCTAssertEqual(movedURL, expectedURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedURL.path))
        XCTAssertEqual(store.openFiles.first?.url, expectedURL)
    }

    @MainActor
    func testKanbanDropUsesMovedURLInsteadOfOriginalSourceURL() throws {
        let workspaceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: workspaceURL) }
        try FileManager.default.createDirectory(
            at: workspaceURL, withIntermediateDirectories: true
        )

        let sourceURL = workspaceURL
            .appendingPathComponent("Ideas", isDirectory: true)
            .appendingPathComponent("Renamed.md")
        let movedURL = workspaceURL
            .appendingPathComponent("Drafts", isDirectory: true)
            .appendingPathComponent("Renamed.md")
        let existingURL = workspaceURL
            .appendingPathComponent("Drafts", isDirectory: true)
            .appendingPathComponent("Alpha.md")

        let updatedFilesByColumn = KanbanBoardView.updatedColumnsAfterDrop(
            sourceURL: sourceURL,
            targetFolder: "Drafts",
            workspace: workspaceURL,
            currentFilesByColumn: [
                "Ideas": [sourceURL],
                "Drafts": [existingURL],
                "Ready for Review": []
            ],
            moveFile: { _, _ in movedURL }
        )

        XCTAssertEqual(updatedFilesByColumn["Ideas"], [])
        XCTAssertEqual(Set(updatedFilesByColumn["Drafts"] ?? []), Set([existingURL, movedURL]))
        XCTAssertFalse(updatedFilesByColumn["Drafts", default: []].contains(sourceURL))
    }

    @MainActor
    func testSelectSearchTabWithTagFocusSetsDetailModeAndFlag() throws {
        let workspaceURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: workspaceURL) }
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)

        let store = DocumentStore()
        store.workspace = workspaceURL
        store.detailMode = .editor

        store.selectSearchTabWithTagFocus()

        XCTAssertEqual(store.detailMode, .search)
        XCTAssertTrue(store.searchTagFocusRequested)
    }

    @MainActor
    func testSelectSearchTabWithTagFocusRequiresWorkspace() {
        let store = DocumentStore()
        store.detailMode = .editor

        store.selectSearchTabWithTagFocus()

        XCTAssertEqual(store.detailMode, .editor)
        XCTAssertFalse(store.searchTagFocusRequested)
    }
}
