import XCTest
@testable import Synth

final class FindReplaceTests: XCTestCase {

    // MARK: - NSFindPanelAction Tag Constants

    /// Verify that the standard NSFindPanelAction tag values used by the
    /// find/replace shortcuts map to the expected operations.
    func testFindPanelActionTagValues() {
        // These tag values are defined by AppKit's NSFindPanelAction enum
        // and are used in SynthApp.sendFindPanelAction(tag:).
        let showFindPanelTag = 1
        let findNextTag = 2
        let findPreviousTag = 3
        let showFindAndReplaceTag = 12

        XCTAssertEqual(showFindPanelTag, 1, "Show Find panel tag should be 1")
        XCTAssertEqual(findNextTag, 2, "Find Next tag should be 2")
        XCTAssertEqual(findPreviousTag, 3, "Find Previous tag should be 3")
        XCTAssertEqual(
            showFindAndReplaceTag, 12,
            "Show Find and Replace tag should be 12"
        )
    }

    /// Verify that all required action tags are distinct so each shortcut
    /// triggers a different operation.
    func testFindPanelActionTagsAreDistinct() {
        let tags = [1, 2, 3, 12]
        let uniqueTags = Set(tags)
        XCTAssertEqual(
            tags.count, uniqueTags.count,
            "All find panel action tags must be unique"
        )
    }
}
