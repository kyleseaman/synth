import Foundation

// MARK: - Table Navigator

/// Pure enum with static methods for markdown table cell navigation.
/// Extracted for testability -- no AppKit or UI dependencies.
enum TableNavigator {

    // MARK: - Table Detection

    /// Returns `true` when the cursor is on a line that starts with
    /// optional whitespace followed by a pipe character.
    static func isInsideTable(text: String, cursorPosition: Int) -> Bool {
        let nsText = text as NSString
        guard cursorPosition >= 0,
              cursorPosition <= nsText.length
        else { return false }
        let lineRange = nsText.lineRange(
            for: NSRange(location: cursorPosition, length: 0)
        )
        let line = nsText.substring(with: lineRange)
        return lineStartsWithPipe(line)
    }

    /// Returns the number of columns in a table row.
    /// Counts the cells between pipes, ignoring leading/trailing pipes.
    /// For example `"| A | B | C |"` returns 3.
    static func tableColumnCount(line: String) -> Int {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("|") else { return 0 }
        // Split by | and filter out empty leading/trailing segments
        let parts = trimmed.split(
            separator: "|", omittingEmptySubsequences: false
        )
        // The first and last elements are empty when the line starts
        // and ends with |
        let cells = parts.dropFirst().dropLast()
        return cells.count
    }

    /// Returns a new empty row template with the given column count.
    /// For example, `newRowTemplate(columnCount: 3)` returns
    /// `"|  |  |  |\n"`.
    static func newRowTemplate(columnCount: Int) -> String {
        guard columnCount > 0 else { return "|\n" }
        var row = "|"
        for _ in 0..<columnCount {
            row += "  |"
        }
        row += "\n"
        return row
    }

    // MARK: - Cell Navigation

    /// Returns the cursor position at the start of the next cell's
    /// content (after the pipe and any whitespace). Returns `nil` if
    /// the cursor is not inside a table or there is no next cell in
    /// the current row or subsequent rows.
    static func nextCellPosition(
        text: String, cursorPosition: Int
    ) -> Int? {
        let nsText = text as NSString
        guard cursorPosition >= 0,
              cursorPosition <= nsText.length
        else { return nil }
        let lineRange = nsText.lineRange(
            for: NSRange(location: cursorPosition, length: 0)
        )
        let line = nsText.substring(with: lineRange)
        guard lineStartsWithPipe(line) else { return nil }

        // Find the next | after cursorPosition within the current line
        let offsetInLine = cursorPosition - lineRange.location
        let lineNS = line as NSString
        let searchStart = offsetInLine

        // Find next pipe in the current line
        if let nextPipe = findNextPipe(
            in: line, startingAt: searchStart
        ) {
            // Check if there is still another pipe after this one
            // (ensuring we are not at the trailing pipe)
            if let afterPipe = findNextPipe(
                in: line, startingAt: nextPipe + 1
            ) {
                _ = afterPipe // confirms content cell follows
                return lineRange.location + nextPipe + 1
                    + leadingSpaces(
                        in: lineNS, from: nextPipe + 1
                    )
            }
        }

        // If we are at the last cell of the current row, try the
        // next non-separator line
        var scanStart = NSMaxRange(lineRange)
        while scanStart < nsText.length {
            let nextLineRange = nsText.lineRange(
                for: NSRange(location: scanStart, length: 0)
            )
            let nextLine = nsText.substring(with: nextLineRange)
            if !lineStartsWithPipe(nextLine) { break }
            if !isSeparatorRow(nextLine) {
                // Return position after the first | and whitespace
                if let firstPipe = findNextPipe(
                    in: nextLine, startingAt: 0
                ) {
                    return nextLineRange.location + firstPipe + 1
                        + leadingSpaces(
                            in: nextLine as NSString,
                            from: firstPipe + 1
                        )
                }
            }
            scanStart = NSMaxRange(nextLineRange)
        }

        return nil
    }

