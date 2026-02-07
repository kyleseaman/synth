import Foundation
import Combine

// MARK: - Daily Note Entry

struct DailyNoteEntry: Identifiable, Equatable {
    let date: Date
    let url: URL
    var exists: Bool
    var content: String
    var isDirty: Bool = false

    var id: String { url.path }

    static func == (lhs: DailyNoteEntry, rhs: DailyNoteEntry) -> Bool {
        lhs.url == rhs.url && lhs.exists == rhs.exists
            && lhs.content == rhs.content && lhs.isDirty == rhs.isDirty
    }
}

// MARK: - Daily Note Manager

class DailyNoteManager: ObservableObject {
    @Published var entries: [DailyNoteEntry] = []

    /// Called after a daily note is saved with (url, content)
    /// so indexes (backlinks, tags, people) can update.
    var onSave: ((URL, String) -> Void)?

    private let pastDays = 30
    private let futureDays = 7
    private var saveTimer: Timer?

    private static let fileDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static let headingDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d, yyyy"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    // MARK: - Load & Scan

    func load(workspace: URL) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dailyFolder = workspace.appendingPathComponent(
            DailyNoteResolver.dailyFolder
        )

        var result: [DailyNoteEntry] = []

        guard let startDate = calendar.date(
            byAdding: .day, value: -pastDays, to: today
        ),
              let endDate = calendar.date(
                  byAdding: .day, value: futureDays, to: today
              ) else {
            return
        }

        var current = startDate
        while current <= endDate {
            let filename = Self.fileDateFormatter.string(from: current)
            let url = dailyFolder.appendingPathComponent("\(filename).md")
            let exists = FileManager.default.fileExists(atPath: url.path)
            let content: String
            if exists {
                content = (try? String(
                    contentsOf: url, encoding: .utf8
                )) ?? ""
            } else {
                content = ""
            }
            let entry = DailyNoteEntry(
                date: current, url: url,
                exists: exists, content: content
            )
            result.append(entry)
            guard let nextDay = calendar.date(
                byAdding: .day, value: 1, to: current
            ) else { break }
            current = nextDay
        }

        entries = result
    }

    func ensureFutureDays(workspace: URL) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dailyFolder = workspace.appendingPathComponent(
            DailyNoteResolver.dailyFolder
        )

        try? FileManager.default.createDirectory(
            at: dailyFolder, withIntermediateDirectories: true
        )

        for offset in 0...futureDays {
            guard let date = calendar.date(
                byAdding: .day, value: offset, to: today
            ) else { continue }
            let filename = Self.fileDateFormatter.string(from: date)
            let url = dailyFolder.appendingPathComponent("\(filename).md")
            if !FileManager.default.fileExists(atPath: url.path) {
                let heading = Self.headingDateFormatter.string(from: date)
                let template = "# \(heading)\n\n"
                try? template.write(
                    to: url, atomically: true, encoding: .utf8
                )
            }
        }
    }

    // MARK: - Content Updates

    /// Returns true if a new file was materialized (caller should refresh file tree)
    @discardableResult
    func updateContent(for entryID: String, newContent: String) -> Bool {
        guard let index = entries.firstIndex(
            where: { $0.id == entryID }
        ) else { return false }

        var didMaterialize = false
        // Materialize virtual note on first edit
        if !entries[index].exists {
            materializeNote(
                at: entries[index].url, date: entries[index].date
            )
            didMaterialize = true
        }

        entries[index].content = newContent
        entries[index].isDirty = true
        scheduleSave()
        return didMaterialize
    }

    func materializeNote(at url: URL, date: Date) {
        let folder = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: url.path) {
            let heading = Self.headingDateFormatter.string(from: date)
            let template = "# \(heading)\n\n"
            try? template.write(
                to: url, atomically: true, encoding: .utf8
            )
        }
        if let index = entries.firstIndex(where: { $0.url == url }) {
            entries[index].exists = true
            if entries[index].content.isEmpty {
                entries[index].content = (try? String(
                    contentsOf: url, encoding: .utf8
                )) ?? ""
            }
        }
    }

    // MARK: - Debounced Save

    private func scheduleSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0, repeats: false
        ) { [weak self] _ in
            self?.saveAll()
        }
    }

    func save(entryID: String) {
        guard let index = entries.firstIndex(
            where: { $0.id == entryID }
        ) else { return }
        guard entries[index].isDirty else { return }
        try? entries[index].content.write(
            to: entries[index].url, atomically: true, encoding: .utf8
        )
        entries[index].isDirty = false
        onSave?(entries[index].url, entries[index].content)
    }

    func saveAll() {
        for index in entries.indices where entries[index].isDirty {
            try? entries[index].content.write(
                to: entries[index].url,
                atomically: true, encoding: .utf8
            )
            entries[index].isDirty = false
            onSave?(entries[index].url, entries[index].content)
        }
    }

    // MARK: - Date Formatting

    static func displayDate(_ date: Date) -> String {
        displayDateFormatter.string(from: date)
    }

    static func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }

    static func dateIdentifier(_ date: Date) -> String {
        fileDateFormatter.string(from: date)
    }
}
