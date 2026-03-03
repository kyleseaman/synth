import XCTest
@testable import Synth

final class TagAndPeopleIndexTests: XCTestCase {
    private let peopleStorageKey = "synth.globalPeople"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: peopleStorageKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: peopleStorageKey)
        super.tearDown()
    }

    func testTagIndexUpdateRemovesStaleTagsAndSupportsIntersection() {
        let index = TagIndex()
        let firstFileURL = URL(fileURLWithPath: "/tmp/first.md")
        let secondFileURL = URL(fileURLWithPath: "/tmp/second.md")

        index.updateFile(firstFileURL, content: "#alpha #beta")
        index.updateFile(secondFileURL, content: "#beta #gamma")
        index.updateFile(firstFileURL, content: "#alpha")

        XCTAssertEqual(index.notes(for: "alpha"), [firstFileURL])
        XCTAssertEqual(index.notes(for: "beta"), [secondFileURL])
        XCTAssertEqual(index.files(matchingAll: ["beta", "gamma"]), [secondFileURL])
    }

    func testTagIndexIgnoresCodeFenceContent() {
        let index = TagIndex()
        let fileURL = URL(fileURLWithPath: "/tmp/tag-check.md")
        let content = """
        #visible
        ```
        #hidden
        ```
        #second
        """

        index.updateFile(fileURL, content: content)

        XCTAssertEqual(index.tags(for: fileURL), ["visible", "second"])
        XCTAssertFalse(index.tags(for: fileURL).contains("hidden"))
    }

    func testPeopleIndexScanFiltersDateTokensAndCodeFenceMentions() {
        let index = PeopleIndex()
        let content = """
        @alice worked with @Bob Smith and @today
        ```
        @carol
        ```
        """

        let people = index.scanFile(content: content)

        XCTAssertTrue(people.contains("alice"))
        XCTAssertTrue(people.contains("bob smith"))
        XCTAssertFalse(people.contains("today"))
        XCTAssertFalse(people.contains("carol"))
    }

    func testPeopleIndexUpdateSupportsIntersectionAndPersistence() {
        let firstIndex = PeopleIndex()
        let firstFileURL = URL(fileURLWithPath: "/tmp/people-first.md")
        let secondFileURL = URL(fileURLWithPath: "/tmp/people-second.md")

        firstIndex.updateFile(firstFileURL, content: "@alice @bob")
        firstIndex.updateFile(secondFileURL, content: "@bob @carol")

        XCTAssertEqual(firstIndex.notes(for: "bob"), [firstFileURL, secondFileURL])
        XCTAssertEqual(firstIndex.files(matchingAll: ["alice", "bob"]), [firstFileURL])

        let secondIndex = PeopleIndex()
        XCTAssertTrue(secondIndex.globalPeople.contains("alice"))
        XCTAssertTrue(secondIndex.globalPeople.contains("bob"))
        XCTAssertTrue(secondIndex.globalPeople.contains("carol"))
    }

    func testPeopleIndexRebuildScansMarkdownAndTextFiles() throws {
        let rootDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let markdownURL = rootDirectory.appendingPathComponent("team.md")
        let textURL = rootDirectory.appendingPathComponent("notes.txt")
        let imageURL = rootDirectory.appendingPathComponent("image.png")

        try "@alice".write(to: markdownURL, atomically: true, encoding: .utf8)
        try "@bob".write(to: textURL, atomically: true, encoding: .utf8)
        try "@carol".write(to: imageURL, atomically: true, encoding: .utf8)

        let fileTree = [
            FileTreeNode(url: markdownURL, isDirectory: false, children: nil),
            FileTreeNode(url: textURL, isDirectory: false, children: nil),
            FileTreeNode(url: imageURL, isDirectory: false, children: nil)
        ]

        let index = PeopleIndex()
        index.rebuild(fileTree: fileTree)

        XCTAssertEqual(index.notes(for: "alice"), [markdownURL])
        XCTAssertEqual(index.notes(for: "bob"), [textURL])
        XCTAssertTrue(index.notes(for: "carol").isEmpty)
    }
}

// MARK: - TagIndex Additional Tests

extension TagAndPeopleIndexTests {
    func testTagIndexSearchFuzzyMatching() {
        let index = TagIndex()
        let fileURL = URL(fileURLWithPath: "/tmp/fuzzy-tag.md")
        index.updateFile(fileURL, content: "#project #programming")

        let results = index.search("prog")
        XCTAssertTrue(results.contains { $0.name == "programming" })
    }

    func testTagIndexAllTagsSortedByFrequency() {
        let index = TagIndex()
        let firstURL = URL(fileURLWithPath: "/tmp/tag-freq-1.md")
        let secondURL = URL(fileURLWithPath: "/tmp/tag-freq-2.md")
        index.updateFile(firstURL, content: "#common #rare")
        index.updateFile(secondURL, content: "#common")

        let allTags = index.allTags
        XCTAssertEqual(allTags.first?.name, "common")
        XCTAssertEqual(allTags.first?.count, 2)
    }

    func testTagIndexAddFileAndRemoveFile() {
        let index = TagIndex()
        let fileURL = URL(fileURLWithPath: "/tmp/tag-add.md")

        index.addFile(fileURL, content: "#added")
        XCTAssertTrue(index.notes(for: "added").contains(fileURL))

        index.removeFile(fileURL)
        XCTAssertTrue(index.notes(for: "added").isEmpty)
    }

    func testPeopleIndexSearchFuzzyMatching() {
        let index = PeopleIndex()
        let fileURL = URL(fileURLWithPath: "/tmp/fuzzy-people.md")
        index.updateFile(fileURL, content: "@alexander")

        let results = index.search("alex")
        XCTAssertTrue(results.contains { $0.name == "alexander" })
    }

    func testPeopleIndexAddFileAndRemoveFile() {
        let index = PeopleIndex()
        let fileURL = URL(fileURLWithPath: "/tmp/people-add.md")

        index.addFile(fileURL, content: "@charlie")
        XCTAssertTrue(index.notes(for: "charlie").contains(fileURL))

        index.removeFile(fileURL)
        XCTAssertTrue(index.notes(for: "charlie").isEmpty)
    }
}