    /// Returns the cursor position at the start of the previous
    /// cell's content. Returns `nil` if not in a table or at the
    /// first cell of the first row.
    static func previousCellPosition(
        text: String, cursorPosition: Int
    ) -> Int? {
        let nsText = text as NSString
        guard cursorPosition >= 0,
              cursorPosition <= nsText.length
        else { return nil }
        let lineRange = nsText.lineRange(
            for: NSRange(location: cursorPosition, length: 0)
        )
        let line = nsText.substring(with: lineRange)
        guard lineStartsWithPipe(line) else { return nil }

        let offsetInLine = cursorPosition - lineRange.location

        // Find the pipe just before the cursor
        if let prevPipe = findPreviousPipe(
            in: line, before: offsetInLine
        ) {
            // Find the pipe before that to land in the previous cell
            if let prevPrevPipe = findPreviousPipe(
                in: line, before: prevPipe
            ) {
                return lineRange.location + prevPrevPipe + 1
                    + leadingSpaces(
                        in: line as NSString,
                        from: prevPrevPipe + 1
                    )
            }
        }

        // Move to the previous non-separator line's last data cell
        var scanBack = lineRange.location
        while scanBack > 0 {
            let prevLineRange = nsText.lineRange(
                for: NSRange(
                    location: scanBack - 1, length: 0
                )
            )
            let prevLine = nsText.substring(with: prevLineRange)
            if !lineStartsWithPipe(prevLine) { break }
            if !isSeparatorRow(prevLine) {
                // Navigate to the last cell of the previous line
                return lastCellPosition(
                    in: prevLine, lineStart: prevLineRange.location
                )
            }
            scanBack = prevLineRange.location
        }
        return nil
    }

    // MARK: - Table Template

    /// Returns a 3-column, 2-row markdown table template.
    static var insertionTemplate: String {
        """
        | Header 1 | Header 2 | Header 3 |
        |----------|----------|----------|
        |          |          |          |

        """
    }

    // MARK: - Separator Detection

    /// Returns `true` if the line is a table separator row like
    /// `|---|---|` or `|:---|---:|`.
    static func isSeparatorRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard trimmed.hasPrefix("|") else { return false }
        // Remove pipes and check remaining is only dashes,
        // colons, and whitespace
        let inner = trimmed.replacingOccurrences(of: "|", with: "")
        let allowed = CharacterSet(charactersIn: "-: ")
        return !inner.isEmpty
            && inner.unicodeScalars.allSatisfy {
                allowed.contains($0)
            }
    }

    // MARK: - Private Helpers

    private static func lineStartsWithPipe(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return trimmed.hasPrefix("|")
    }

    private static func findNextPipe(
        in line: String, startingAt offset: Int
    ) -> Int? {
        let chars = Array(line.utf16)
        let pipe = "|".utf16.first ?? 0x7C
        for idx in offset..<chars.count
            where chars[idx] == pipe {
            return idx
        }
        return nil
    }

    private static func findPreviousPipe(
        in line: String, before offset: Int
    ) -> Int? {
        let chars = Array(line.utf16)
        let pipe = "|".utf16.first ?? 0x7C
        let upperBound = min(offset, chars.count)
        for idx in stride(from: upperBound - 1, through: 0, by: -1)
            where chars[idx] == pipe {
            return idx
        }
        return nil
    }

    private static func leadingSpaces(
        in nsString: NSString, from offset: Int
    ) -> Int {
        var count = 0
        while offset + count < nsString.length,
              nsString.character(at: offset + count) == 0x20 {
            count += 1
        }
        return count
    }

    private static func lastCellPosition(
        in line: String, lineStart: Int
    ) -> Int? {
        // Find the second-to-last pipe (start of last data cell)
        let chars = Array(line.utf16)
        let pipe = "|".utf16.first ?? 0x7C
        var pipePositions: [Int] = []
        for (idx, char) in chars.enumerated() where char == pipe {
            pipePositions.append(idx)
        }
        // We need at least 3 pipes for a valid table row with 2+
        // cells: |...|...|
        guard pipePositions.count >= 3 else { return nil }
        let targetPipe = pipePositions[pipePositions.count - 2]
        return lineStart + targetPipe + 1
            + leadingSpaces(in: line as NSString, from: targetPipe + 1)
    }
}
