import XCTest
@testable import Synth

final class LinkStoreTests: XCTestCase {
    private var storage: UserDefaults?
    private let storageSuite = "LinkStoreTests"
    private let storageKey = "tests.savedLinks"

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

    func testAddLinkNormalizesAndPersists() {
        guard let storage = storage else {
            XCTFail("Missing storage")
            return
        }

        let store = LinkStore(storage: storage, storageKey: storageKey)
        let created = store.addLink("example.com")

        XCTAssertNotNil(created)
        XCTAssertEqual(store.links.count, 1)
        XCTAssertEqual(store.links.first?.urlString, "https://example.com")

        let reloaded = LinkStore(storage: storage, storageKey: storageKey)
        XCTAssertEqual(reloaded.links.count, 1)
        XCTAssertEqual(reloaded.links.first?.urlString, "https://example.com")
    }

    func testAddLinkRejectsEmpty() {
        guard let storage = storage else {
            XCTFail("Missing storage")
            return
        }

        let store = LinkStore(storage: storage, storageKey: storageKey)
        let created = store.addLink("   ")

        XCTAssertNil(created)
        XCTAssertTrue(store.links.isEmpty)
    }

    func testAddLinkDeduplicatesAndMovesToTop() {
        guard let storage = storage else {
            XCTFail("Missing storage")
            return
        }

        let store = LinkStore(storage: storage, storageKey: storageKey)
        let first = store.addLink("https://example.com")
        let second = store.addLink("https://another.com")
        let duplicate = store.addLink("example.com")

        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        XCTAssertNotNil(duplicate)
        XCTAssertEqual(store.links.count, 2)
        XCTAssertEqual(store.links.first?.urlString, "https://example.com")
        XCTAssertEqual(store.links.first?.identifier, first?.identifier)
    }
}
