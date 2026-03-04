import XCTest
@testable import SynthMCPLib

final class ToolRouterTests: XCTestCase {
    func testResolvePathBlocksTraversal() {
        let workspace = "/tmp/workspace"
        XCTAssertNil(resolvePath("../etc/passwd", workspace: workspace))
        XCTAssertNil(resolvePath("/etc/passwd", workspace: workspace))
    }

    func testResolvePathAllowsValidPaths() {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(
            at: workspace, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: workspace) }

        let fileURL = workspace.appendingPathComponent("note.md")
        try? "test".write(to: fileURL, atomically: true, encoding: .utf8)

        let resolved = resolvePath("note.md", workspace: workspace.path)
        XCTAssertNotNil(resolved)
        XCTAssertTrue(resolved?.hasSuffix("note.md") == true)
    }

    func testListToolsReturnsAllEight() {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true).path
        let router = ToolRouter(workspacePath: workspace)
        let tools = router.listTools()
        XCTAssertEqual(tools.count, 8)
    }

    func testCallUnknownToolReturnsError() {
        let router = ToolRouter(workspacePath: "/tmp")
        let result = router.callTool(name: "nonexistent", arguments: [:])
        let text = result["content"]?.arrayValue?.first?["text"]?.stringValue
        XCTAssertTrue(text?.contains("Unknown tool") == true)
    }

    func testHasNestedQuantifiersDetectsPatterns() {
        XCTAssertTrue(GlobalSearch.hasNestedQuantifiers("(a+)+"))
        XCTAssertTrue(GlobalSearch.hasNestedQuantifiers("(a*)*"))
        XCTAssertFalse(GlobalSearch.hasNestedQuantifiers("a+b+"))
        XCTAssertFalse(GlobalSearch.hasNestedQuantifiers("(abc)+"))
    }
}

final class ToolHandlerTests: XCTestCase {
    private var workspace: URL!
    private var router: ToolRouter!

