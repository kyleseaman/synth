import XCTest
@testable import Synth

final class ACPSessionStoreTests: XCTestCase {
    func testSaveAndLoadSessionId() {
        let docURL = URL(fileURLWithPath: "/tmp/test-session-\(UUID().uuidString).md")
        defer { ACPSessionStore.remove(for: docURL) }

        ACPSessionStore.save(sessionId: "sess_123", for: docURL)
        XCTAssertEqual(ACPSessionStore.sessionId(for: docURL), "sess_123")
    }

    func testRemoveSessionId() {
        let docURL = URL(fileURLWithPath: "/tmp/test-remove-\(UUID().uuidString).md")

        ACPSessionStore.save(sessionId: "sess_456", for: docURL)
        ACPSessionStore.remove(for: docURL)
        XCTAssertNil(ACPSessionStore.sessionId(for: docURL))
    }

    func testSessionIdReturnsNilForUnknownDocument() {
        let docURL = URL(fileURLWithPath: "/tmp/unknown-\(UUID().uuidString).md")
        XCTAssertNil(ACPSessionStore.sessionId(for: docURL))
    }
}
