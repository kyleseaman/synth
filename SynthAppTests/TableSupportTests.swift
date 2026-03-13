import XCTest
@testable import Synth

final class TableSupportTests: XCTestCase {

    // MARK: - isInsideTable

    func testIsInsideTableOnTableRow() {
        let text = "| A | B |\n| C | D |"
        XCTAssertTrue(
            TableNavigator.isInsideTable(text: text, cursorPosition: 3)
        )
    }

    func testIsInsideTableOnSecondRow() {
        let text = "| A | B |\n| C | D |"
        XCTAssertTrue(
            TableNavigator.isInsideTable(text: text, cursorPosition: 12)
        )
    }

    func testIsInsideTableOnNonTableRow() {
        let text = "Hello world\n| A | B |"
        XCTAssertFalse(
            TableNavigator.isInsideTable(text: text, cursorPosition: 5)
        )
    }

    func testIsInsideTableAtBoundary() {
        let text = "| A | B |"
        XCTAssertTrue(
            TableNavigator.isInsideTable(text: text, cursorPosition: 0)
        )
    }

    func testIsInsideTableEmptyText() {
        XCTAssertFalse(
            TableNavigator.isInsideTable(text: "", cursorPosition: 0)
        )
    }

    func testIsInsideTableNegativePosition() {
        let text = "| A |"
        XCTAssertFalse(
            TableNavigator.isInsideTable(text: text, cursorPosition: -1)
        )
    }

    // MARK: - tableColumnCount

    func testTableColumnCountThreeColumns() {
        XCTAssertEqual(
            TableNavigator.tableColumnCount(line: "| A | B | C |"), 3
        )
    }

    func testTableColumnCountTwoColumns() {
        XCTAssertEqual(
            TableNavigator.tableColumnCount(line: "| X | Y |"), 2
        )
    }

    func testTableColumnCountSingleColumn() {
        XCTAssertEqual(
            TableNavigator.tableColumnCount(line: "| X |"), 1
        )
    }

    func testTableColumnCountNonTableLine() {
        XCTAssertEqual(
            TableNavigator.tableColumnCount(line: "Hello world"), 0
        )
    }

    func testTableColumnCountSeparatorRow() {
        XCTAssertEqual(
            TableNavigator.tableColumnCount(line: "|---|---|"), 2
        )
    }

    // MARK: - newRowTemplate

    func testNewRowTemplateThreeColumns() {
        let template = TableNavigator.newRowTemplate(columnCount: 3)
        XCTAssertEqual(template, "|  |  |  |\n")
    }

    func testNewRowTemplateTwoColumns() {
        let template = TableNavigator.newRowTemplate(columnCount: 2)
        XCTAssertEqual(template, "|  |  |\n")
    }

    func testNewRowTemplateZeroColumns() {
        let template = TableNavigator.newRowTemplate(columnCount: 0)
        XCTAssertEqual(template, "|\n")
    }

    // MARK: - isSeparatorRow

    func testIsSeparatorRowValid() {
        XCTAssertTrue(
            TableNavigator.isSeparatorRow("|---|---|")
        )
    }

    func testIsSeparatorRowWithColons() {
        XCTAssertTrue(
            TableNavigator.isSeparatorRow("|:---|---:|")
        )
    }

    func testIsSeparatorRowWithSpaces() {
        XCTAssertTrue(
            TableNavigator.isSeparatorRow("| --- | --- |")
        )
    }

    func testIsSeparatorRowNotASeparator() {
        XCTAssertFalse(
            TableNavigator.isSeparatorRow("| Cell A | Cell B |")
        )
    }

    func testIsSeparatorRowNoPipe() {
        XCTAssertFalse(
            TableNavigator.isSeparatorRow("------")
        )
    }

    // MARK: - nextCellPosition

    func testNextCellPositionMovesToNextCell() {
        let text = "| A | B | C |"
        // Cursor at position 2 (between | and A)
        let next = TableNavigator.nextCellPosition(
            text: text, cursorPosition: 2
        )
        // Should move to after the second | (position 5 or 6)
        XCTAssertNotNil(next)
        if let position = next {
            XCTAssertTrue(position > 2)
            XCTAssertTrue(position <= 6)
        }
    }

    func testNextCellPositionReturnsNilOutsideTable() {
        let text = "Hello world"
        let next = TableNavigator.nextCellPosition(
            text: text, cursorPosition: 3
        )
        XCTAssertNil(next)
    }

