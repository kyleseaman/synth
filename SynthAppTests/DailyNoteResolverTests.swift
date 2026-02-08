import XCTest
@testable import Synth

final class DailyNoteResolverTests: XCTestCase {
    private let fileFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    func testResolveDateParsesFilenameDate() {
        let parsedDate = DailyNoteResolver.resolveDate("2026-02-07")

        XCTAssertNotNil(parsedDate)
        XCTAssertEqual(fileFormatter.string(from: parsedDate ?? Date()), "2026-02-07")
    }

    func testResolveDateSupportsRelativeTokens() {
        XCTAssertNotNil(DailyNoteResolver.resolveDate("today"))
        XCTAssertNotNil(DailyNoteResolver.resolveDate("yesterday"))
        XCTAssertNotNil(DailyNoteResolver.resolveDate("tomorrow"))
        XCTAssertNotNil(DailyNoteResolver.resolveDate("next monday"))
        XCTAssertNotNil(DailyNoteResolver.resolveDate("next week"))
        XCTAssertNotNil(DailyNoteResolver.resolveDate("next month"))
        XCTAssertNotNil(DailyNoteResolver.resolveDate("in 3 days"))
        XCTAssertNil(DailyNoteResolver.resolveDate("in 0 days"))
        XCTAssertNil(DailyNoteResolver.resolveDate("nonsense"))
    }

    func testResolveCreatesDailyPathInsideWorkspace() {
        let workspaceURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: workspaceURL) }

        let resolvedURL = DailyNoteResolver.resolve("2026-02-07", workspace: workspaceURL)

        XCTAssertEqual(
            resolvedURL,
            workspaceURL.appendingPathComponent("daily/2026-02-07.md")
        )
    }

    func testEnsureExistsCreatesDateHeadingWhenNeeded() throws {
        let rootDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let noteURL = rootDirectory.appendingPathComponent("daily/2026-02-07.md")

        DailyNoteResolver.ensureExists(at: noteURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: noteURL.path))
        let fileContent = try String(contentsOf: noteURL, encoding: .utf8)
        XCTAssertTrue(fileContent.hasPrefix("# February 7, 2026\n\n"))
    }

    func testEnsureExistsUsesFilenameForUnknownDateFormat() throws {
        let rootDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let noteURL = rootDirectory.appendingPathComponent("daily/custom-note.md")

        DailyNoteResolver.ensureExists(at: noteURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: noteURL.path))
        let fileContent = try String(contentsOf: noteURL, encoding: .utf8)
        XCTAssertEqual(fileContent, "# custom-note\n\n")
    }

    func testEnsureExistsDoesNotOverwriteExistingFile() throws {
        let rootDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let noteURL = rootDirectory.appendingPathComponent("daily/2026-02-07.md")
        try FileManager.default.createDirectory(
            at: noteURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "# Existing\n\nBody".write(to: noteURL, atomically: true, encoding: .utf8)

        DailyNoteResolver.ensureExists(at: noteURL)

        let fileContent = try String(contentsOf: noteURL, encoding: .utf8)
        XCTAssertEqual(fileContent, "# Existing\n\nBody")
    }
}
