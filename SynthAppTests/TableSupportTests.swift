import XCTest
@testable import Synth

final class TableSupportTests: XCTestCase {

    // MARK: - isTableRow Tests

    func testIsTableRowDetectsValidRows() {
        XCTAssertTrue(TableNavigator.isTableRow("| a | b | c |"))
        XCTAssertTrue(TableNavigator.isTableRow("| Name | Age |"))
        XCTAssertTrue(TableNavigator.isTableRow("|col1|col2|"))
        XCTAssertTrue(TableNavigator.isTableRow("| single |"))
    }

    func testIsTableRowRejectsNonTableLines() {
        XCTAssertFalse(TableNavigator.isTableRow("hello world"))
        XCTAssertFalse(TableNavigator.isTableRow("# Heading"))
        XCTAssertFalse(TableNavigator.isTableRow(""))
        XCTAssertFalse(TableNavigator.isTableRow("| open ended"))
        XCTAssertFalse(TableNavigator.isTableRow("no pipes here"))
    }

    // MARK: - isSeparatorRow Tests

    func testIsSeparatorRowDetectsSeparators() {
        XCTAssertTrue(TableNavigator.isSeparatorRow("|---|---|"))
        XCTAssertTrue(TableNavigator.isSeparatorRow("| --- | --- |"))
        XCTAssertTrue(
            TableNavigator.isSeparatorRow("| :--- | :---: | ---: |")
        )
        XCTAssertTrue(TableNavigator.isSeparatorRow("|:---|:---|"))
    }

    func testIsSeparatorRowRejectsNonSeparators() {
        XCTAssertFalse(
            TableNavigator.isSeparatorRow("| text | more |")
        )
        XCTAssertFalse(TableNavigator.isSeparatorRow("---"))
        XCTAssertFalse(TableNavigator.isSeparatorRow(""))
        XCTAssertFalse(
            TableNavigator.isSeparatorRow("| abc | def |")
        )
    }

    // MARK: - columnCount Tests

    func testColumnCountReturnsCorrectCount() {
        XCTAssertEqual(
            TableNavigator.columnCount(in: "| a | b | c |"), 3
        )
        XCTAssertEqual(
            TableNavigator.columnCount(in: "| Name | Age |"), 2
        )
        XCTAssertEqual(
            TableNavigator.columnCount(in: "| single |"), 1
        )
        XCTAssertEqual(
            TableNavigator.columnCount(in: "|a|b|c|d|"), 4
        )
    }

    func testColumnCountReturnsZeroForNonTableLines() {
        XCTAssertEqual(
            TableNavigator.columnCount(in: "not a table"), 0
        )
        XCTAssertEqual(
            TableNavigator.columnCount(in: "| open"), 0
        )
    }

    // MARK: - tableTemplate Tests

    func testTableTemplateGeneratesCorrectMarkdown() {
        let template = TableNavigator.tableTemplate(
            columns: 3, rows: 2
        )
        let lines = template.components(separatedBy: "\n")
            .filter { !$0.isEmpty }
        // Should have: header, separator, 2 data rows
        XCTAssertEqual(lines.count, 4)
        XCTAssertTrue(lines[0].contains("Header 1"))
        XCTAssertTrue(lines[0].contains("Header 3"))
        XCTAssertTrue(lines[1].contains("---"))
        XCTAssertTrue(lines[2].hasPrefix("|"))
        XCTAssertTrue(lines[2].hasSuffix("|"))
    }

    func testTableTemplateReturnsEmptyForZeroColumns() {
        XCTAssertEqual(
            TableNavigator.tableTemplate(columns: 0, rows: 2), ""
        )
    }

    func testTableTemplateReturnsEmptyForZeroRows() {
        XCTAssertEqual(
            TableNavigator.tableTemplate(columns: 3, rows: 0), ""
        )
    }

    // MARK: - newRowString Tests

    func testNewRowStringGeneratesBlankRow() {
        let row = TableNavigator.newRowString(columnCount: 3)
        XCTAssertEqual(row, "|   |   |   |\n")
    }

    func testNewRowStringReturnsEmptyForZeroColumns() {
        XCTAssertEqual(
            TableNavigator.newRowString(columnCount: 0), ""
        )
    }

    // MARK: - nextCellRange Tests

    func testNextCellRangeFindsNextCell() {
        let text = "| alpha | beta | gamma |\n"
        // Cursor inside "alpha" at position 2
        let range = TableNavigator.nextCellRange(
            in: text, from: 2
        )
        XCTAssertNotNil(range)
        if let range = range {
            let found = (text as NSString).substring(with: range)
            XCTAssertEqual(found, "beta")
        }
    }

    func testNextCellRangeReturnsNilAtEnd() {
        let text = "plain text"
        let range = TableNavigator.nextCellRange(
            in: text, from: 5
        )
        XCTAssertNil(range)
    }

    // MARK: - previousCellRange Tests

    func testPreviousCellRangeFindsPreviousCell() {
        let text = "| alpha | beta | gamma |\n"
        // Cursor inside "gamma" at position 18
        let gammaStart = (text as NSString).range(of: "gamma")
        let range = TableNavigator.previousCellRange(
            in: text, from: gammaStart.location + 2
        )
        XCTAssertNotNil(range)
        if let range = range {
            let found = (text as NSString).substring(with: range)
            XCTAssertEqual(found, "beta")
        }
    }

    func testPreviousCellRangeReturnsNilAtStart() {
        let text = "| alpha | beta |\n"
        // At the very beginning
        let range = TableNavigator.previousCellRange(
            in: text, from: 0
        )
        XCTAssertNil(range)
    }

    // MARK: - Rendering Integration Tests

    func testMarkdownFormatHasTablePatterns() {
        let text = "| a | b |\n"
        let fullRange = NSRange(
            location: 0, length: text.utf16.count
        )
        let match = MarkdownFormat.tableRowPattern.firstMatch(
            in: text, range: fullRange
        )
        XCTAssertNotNil(match)
    }

    func testMarkdownFormatHasSeparatorPattern() {
        let text = "| --- | --- |\n"
        let fullRange = NSRange(
            location: 0, length: text.utf16.count
        )
        let match = MarkdownFormat.separatorRowPattern.firstMatch(
            in: text, range: fullRange
        )
        XCTAssertNotNil(match)
    }
}