    override func setUp() {
        super.setUp()
        workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(
            at: workspace, withIntermediateDirectories: true
        )
        router = ToolRouter(workspacePath: workspace.path)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: workspace)
        super.tearDown()
    }

    // MARK: - read_note

    func testReadNoteReadsFile() throws {
        let fileURL = workspace.appendingPathComponent("hello.md")
        try "# Hello".write(to: fileURL, atomically: true, encoding: .utf8)

        let result = router.callTool(
            name: "read_note",
            arguments: ["path": .string("hello.md")]
        )
        let text = extractText(result)
        XCTAssertEqual(text, "# Hello")
    }

    func testReadNoteMissingFile() {
        let result = router.callTool(
            name: "read_note",
            arguments: ["path": .string("missing.md")]
        )
        XCTAssertTrue(isError(result))
    }

    func testReadNoteWithStats() throws {
        let fileURL = workspace.appendingPathComponent("stats.md")
        try "one two three".write(to: fileURL, atomically: true, encoding: .utf8)

        let result = router.callTool(
            name: "read_note",
            arguments: [
                "path": .string("stats.md"),
                "include_stats": .bool(true)
            ]
        )
        let text = extractText(result)
        XCTAssertTrue(text?.contains("Words: 3") == true)
    }

    // MARK: - list_notes

    func testListNotesListsFiles() throws {
        try "a".write(
            to: workspace.appendingPathComponent("one.md"),
            atomically: true, encoding: .utf8
        )
        try "b".write(
            to: workspace.appendingPathComponent("two.txt"),
            atomically: true, encoding: .utf8
        )

        let result = router.callTool(
            name: "list_notes",
            arguments: ["directory": .string(".")]
        )
        let text = extractText(result)
        XCTAssertTrue(text?.contains("one.md") == true)
        XCTAssertTrue(text?.contains("two.txt") == true)
    }

    func testListNotesFiltersByExtension() throws {
        try "a".write(
            to: workspace.appendingPathComponent("note.md"),
            atomically: true, encoding: .utf8
        )
        try "b".write(
            to: workspace.appendingPathComponent("image.png"),
            atomically: true, encoding: .utf8
        )

        let result = router.callTool(
            name: "list_notes",
            arguments: [
                "directory": .string("."),
                "extensions": .array([.string("md")])
            ]
        )
        let text = extractText(result)
        XCTAssertTrue(text?.contains("note.md") == true)
        XCTAssertFalse(text?.contains("image.png") == true)
    }

    // MARK: - global_search

    func testGlobalSearchFindsMatches() throws {
        try "hello world".write(
            to: workspace.appendingPathComponent("search.md"),
            atomically: true, encoding: .utf8
        )

        let result = router.callTool(
            name: "global_search",
            arguments: ["query": .string("hello")]
        )
        let text = extractText(result)
        XCTAssertTrue(text?.contains("hello world") == true)
    }

    // MARK: - manage_tags

    func testManageTagsListAndAdd() throws {
        let fileURL = workspace.appendingPathComponent("tagged.md")
        try "---\ntags:\n  - rust\n---\nBody".write(
            to: fileURL, atomically: true, encoding: .utf8
        )

        let listResult = router.callTool(
            name: "manage_tags",
            arguments: [
                "path": .string("tagged.md"),
                "action": .string("list")
            ]
        )
        XCTAssertTrue(extractText(listResult)?.contains("rust") == true)

        let addResult = router.callTool(
            name: "manage_tags",
            arguments: [
                "path": .string("tagged.md"),
                "action": .string("add"),
                "tag": .string("swift")
            ]
        )
        XCTAssertTrue(extractText(addResult)?.contains("Added") == true)

        let content = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(content.contains("swift"))
    }

    func testManageTagsRemove() throws {
        let fileURL = workspace.appendingPathComponent("remove.md")
        try "---\ntags:\n  - old\n---\nBody".write(
            to: fileURL, atomically: true, encoding: .utf8
        )

        let result = router.callTool(
            name: "manage_tags",
            arguments: [
                "path": .string("remove.md"),
                "action": .string("remove"),
                "tag": .string("old")
            ]
        )
        XCTAssertTrue(extractText(result)?.contains("Removed") == true)
    }

    // MARK: - update_note

    func testUpdateNoteAppend() throws {
        let fileURL = workspace.appendingPathComponent("append.md")
        try "first".write(to: fileURL, atomically: true, encoding: .utf8)

        let result = router.callTool(
            name: "update_note",
            arguments: [
                "path": .string("append.md"),
                "content": .string("second"),
                "position": .string("append")
            ]
        )
        XCTAssertFalse(isError(result))

        let content = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(content.contains("first"))
        XCTAssertTrue(content.contains("second"))
    }

    func testUpdateNotePrepend() throws {
        let fileURL = workspace.appendingPathComponent("prepend.md")
        try "second".write(to: fileURL, atomically: true, encoding: .utf8)

        let result = router.callTool(
            name: "update_note",
            arguments: [
                "path": .string("prepend.md"),
                "content": .string("first"),
                "position": .string("prepend")
            ]
        )
        XCTAssertFalse(isError(result))

        let content = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(content.hasPrefix("first"))
    }

    // MARK: - get_backlinks

    func testGetBacklinksFindsWikiLinks() throws {
        try "target content".write(
            to: workspace.appendingPathComponent("target.md"),
            atomically: true, encoding: .utf8
        )
        try "See [[target]] for details".write(
            to: workspace.appendingPathComponent("source.md"),
            atomically: true, encoding: .utf8
        )

        let result = router.callTool(
            name: "get_backlinks",
            arguments: ["path": .string("target.md")]
        )
        let text = extractText(result)
        XCTAssertTrue(text?.contains("source.md") == true)
    }

    // MARK: - get_people

    func testGetPeopleFindsAtMentions() throws {
        try "Meeting with @Alice and @Bob".write(
            to: workspace.appendingPathComponent("meeting.md"),
            atomically: true, encoding: .utf8
        )

        let result = router.callTool(
            name: "get_people",
            arguments: [:]
        )
        let text = extractText(result)
        XCTAssertTrue(text?.contains("Alice") == true)
        XCTAssertTrue(text?.contains("Bob") == true)
    }

    func testGetPeopleFiltersByPerson() throws {
        try "Talk to @Alice".write(
            to: workspace.appendingPathComponent("note.md"),
            atomically: true, encoding: .utf8
        )

        let result = router.callTool(
            name: "get_people",
            arguments: ["person": .string("Alice")]
        )
        let text = extractText(result)
        XCTAssertTrue(text?.contains("Alice") == true)
    }

    // MARK: - create_note

    func testCreateNoteBlankTemplate() {
        let result = router.callTool(
            name: "create_note",
            arguments: [
                "path": .string("new.md"),
                "template": .string("blank"),
                "title": .string("Test Note")
            ]
        )
        XCTAssertFalse(isError(result))

        let fileURL = workspace.appendingPathComponent("new.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        let content = try? String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(content?.contains("# Test Note") == true)
    }

    func testCreateNoteRejectsExistingFile() throws {
        let fileURL = workspace.appendingPathComponent("exists.md")
        try "existing".write(to: fileURL, atomically: true, encoding: .utf8)

        let result = router.callTool(
            name: "create_note",
            arguments: [
                "path": .string("exists.md"),
                "template": .string("blank")
            ]
        )
        XCTAssertTrue(isError(result))
    }

    func testCreateNoteBlocksPathTraversal() {
        let result = router.callTool(
            name: "create_note",
            arguments: [
                "path": .string("../outside.md"),
                "template": .string("blank")
            ]
        )
        XCTAssertTrue(isError(result))
    }

    func testCreateNoteAdrTemplate() {
        let result = router.callTool(
            name: "create_note",
            arguments: [
                "path": .string("adr.md"),
                "template": .string("adr"),
                "title": .string("Use Swift")
            ]
        )
        XCTAssertFalse(isError(result))
        let content = try? String(
            contentsOf: workspace.appendingPathComponent("adr.md"),
            encoding: .utf8
        )
        XCTAssertTrue(content?.contains("## Context") == true)
    }

    // MARK: - Helpers

    private func extractText(_ value: AnyCodableValue) -> String? {
        value["content"]?.arrayValue?.first?["text"]?.stringValue
    }

    private func isError(_ value: AnyCodableValue) -> Bool {
        value["isError"]?.boolValue == true
    }
}
