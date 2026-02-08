import XCTest
@testable import Synth

final class BacklinkIndexTests: XCTestCase {
    func testUpdateFileTracksWikiAliasesAndDateMentions() {
        let index = BacklinkIndex()
        let sourceURL = URL(fileURLWithPath: "/tmp/source.md")
        let content = "See [[Project Plan|plan]] with @2026-02-07"

        index.updateFile(sourceURL, content: content)

        XCTAssertEqual(index.links(to: "project plan"), [sourceURL])
        XCTAssertEqual(index.links(to: "2026-02-07"), [sourceURL])
        XCTAssertEqual(index.outgoing(from: sourceURL), ["project plan", "2026-02-07"])
        XCTAssertEqual(index.snippet(from: sourceURL, to: "project plan"), content)
    }

    func testUpdateFileRemovesStaleOutgoingLinks() {
        let index = BacklinkIndex()
        let sourceURL = URL(fileURLWithPath: "/tmp/refresh.md")

        index.updateFile(sourceURL, content: "[[first]]")
        index.updateFile(sourceURL, content: "[[second]]")

        XCTAssertTrue(index.links(to: "first").isEmpty)
        XCTAssertEqual(index.links(to: "second"), [sourceURL])
    }

    func testRebuildScansMarkdownAndTextFilesOnly() throws {
        let rootDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let markdownURL = rootDirectory.appendingPathComponent("page.md")
        let textURL = rootDirectory.appendingPathComponent("notes.txt")
        let imageURL = rootDirectory.appendingPathComponent("image.png")

        try "[[alpha]]".write(to: markdownURL, atomically: true, encoding: .utf8)
        try "[[beta]]".write(to: textURL, atomically: true, encoding: .utf8)
        try "[[ignored]]".write(to: imageURL, atomically: true, encoding: .utf8)

        let fileTree = [
            FileTreeNode(url: markdownURL, isDirectory: false, children: nil),
            FileTreeNode(url: textURL, isDirectory: false, children: nil),
            FileTreeNode(url: imageURL, isDirectory: false, children: nil)
        ]

        let index = BacklinkIndex()
        index.rebuild(fileTree: fileTree)

        XCTAssertEqual(index.links(to: "alpha"), [markdownURL])
        XCTAssertEqual(index.links(to: "beta"), [textURL])
        XCTAssertTrue(index.links(to: "ignored").isEmpty)
    }
}
