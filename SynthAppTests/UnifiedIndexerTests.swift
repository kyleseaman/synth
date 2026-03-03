import XCTest
@testable import Synth

final class UnifiedIndexerTests: XCTestCase {
    func testRebuildAllPopulatesAllIndexes() throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)

        try "[[linked]] #swift @alice content".write(
            to: workspace.appendingPathComponent("note.md"),
            atomically: true, encoding: .utf8
        )

        let context = IndexContext(
            noteIndex: NoteIndex(),
            backlinkIndex: BacklinkIndex(),
            tagIndex: TagIndex(),
            peopleIndex: PeopleIndex()
        )
        let fileTree = FileTreeNode.scan(workspace)
        UnifiedIndexer.rebuildAll(fileTree: fileTree, workspace: workspace, context: context)

        XCTAssertTrue(context.noteIndex.isPopulated)
        XCTAssertFalse(context.backlinkIndex.links(to: "linked").isEmpty)
        XCTAssertFalse(context.tagIndex.notes(for: "swift").isEmpty)
        XCTAssertFalse(context.peopleIndex.notes(for: "alice").isEmpty)
    }

    func testAddFileUpdatesAllIndexes() throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)

        let fileURL = workspace.appendingPathComponent("new.md")
        try "[[target]] #rust @bob".write(to: fileURL, atomically: true, encoding: .utf8)

        let context = IndexContext(
            noteIndex: NoteIndex(),
            backlinkIndex: BacklinkIndex(),
            tagIndex: TagIndex(),
            peopleIndex: PeopleIndex()
        )

        UnifiedIndexer.addFile(
            fileURL, content: "[[target]] #rust @bob",
            workspace: workspace, context: context
        )

        XCTAssertFalse(context.backlinkIndex.links(to: "target").isEmpty)
        XCTAssertFalse(context.tagIndex.notes(for: "rust").isEmpty)
        XCTAssertFalse(context.peopleIndex.notes(for: "bob").isEmpty)
    }

    func testRemoveFileUpdatesAllIndexes() throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)

        let fileURL = workspace.appendingPathComponent("remove.md")
        try "[[target]] #swift @alice".write(to: fileURL, atomically: true, encoding: .utf8)

        let context = IndexContext(
            noteIndex: NoteIndex(),
            backlinkIndex: BacklinkIndex(),
            tagIndex: TagIndex(),
            peopleIndex: PeopleIndex()
        )
        UnifiedIndexer.addFile(
            fileURL, content: "[[target]] #swift @alice",
            workspace: workspace, context: context
        )

        UnifiedIndexer.removeFile(fileURL, context: context)

        XCTAssertTrue(context.backlinkIndex.links(to: "target").isEmpty)
        XCTAssertTrue(context.tagIndex.notes(for: "swift").isEmpty)
        XCTAssertTrue(context.peopleIndex.notes(for: "alice").isEmpty)
    }

    func testUpdateFileUpdatesAllIndexes() throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)

        let fileURL = workspace.appendingPathComponent("update.md")
        try "[[old]] #alpha".write(to: fileURL, atomically: true, encoding: .utf8)

        let context = IndexContext(
            noteIndex: NoteIndex(),
            backlinkIndex: BacklinkIndex(),
            tagIndex: TagIndex(),
            peopleIndex: PeopleIndex()
        )
        UnifiedIndexer.addFile(
            fileURL, content: "[[old]] #alpha",
            workspace: workspace, context: context
        )

        UnifiedIndexer.updateFile(
            fileURL, content: "[[new]] #beta", context: context
        )

        XCTAssertTrue(context.backlinkIndex.links(to: "old").isEmpty)
        XCTAssertFalse(context.backlinkIndex.links(to: "new").isEmpty)
        XCTAssertTrue(context.tagIndex.notes(for: "alpha").isEmpty)
        XCTAssertFalse(context.tagIndex.notes(for: "beta").isEmpty)
    }
}
