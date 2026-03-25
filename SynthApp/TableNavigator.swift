import Foundation

// MARK: - Table Navigation & Detection

/// Pure utility enum for markdown table detection, cell navigation,
/// and template generation. No AppKit dependencies for core logic.
enum TableNavigator {

    // MARK: - Precompiled Patterns

    // swiftlint:disable force_try
    static let tableRowPattern = try! NSRegularExpression(
        pattern: #"^\|(.+\|)+\s*$"#,
        options: .anchorsMatchLines
    )
    static let separatorRowPattern = try! NSRegularExpression(
        pattern: #"^\|[\s:-]+(\|[\s:-]*)+$"#,
        options: .anchorsMatchLines
    )
    // swiftlint:enable force_try

    // MARK: - Line Detection

    /// Returns true if the given line matches the table row pattern
    /// (pipe-delimited cells like `| col1 | col2 |`).
    static func isTableRow(_ line: String) -> Bool {
        let range = NSRange(location: 0, length: line.utf16.count)
        return tableRowPattern.firstMatch(
            in: line, range: range
        ) != nil
    }

    /// Returns true if the given line matches the separator row pattern
    /// (like `|---|---|` or `| --- | --- |`).
    static func isSeparatorRow(_ line: String) -> Bool {
        let range = NSRange(location: 0, length: line.utf16.count)
        return separatorRowPattern.firstMatch(
            in: line, range: range
        ) != nil
    }

    /// Counts the number of cells (columns) in a pipe-delimited row.
    /// For `| a | b | c |` returns 3.
    static func columnCount(in line: String) -> Int {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("|"), trimmed.hasSuffix("|") else {
            return 0
        }
        // Drop leading and trailing pipes, split by remaining pipes
        let inner = String(trimmed.dropFirst().dropLast())
        let cells = inner.components(separatedBy: "|")
        return cells.count
    }

    // MARK: - Cell Navigation

    /// Finds the NSRange of the next cell's content after the cursor.
    /// Returns nil if there is no next cell in the table.
    static func nextCellRange(
        in text: String, from cursorLocation: Int
    ) -> NSRange? {
        let nsText = text as NSString
        let length = nsText.length
        guard cursorLocation <= length else { return nil }

        // Find the pipe after the cursor position
        var pipeIndex = cursorLocation
        while pipeIndex < length {
            if nsText.character(at: pipeIndex) == 0x7C { // '|'
                break
            }
            pipeIndex += 1
        }
        guard pipeIndex < length else { return nil }

        // Move past the pipe
        let afterPipe = pipeIndex + 1
        guard afterPipe < length else { return nil }

        // Check if we hit a newline -- need to go to next line
        let charAfterPipe = nsText.character(at: afterPipe)
        if charAfterPipe == 0x0A || charAfterPipe == 0x0D {
            // Move to next line and find first cell
            let nextLineStart = afterPipe + 1
            guard nextLineStart < length else { return nil }
            let nextLineRange = nsText.lineRange(
                for: NSRange(location: nextLineStart, length: 0)
            )
            let nextLine = nsText.substring(with: nextLineRange)
            let trimmedLine = nextLine.trimmingCharacters(
                in: .newlines
            )
            // Skip separator rows
            if isSeparatorRow(trimmedLine) {
                // Recurse from end of separator line
                let lineEnd = NSMaxRange(nextLineRange)
                return nextCellRange(in: text, from: lineEnd)
            }
            guard isTableRow(trimmedLine) else { return nil }
            // Find first cell in this line
            return firstCellRange(
                in: text, lineStart: nextLineRange.location
            )
        }

        // Find the next pipe to get cell boundaries
        var nextPipe = afterPipe
        while nextPipe < length {
            let nextChar = nsText.character(at: nextPipe)
            if nextChar == 0x7C { break } // '|'
            if nextChar == 0x0A || nextChar == 0x0D { break }
            nextPipe += 1
        }
        guard nextPipe < length,
              nsText.character(at: nextPipe) == 0x7C else {
            return nil
        }

        // Return range of content between pipes (trimmed spaces)
        return trimmedCellRange(
            in: nsText, start: afterPipe, end: nextPipe
        )
    }

