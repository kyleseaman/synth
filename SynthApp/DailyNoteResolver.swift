import Foundation

// MARK: - Daily Note Resolver

struct DailyNoteResolver {
    static let dailyFolder = "daily"

    private static let fileDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let headingDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter
    }()

    static func resolve(_ token: String, workspace: URL) -> URL? {
        guard let resolvedDate = resolveDate(token) else { return nil }
        let filename = fileDateFormatter.string(from: resolvedDate)
        let folder = workspace.appendingPathComponent(dailyFolder)
        return folder.appendingPathComponent("\(filename).md")
    }

    /// Resolve a token string to a Date. Returns nil for unrecognized tokens.
    /// Supports relative tokens ("today", "next monday") and
    /// date filenames ("2026-02-07").
    static func resolveDate(_ token: String) -> Date? {
        let lower = token.lowercased().trimmingCharacters(in: .whitespaces)
        let calendar = Calendar.current
        let now = Date()

        // Try yyyy-MM-dd date filename format first
        if let date = fileDateFormatter.date(from: lower) {
            return date
        }

        // Simple day offsets
        switch lower {
        case "today":
            return now
        case "yesterday":
            return calendar.date(byAdding: .day, value: -1, to: now)
        case "tomorrow":
            return calendar.date(byAdding: .day, value: 1, to: now)
        case "next week":
            return nextWeekday(2, after: now)
        case "next month":
            let components = calendar.dateComponents([.year, .month], from: now)
            guard let firstOfMonth = calendar.date(from: components) else { return nil }
            return calendar.date(byAdding: .month, value: 1, to: firstOfMonth)
        default:
            break
        }

        // "next <weekday>" pattern
        if lower.hasPrefix("next ") {
            let dayName = String(lower.dropFirst(5))
            if let weekday = weekdayFromName(dayName) {
                return nextWeekday(weekday, after: now)
            }
        }

        // "in N days" pattern
        if lower.hasPrefix("in ") && lower.hasSuffix(" days") {
            let middle = lower.dropFirst(3).dropLast(5)
                .trimmingCharacters(in: .whitespaces)
            if let offset = Int(middle), offset >= 1 {
                return calendar.date(byAdding: .day, value: offset, to: now)
            }
        }

        return nil
    }

    // MARK: - Weekday Helpers

    private static let weekdayNames: [(String, Int)] = [
        ("sunday", 1), ("monday", 2), ("tuesday", 3),
        ("wednesday", 4), ("thursday", 5), ("friday", 6),
        ("saturday", 7)
    ]

    private static func weekdayFromName(_ name: String) -> Int? {
        weekdayNames.first { $0.0 == name }?.1
    }

    /// Find the next occurrence of a given weekday (1=Sun..7=Sat) after today.
    private static func nextWeekday(_ target: Int, after date: Date) -> Date? {
        let calendar = Calendar.current
        let today = calendar.component(.weekday, from: date)
        var daysAhead = target - today
        if daysAhead <= 0 { daysAhead += 7 }
        return calendar.date(byAdding: .day, value: daysAhead, to: date)
    }

    static func ensureExists(at url: URL) {
        let folder = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            let dateStr = url.deletingPathExtension().lastPathComponent
            let heading: String
            if let date = fileDateFormatter.date(from: dateStr) {
                heading = headingDateFormatter.string(from: date)
            } else {
                heading = dateStr
            }
            let content = "# \(heading)\n\n"
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
