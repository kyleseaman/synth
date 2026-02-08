import XCTest
@testable import Synth

final class DailyNoteManagerTests: XCTestCase {
    private var workspaceURL: URL?
    private let fileFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    override func setUpWithError() throws {
        try super.setUpWithError()
        let temporaryURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: temporaryURL, withIntermediateDirectories: true)
        workspaceURL = temporaryURL
    }

    override func tearDownWithError() throws {
        if let workspaceURL {
            try? FileManager.default.removeItem(at: workspaceURL)
        }
        workspaceURL = nil
        try super.tearDownWithError()
    }

    @MainActor
    func testLoadIncludesExistingFileContent() throws {
        guard let workspaceURL else {
            XCTFail("Missing workspace URL")
            return
        }

        let manager = DailyNoteManager()
        let todayString = fileFormatter.string(from: Date())
        let dailyDirectory = workspaceURL.appendingPathComponent("daily", isDirectory: true)
        try FileManager.default.createDirectory(at: dailyDirectory, withIntermediateDirectories: true)
        let todayFileURL = dailyDirectory.appendingPathComponent("\(todayString).md")
        try "# Existing\n\nSaved".write(to: todayFileURL, atomically: true, encoding: .utf8)

        manager.load(workspace: workspaceURL)

        let loadedEntry = manager.entries.first { entry in
            entry.url.lastPathComponent == todayFileURL.lastPathComponent
        }
        XCTAssertNotNil(loadedEntry)
        XCTAssertTrue(loadedEntry?.exists == true)
        XCTAssertEqual(loadedEntry?.content, "# Existing\n\nSaved")
    }

    @MainActor
    func testUpdateContentMaterializesAndSaveWritesFile() throws {
        guard let workspaceURL else {
            XCTFail("Missing workspace URL")
            return
        }

        let manager = DailyNoteManager()
        manager.load(workspace: workspaceURL)

        guard let missingEntry = manager.entries.first(where: { !$0.exists }) else {
            XCTFail("Expected at least one missing entry")
            return
        }

        let didMaterialize = manager.updateContent(
            for: missingEntry.id,
            newContent: "# Updated\n\nBody"
        )

        XCTAssertTrue(didMaterialize)
        XCTAssertTrue(FileManager.default.fileExists(atPath: missingEntry.url.path))

        manager.save(entryID: missingEntry.id)

        let persistedContent = try String(contentsOf: missingEntry.url, encoding: .utf8)
        XCTAssertEqual(persistedContent, "# Updated\n\nBody")
    }

    @MainActor
    func testSaveAllWritesDirtyEntriesAndInvokesCallback() throws {
        guard let workspaceURL else {
            XCTFail("Missing workspace URL")
            return
        }

        let manager = DailyNoteManager()
        manager.load(workspace: workspaceURL)

        let missingEntries = manager.entries.filter { !$0.exists }
        guard missingEntries.count >= 2 else {
            XCTFail("Expected at least two missing entries")
            return
        }

        var savedPaths: [String] = []
        manager.onSave = { fileURL, _ in
            savedPaths.append(fileURL.path)
        }

        _ = manager.updateContent(for: missingEntries[0].id, newContent: "first")
        _ = manager.updateContent(for: missingEntries[1].id, newContent: "second")
        manager.saveAll()

        let firstContent = try String(contentsOf: missingEntries[0].url, encoding: .utf8)
        let secondContent = try String(contentsOf: missingEntries[1].url, encoding: .utf8)

        XCTAssertEqual(firstContent, "first")
        XCTAssertEqual(secondContent, "second")
        XCTAssertTrue(savedPaths.contains(missingEntries[0].url.path))
        XCTAssertTrue(savedPaths.contains(missingEntries[1].url.path))
    }

    @MainActor
    func testEnsureFutureDaysCreatesTodayAndFutureFiles() {
        guard let workspaceURL else {
            XCTFail("Missing workspace URL")
            return
        }

        let manager = DailyNoteManager()
        manager.ensureFutureDays(workspace: workspaceURL)

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let todayURL = workspaceURL.appendingPathComponent(
            "daily/\(fileFormatter.string(from: today)).md"
        )
        let weekAheadDate = calendar.date(byAdding: .day, value: 7, to: today)
        let weekAheadURL = workspaceURL.appendingPathComponent(
            "daily/\(fileFormatter.string(from: weekAheadDate ?? today)).md"
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: todayURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: weekAheadURL.path))
    }
}
