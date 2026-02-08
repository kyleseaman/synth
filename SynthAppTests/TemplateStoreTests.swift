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
}
