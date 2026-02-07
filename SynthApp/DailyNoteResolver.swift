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
        let date: Date?
        switch token.lowercased() {
        case "today":
            date = Date()
        case "yesterday":
            date = Calendar.current.date(byAdding: .day, value: -1, to: Date())
        case "tomorrow":
            date = Calendar.current.date(byAdding: .day, value: 1, to: Date())
        default:
            return nil
        }
        guard let resolvedDate = date else { return nil }
        let filename = fileDateFormatter.string(from: resolvedDate)
        let folder = workspace.appendingPathComponent(dailyFolder)
        return folder.appendingPathComponent("\(filename).md")
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