    func testNextCellPositionMovesToNextRow() {
        let text = "| A | B |\n| C | D |"
        // Cursor near end of first row (at last cell)
        let next = TableNavigator.nextCellPosition(
            text: text, cursorPosition: 7
        )
        // Should move to the next row (skipping separator-less rows)
        XCTAssertNotNil(next)
    }

    // MARK: - previousCellPosition

    func testPreviousCellPositionMovesBack() {
        let text = "| A | B | C |"
        // Cursor at cell B area (position 6)
        let prev = TableNavigator.previousCellPosition(
            text: text, cursorPosition: 6
        )
        XCTAssertNotNil(prev)
        if let position = prev {
            XCTAssertTrue(position < 6)
        }
    }

    func testPreviousCellPositionReturnsNilOutsideTable() {
        let text = "Normal text"
        let prev = TableNavigator.previousCellPosition(
            text: text, cursorPosition: 5
        )
        XCTAssertNil(prev)
    }

    func testPreviousCellPositionMovesToPreviousRow() {
        let text = "| A | B |\n| C | D |"
        // Cursor at start of second row, first cell
        let prev = TableNavigator.previousCellPosition(
            text: text, cursorPosition: 11
        )
        // Should move to the last cell of the first row
        XCTAssertNotNil(prev)
    }

    // MARK: - insertionTemplate

    func testInsertionTemplateHasThreeColumns() {
        let template = TableNavigator.insertionTemplate
        let lines = template.components(separatedBy: "\n")
        // Should have header, separator, data row, trailing empty
        XCTAssertTrue(lines.count >= 3)
        XCTAssertEqual(
            TableNavigator.tableColumnCount(line: lines[0]), 3
        )
    }

    func testInsertionTemplateSecondLineIsSeparator() {
        let template = TableNavigator.insertionTemplate
        let lines = template.components(separatedBy: "\n")
        XCTAssertTrue(TableNavigator.isSeparatorRow(lines[1]))
    }

    func testInsertionTemplateThirdLineIsDataRow() {
        let template = TableNavigator.insertionTemplate
        let lines = template.components(separatedBy: "\n")
        XCTAssertFalse(TableNavigator.isSeparatorRow(lines[2]))
        XCTAssertEqual(
            TableNavigator.tableColumnCount(line: lines[2]), 3
        )
    }

    // MARK: - Table Regex Pattern

    func testTableRowPatternMatchesValidRow() throws {
        let pattern = MarkdownFormat.tableRowPattern
        let text = "| Header 1 | Header 2 |"
        let range = NSRange(location: 0, length: text.utf16.count)
        let matches = pattern.matches(in: text, range: range)
        XCTAssertEqual(matches.count, 1)
    }

    func testTableRowPatternNoMatchForPlainText() throws {
        let pattern = MarkdownFormat.tableRowPattern
        let text = "Just some text"
        let range = NSRange(location: 0, length: text.utf16.count)
        let matches = pattern.matches(in: text, range: range)
        XCTAssertEqual(matches.count, 0)
    }

    func testTableRowPatternMatchesMultipleRows() throws {
        let pattern = MarkdownFormat.tableRowPattern
        let text = "| A | B |\n|---|---|\n| C | D |"
        let range = NSRange(location: 0, length: text.utf16.count)
        let matches = pattern.matches(in: text, range: range)
        XCTAssertEqual(matches.count, 3)
    }

    func testTableRowPatternMatchesWithLeadingWhitespace() throws {
        let pattern = MarkdownFormat.tableRowPattern
        let text = "  | A | B |"
        let range = NSRange(location: 0, length: text.utf16.count)
        let matches = pattern.matches(in: text, range: range)
        XCTAssertEqual(matches.count, 1)
    }

    // MARK: - Edge Cases

    func testIsInsideTableWithIndentedTableRow() {
        let text = "  | A | B |"
        XCTAssertTrue(
            TableNavigator.isInsideTable(text: text, cursorPosition: 5)
        )
    }

    func testNextCellPositionSkipsSeparatorRow() {
        let text = "| H1 | H2 |\n|-----|-----|\n| A  | B  |"
        // Cursor near end of header row (position 9)
        let next = TableNavigator.nextCellPosition(
            text: text, cursorPosition: 9
        )
        // Should skip the separator row and land in the data row
        XCTAssertNotNil(next)
    }
}
