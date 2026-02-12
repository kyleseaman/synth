import XCTest
@testable import Synth

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

    // MARK: - Template Category Tests

    func testAddTemplateWithCategoryAndDescription() {
        guard let storage = storage else {
            XCTFail("Missing storage")
            return
        }

        let store = TemplateStore(storage: storage, storageKey: storageKey)
        let template = store.addTemplate(
            name: "Meeting Notes",
            content: "# Meeting\n\n## Attendees\n\n## Agenda",
            shortcutSlot: nil,
            category: "Work",
            description: "Template for meeting notes"
        )

        XCTAssertNotNil(template)
        XCTAssertEqual(template?.category, "Work")
        XCTAssertEqual(template?.description, "Template for meeting notes")
        XCTAssertTrue(store.categories.contains("Work"))
    }

    func testTemplatesInCategoryFiltering() {
        guard let storage = storage else {
            XCTFail("Missing storage")
            return
        }

        let store = TemplateStore(storage: storage, storageKey: storageKey)
        _ = store.addTemplate(name: "Work Template 1", content: "work1", shortcutSlot: nil, category: "Work")
        _ = store.addTemplate(name: "Work Template 2", content: "work2", shortcutSlot: nil, category: "Work")
        _ = store.addTemplate(name: "Personal Template", content: "personal", shortcutSlot: nil, category: "Personal")
        _ = store.addTemplate(name: "Uncategorized", content: "none", shortcutSlot: nil)

        let workTemplates = store.templatesInCategory("Work")
        XCTAssertEqual(workTemplates.count, 2)

        let personalTemplates = store.templatesInCategory("Personal")
        XCTAssertEqual(personalTemplates.count, 1)

        let uncategorized = store.templatesInCategory(nil)
        XCTAssertEqual(uncategorized.count, 1)
        XCTAssertEqual(uncategorized.first?.name, "Uncategorized")
    }

    func testSearchByCategory() {
        guard let storage = storage else {
            XCTFail("Missing storage")
            return
        }

        let store = TemplateStore(storage: storage, storageKey: storageKey)
        _ = store.addTemplate(name: "Daily Standup", content: "standup", shortcutSlot: nil, category: "Meetings")
        _ = store.addTemplate(name: "Weekly Review", content: "review", shortcutSlot: nil, category: "Personal")

        let results = store.search("Meetings")
        XCTAssertEqual(results.first?.name, "Daily Standup")
    }

    func testSearchByDescription() {
        guard let storage = storage else {
            XCTFail("Missing storage")
            return
        }

        let store = TemplateStore(storage: storage, storageKey: storageKey)
        _ = store.addTemplate(
            name: "Project",
            content: "body",
            shortcutSlot: nil,
            description: "Track project milestones"
        )

        let results = store.search("milestones")
        XCTAssertEqual(results.first?.name, "Project")
    }

    // MARK: - Template Duplication Tests

    func testDuplicateTemplate() {
        guard let storage = storage else {
            XCTFail("Missing storage")
            return
        }

        let store = TemplateStore(storage: storage, storageKey: storageKey)
        guard let original = store.addTemplate(
            name: "Original",
            content: "Content here",
            shortcutSlot: 1,
            category: "Test",
            description: "Original description"
        ) else {
            XCTFail("Template creation failed")
            return
        }

        let duplicate = store.duplicateTemplate(identifier: original.identifier)

        XCTAssertNotNil(duplicate)
        XCTAssertEqual(duplicate?.name, "Original (Copy)")
        XCTAssertEqual(duplicate?.content, "Content here")
        XCTAssertEqual(duplicate?.category, "Test")
        XCTAssertEqual(duplicate?.description, "Original description")
        XCTAssertNil(duplicate?.shortcutSlot) // Shortcuts shouldn't be copied
        XCTAssertEqual(store.templates.count, 2)
    }

    func testDuplicateTemplateWithCustomName() {
        guard let storage = storage else {
            XCTFail("Missing storage")
            return
        }

        let store = TemplateStore(storage: storage, storageKey: storageKey)
        guard let original = store.addTemplate(
            name: "Source",
            content: "Content",
            shortcutSlot: nil
        ) else {
            XCTFail("Template creation failed")
            return
        }

        let duplicate = store.duplicateTemplate(identifier: original.identifier, newName: "Custom Name")

        XCTAssertNotNil(duplicate)
        XCTAssertEqual(duplicate?.name, "Custom Name")
    }

    // MARK: - Usage Tracking Tests

    func testUsageCountIncrementsOnExpansion() {
        guard let storage = storage else {
            XCTFail("Missing storage")
            return
        }

        let store = TemplateStore(storage: storage, storageKey: storageKey)
        guard let template = store.addTemplate(
            name: "Counter Test",
            content: "Test content",
            shortcutSlot: nil
        ) else {
            XCTFail("Template creation failed")
            return
        }

        XCTAssertEqual(template.usageCount, 0)

        _ = store.expandTemplate(template)
        let updated = store.template(named: "Counter Test")
        XCTAssertEqual(updated?.usageCount, 1)

        _ = store.expandTemplate(updated ?? template)
        let updatedAgain = store.template(named: "Counter Test")
        XCTAssertEqual(updatedAgain?.usageCount, 2)
    }

    // MARK: - Template Variable Expansion Tests

    func testExpandDateVariable() {
        let testDate = makeTestDate(year: 2026, month: 3, day: 15)
        let expanded = TemplateExpander.expand("Today is {{date}}", date: testDate)
        XCTAssertEqual(expanded.content, "Today is March 15, 2026")
    }

    func testExpandDateWithCustomFormat() {
        let testDate = makeTestDate(year: 2026, month: 3, day: 15)
        let expanded = TemplateExpander.expand("Date: {{date:yyyy-MM-dd}}", date: testDate)
        XCTAssertEqual(expanded.content, "Date: 2026-03-15")
    }

    func testExpandTimeVariable() {
        // Create a date at 2:30 PM
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 15
        components.hour = 14
        components.minute = 30
        let calendar = Calendar.current
        guard let testDate = calendar.date(from: components) else {
            XCTFail("Failed to create test date")
            return
        }

        let expanded = TemplateExpander.expand("Time: {{time:HH:mm}}", date: testDate)
        XCTAssertEqual(expanded.content, "Time: 14:30")
    }

    func testExpandYearMonthDayWeekday() {
        let testDate = makeTestDate(year: 2026, month: 3, day: 15) // Sunday
        let expanded = TemplateExpander.expand(
            "{{year}} {{month}} {{day}} {{weekday}}",
            date: testDate
        )
        XCTAssertEqual(expanded.content, "2026 March 15 Sunday")
    }

    func testExpandTitleAndFilename() {
        let expanded = TemplateExpander.expand(
            "# {{title}}\n\nFile: {{filename}}",
            title: "My Document",
            filename: "my-document"
        )
        XCTAssertEqual(expanded.content, "# My Document\n\nFile: my-document")
    }

    func testExpandCursorPlaceholder() {
        let expanded = TemplateExpander.expand("# Title\n\n{{cursor}}\n\nFooter")
        XCTAssertEqual(expanded.content, "# Title\n\n\n\nFooter")
        XCTAssertEqual(expanded.cursorOffset, 9) // Position after "# Title\n\n"
    }

    func testExpandUUID() {
        let expanded = TemplateExpander.expand("ID: {{uuid}}")
        // UUID should be replaced with a valid UUID string
        XCTAssertFalse(expanded.content.contains("{{uuid}}"))
        XCTAssertTrue(expanded.content.hasPrefix("ID: "))
        // Verify UUID format (8-4-4-4-12 characters)
        let uuidPart = expanded.content.replacingOccurrences(of: "ID: ", with: "")
        XCTAssertNotNil(UUID(uuidString: uuidPart))
    }

    func testExpandRandomNumber() {
        let expanded = TemplateExpander.expand("Code: {{random:4}}")
        XCTAssertFalse(expanded.content.contains("{{random:4}}"))
        let codePart = expanded.content.replacingOccurrences(of: "Code: ", with: "")
        XCTAssertEqual(codePart.count, 4)
        XCTAssertTrue(codePart.allSatisfy { $0.isNumber })
    }

    func testExpandMultipleVariables() {
        let testDate = makeTestDate(year: 2026, month: 3, day: 15)
        let template = """
        # {{title}}
        Date: {{date:yyyy-MM-dd}}

        {{cursor}}

        Created on {{weekday}}
        """

        let expanded = TemplateExpander.expand(template, title: "Test Note", date: testDate)

        XCTAssertTrue(expanded.content.contains("# Test Note"))
        XCTAssertTrue(expanded.content.contains("Date: 2026-03-15"))
        XCTAssertTrue(expanded.content.contains("Created on Sunday"))
        XCTAssertNotNil(expanded.cursorOffset)
    }

    func testPreviewExpansionDoesNotTrackUsage() {
        guard let storage = storage else {
            XCTFail("Missing storage")
            return
        }

        let store = TemplateStore(storage: storage, storageKey: storageKey)
        guard let template = store.addTemplate(
            name: "Preview Test",
            content: "Date: {{date}}",
            shortcutSlot: nil
        ) else {
            XCTFail("Template creation failed")
            return
        }

        // Preview should not increment usage
        _ = TemplateStore.previewExpansion(template.content)
        let afterPreview = store.template(named: "Preview Test")
        XCTAssertEqual(afterPreview?.usageCount, 0)
    }

    // MARK: - Helpers

    private func makeTestDate(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        components.minute = 0
        let calendar = Calendar.current
        return calendar.date(from: components) ?? Date()
    }
}