    /// Finds the NSRange of the previous cell's content before the cursor.
    /// Returns nil if there is no previous cell in the table.
    static func previousCellRange(
        in text: String, from cursorLocation: Int
    ) -> NSRange? {
        let nsText = text as NSString
        guard cursorLocation > 0 else { return nil }

        // Find the pipe before the cursor
        var pipeIndex = cursorLocation - 1
        while pipeIndex >= 0 {
            if nsText.character(at: pipeIndex) == 0x7C { break }
            pipeIndex -= 1
        }
        guard pipeIndex >= 0 else { return nil }

        // Check if this pipe is at start of line (leading pipe)
        let lineRange = nsText.lineRange(
            for: NSRange(location: pipeIndex, length: 0)
        )
        let lineContent = nsText.substring(with: lineRange)
            .trimmingCharacters(in: .newlines)
        let offsetInLine = pipeIndex - lineRange.location

        if offsetInLine == 0 {
            // At leading pipe -- go to previous line's last cell
            guard lineRange.location > 0 else { return nil }
            let prevLineRange = nsText.lineRange(
                for: NSRange(
                    location: lineRange.location - 1, length: 0
                )
            )
            let prevLine = nsText.substring(with: prevLineRange)
                .trimmingCharacters(in: .newlines)
            // Skip separator rows
            if isSeparatorRow(prevLine) {
                return previousCellRange(
                    in: text, from: prevLineRange.location
                )
            }
            guard isTableRow(prevLine) else { return nil }
            return lastCellRange(
                in: text, lineStart: prevLineRange.location,
                lineContent: prevLine
            )
        }

        // Find the pipe before this one
        var prevPipe = pipeIndex - 1
        while prevPipe >= lineRange.location {
            if nsText.character(at: prevPipe) == 0x7C { break }
            prevPipe -= 1
        }
        guard prevPipe >= lineRange.location,
              nsText.character(at: prevPipe) == 0x7C,
              isTableRow(lineContent) else {
            return nil
        }

        return trimmedCellRange(
            in: nsText, start: prevPipe + 1, end: pipeIndex
        )
    }

    // MARK: - Template Generation

    /// Generates a blank table row with the given column count.
    /// Example: `|   |   |   |\n` for 3 columns.
    static func newRowString(columnCount columns: Int) -> String {
        guard columns > 0 else { return "" }
        var row = "|"
        for _ in 0..<columns {
            row += "   |"
        }
        row += "\n"
        return row
    }

    /// Generates a full markdown table template with header,
    /// separator, and data rows.
    static func tableTemplate(columns: Int, rows: Int) -> String {
        guard columns > 0, rows > 0 else { return "" }
        var result = ""
        // Header row
        let headers = (1...columns).map { "Header \($0)" }
        result += "| "
            + headers.joined(separator: " | ") + " |\n"
        // Separator row
        let separators = Array(
            repeating: "---", count: columns
        )
        result += "| "
            + separators.joined(separator: " | ") + " |\n"
        // Data rows
        for _ in 1...rows {
            result += newRowString(columnCount: columns)
        }
        return result
    }

    // MARK: - Private Helpers

    /// Finds the first cell range in a table row starting at lineStart.
    private static func firstCellRange(
        in text: String, lineStart: Int
    ) -> NSRange? {
        let nsText = text as NSString
        let length = nsText.length
        guard lineStart < length else { return nil }

        // Find leading pipe
        var firstPipe = lineStart
        while firstPipe < length {
            if nsText.character(at: firstPipe) == 0x7C { break }
            firstPipe += 1
        }
        guard firstPipe < length else { return nil }

        // Find second pipe
        let afterFirst = firstPipe + 1
        var secondPipe = afterFirst
        while secondPipe < length {
            let charValue = nsText.character(at: secondPipe)
            if charValue == 0x7C { break }
            if charValue == 0x0A || charValue == 0x0D { break }
            secondPipe += 1
        }
        guard secondPipe < length,
              nsText.character(at: secondPipe) == 0x7C else {
            return nil
        }

        return trimmedCellRange(
            in: nsText, start: afterFirst, end: secondPipe
        )
    }

    /// Finds the last cell range in a table row.
    private static func lastCellRange(
        in text: String, lineStart: Int, lineContent: String
    ) -> NSRange? {
        let nsText = text as NSString
        // Find the trailing pipe
        let lineEnd = lineStart + lineContent.utf16.count
        guard lineEnd > lineStart else { return nil }

        // Walk backwards from end to find trailing pipe
        var trailingPipe = lineEnd - 1
        while trailingPipe > lineStart {
            if nsText.character(at: trailingPipe) == 0x7C { break }
            trailingPipe -= 1
        }
        guard trailingPipe > lineStart else { return nil }

        // Find the pipe before the trailing one
        var prevPipe = trailingPipe - 1
        while prevPipe > lineStart {
            if nsText.character(at: prevPipe) == 0x7C { break }
            prevPipe -= 1
        }
        guard prevPipe >= lineStart,
              nsText.character(at: prevPipe) == 0x7C else {
            return nil
        }

        return trimmedCellRange(
            in: nsText, start: prevPipe + 1, end: trailingPipe
        )
    }

    /// Returns the range of content between two pipe positions,
    /// trimming leading/trailing spaces but keeping at least 1 char.
    private static func trimmedCellRange(
        in nsText: NSString, start: Int, end: Int
    ) -> NSRange? {
        guard end > start else { return nil }
        // Find first non-space character
        var trimStart = start
        while trimStart < end,
              nsText.character(at: trimStart) == 0x20 {
            trimStart += 1
        }
        // Find last non-space character
        var trimEnd = end - 1
        while trimEnd > trimStart,
              nsText.character(at: trimEnd) == 0x20 {
            trimEnd -= 1
        }
        // If all spaces, select the whole space range
        if trimStart >= end {
            return NSRange(location: start, length: end - start)
        }
        return NSRange(
            location: trimStart, length: trimEnd - trimStart + 1
        )
    }
}
