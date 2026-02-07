import AppKit

// MARK: - Shared autocomplete logic for wiki links, @mentions, #tags
// Used by both MarkdownEditor.Coordinator and DailyNoteEditor.Coordinator

class AutocompleteCoordinator {
    weak var textView: FormattingTextView?
    weak var store: DocumentStore?
    let wikiLinkPopover = WikiLinkPopover()
    private var observers: [NSObjectProtocol] = []

    /// Called after autocomplete text replacement finishes.
    /// The parent coordinator should update its binding and re-format.
    var onTextChange: (() -> Void)?

    deinit {
        removeObservers()
    }

    // MARK: - Observer Setup

    func setupObservers() {
        let center = NotificationCenter.default

        let triggerObs = center.addObserver(
            forName: .wikiLinkTrigger,
            object: nil, queue: .main
        ) { [weak self] notification in
            self?.handleTrigger(notification)
        }
        observers.append(triggerObs)

        let dismissObs = center.addObserver(
            forName: .wikiLinkDismiss,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.wikiLinkPopover.dismiss()
        }
        observers.append(dismissObs)

        let queryObs = center.addObserver(
            forName: .wikiLinkQueryUpdate,
            object: nil, queue: .main
        ) { [weak self] notification in
            self?.handleQueryUpdate(notification)
        }
        observers.append(queryObs)

        let selectObs = center.addObserver(
            forName: .wikiLinkSelect,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.handleSelect()
        }
        observers.append(selectObs)

        let navObs = center.addObserver(
            forName: .wikiLinkNavigate,
            object: nil, queue: .main
        ) { [weak self] notification in
            self?.handleNavigate(notification)
        }
        observers.append(navObs)

        wikiLinkPopover.onSelect = { [weak self] title in
            self?.completeWikiLink(title: title)
        }
    }

    func removeObservers() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
    }

    // MARK: - Handlers

    private func handleTrigger(_ notification: Notification) {
        guard let textView = textView,
              notification.object as? FormattingTextView
                  === textView else { return }
        let mode = notification.userInfo?["mode"]
            as? String ?? "wikilink"
        let query = notification.userInfo?["query"]
            as? String ?? ""
        let cursor = textView.selectedRange().location

        let triggerStart: Int
        if mode == "wikilink" {
            triggerStart = max(cursor - 2, 0)
        } else if mode == "hashtag" {
            triggerStart = max(cursor - 2, 0)
        } else {
            triggerStart = max(cursor - 1, 0)
        }

        wikiLinkPopover.show(
            at: triggerStart, in: textView, mode: mode
        )

        let results: [NoteSearchResult]
        if mode == "at" {
            results = atResults(query: "")
        } else if mode == "hashtag" {
            results = tagResults(query: query)
        } else {
            results = store?.noteIndex.search("") ?? []
        }
        wikiLinkPopover.updateResults(
            query: query, results: results
        )
    }

    private func handleQueryUpdate(_ notification: Notification) {
        guard let textView = textView,
              notification.object as? FormattingTextView
                  === textView else { return }
        let query = notification.userInfo?["query"]
            as? String ?? ""

        let results: [NoteSearchResult]
        switch textView.wikiLinkState {
        case .atActive:
            results = atResults(query: query)
        case .hashtagActive:
            results = tagResults(query: query)
        default:
            results = store?.noteIndex.search(query) ?? []
        }
        wikiLinkPopover.updateResults(
            query: query, results: results
        )
    }

    private func handleSelect() {
        guard let title = wikiLinkPopover.selectedTitle()
        else { return }
        guard let textView = textView,
              textView.window?.firstResponder === textView
        else { return }
        completeWikiLink(title: title)
    }

    private func handleNavigate(_ notification: Notification) {
        guard let textView = textView,
              notification.object as? FormattingTextView
                  === textView else { return }
        let direction = notification.userInfo?["direction"]
            as? String ?? ""
        if direction == "up" {
            wikiLinkPopover.moveSelectionUp()
        } else {
            wikiLinkPopover.moveSelectionDown()
        }
    }

    // MARK: - Completion

    private static let dateFileFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt
    }()

    func completeWikiLink(title: String) {
        guard let textView = textView else { return }

        // Unfurl ALL date tokens to concrete yyyy-MM-dd filenames
        // e.g. "Today" → "2026-02-07", "Next Monday" → "2026-02-10"
        // The rendering layer displays them relatively (@Today, etc.)
        var completionTitle = title
        if let resolved = DailyNoteResolver.resolveDate(title),
           title.range(
               of: "^\\d{4}-\\d{2}-\\d{2}$",
               options: .regularExpression
           ) == nil {
            completionTitle = Self.dateFileFormatter
                .string(from: resolved)
        }

        let result = textView.completeAutocomplete(
            title: completionTitle
        )
        wikiLinkPopover.dismiss()

        // Auto-create the note file so the link renders immediately
        if result.completedWikiLink, let store = store {
            let noteTitle = title.trimmingCharacters(
                in: .whitespaces
            )
            if store.noteIndex.findExact(noteTitle) == nil {
                store.createNoteIfNeeded(
                    title: noteTitle, openAfter: false
                )
            }
        }

        // Ensure daily note file exists for date mentions
        if result.completedDate,
           let store = store,
           let workspace = store.workspace {
            let folder = workspace.appendingPathComponent(
                DailyNoteResolver.dailyFolder
            )
            let fileURL = folder.appendingPathComponent(
                "\(completionTitle).md"
            )
            DailyNoteResolver.ensureExists(at: fileURL)
            store.loadFileTree()
        }

        onTextChange?()

        // Auto-save after person mention so the people
        // index updates immediately
        if result.completedPerson {
            DispatchQueue.main.async { [weak self] in
                self?.store?.save()
            }
        }
    }

    // MARK: - Autocomplete Results

    func atResults(query: String) -> [NoteSearchResult] {
        var results = dateResults(query: query)
        if let peopleIndex = store?.peopleIndex {
            let people = peopleIndex.search(query)
            let mapped = people.map { person in
                let label = person.count == 1
                    ? "1 note" : "\(person.count) notes"
                return NoteSearchResult(
                    // swiftlint:disable:next force_unwrapping
                    id: URL(string: "synth://person/\(person.name)")!,
                    title: person.name,
                    relativePath: label,
                    // swiftlint:disable:next force_unwrapping
                    url: URL(string: "synth://person/\(person.name)")!
                )
            }
            results.append(contentsOf: mapped)
        }
        return results
    }

    // swiftlint:disable:next function_body_length
    func dateResults(query: String) -> [NoteSearchResult] {
        let basicTokens = ["Today", "Yesterday", "Tomorrow"]
        let extendedTokens = [
            "Next Sunday", "Next Monday", "Next Tuesday",
            "Next Wednesday", "Next Thursday", "Next Friday",
            "Next Saturday", "Next Week", "Next Month",
            "In 2 Days", "In 3 Days", "In 4 Days", "In 5 Days"
        ]

        let candidates: [String]
        if query.isEmpty {
            candidates = basicTokens
        } else {
            let lowerQuery = query.lowercased()
            candidates = (basicTokens + extendedTokens).filter {
                $0.lowercased().hasPrefix(lowerQuery)
            }
        }

        return candidates.compactMap { token in
            guard let date = DailyNoteResolver.resolveDate(token)
            else { return nil }
            let label = Self.ordinalDateString(from: date)
            let slug = token.lowercased()
                .addingPercentEncoding(
                    withAllowedCharacters: .urlPathAllowed
                ) ?? token.lowercased()
            // swiftlint:disable:next force_unwrapping
            let tokenURL = URL(string: "synth://daily/\(slug)")!
            return NoteSearchResult(
                id: tokenURL,
                title: token,
                relativePath: label,
                url: tokenURL
            )
        }
    }

    func tagResults(query: String) -> [NoteSearchResult] {
        guard let tagIndex = store?.tagIndex else { return [] }
        let tags = tagIndex.search(query)
        return tags.map { tag in
            NoteSearchResult(
                // swiftlint:disable:next force_unwrapping
                id: URL(string: "synth://tag/\(tag.name)")!,
                title: "#\(tag.name)",
                relativePath: "\(tag.count) notes",
                // swiftlint:disable:next force_unwrapping
                url: URL(string: "synth://tag/\(tag.name)")!
            )
        }
    }

    // MARK: - Ordinal Date Formatting

    private static let ordinalFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM d, yyyy"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt
    }()

    /// Formats a date as "February 9th, 2026" with ordinal suffix.
    static func ordinalDateString(from date: Date) -> String {
        let day = Calendar.current.component(.day, from: date)
        let base = ordinalFormatter.string(from: date)
        let suffix = ordinalSuffix(for: day)
        // Insert suffix after the day number, before the comma
        return base.replacingOccurrences(
            of: "\(day),",
            with: "\(day)\(suffix),"
        )
    }

    private static func ordinalSuffix(for day: Int) -> String {
        if (11...13).contains(day) { return "th" }
        switch day % 10 {
        case 1: return "st"
        case 2: return "nd"
        case 3: return "rd"
        default: return "th"
        }
    }

    // MARK: - Link Click Handling

    func handleLinkClick(url: URL) -> Bool {
        guard url.scheme == "synth" else { return false }

        if url.host == "wiki" {
            let noteTitle = url.pathComponents.dropFirst()
                .joined(separator: "/")
                .removingPercentEncoding ?? ""
            guard let store = store else { return true }
            if let exact = store.noteIndex.findExact(noteTitle) {
                store.open(exact.url)
            } else {
                store.createNoteIfNeeded(title: noteTitle)
            }
            return true
        }

        if url.host == "daily" {
            let token = url.pathComponents.dropFirst()
                .joined(separator: "/")
                .removingPercentEncoding ?? ""
            guard let store = store,
                  let workspace = store.workspace,
                  let resolved = DailyNoteResolver.resolve(
                      token, workspace: workspace
                  ) else { return true }
            DailyNoteResolver.ensureExists(at: resolved)
            store.loadFileTree()
            store.activateDailyNotes()
            NotificationCenter.default.post(
                name: .showDailyDate, object: nil,
                userInfo: ["date": token]
            )
            return true
        }

        if url.host == "tag" {
            let tagName = url.pathComponents.dropFirst()
                .joined(separator: "/")
            NotificationCenter.default.post(
                name: .showTagBrowser, object: nil,
                userInfo: ["initialTag": tagName]
            )
            return true
        }

        if url.host == "person" {
            let personName = url.pathComponents.dropFirst()
                .joined(separator: "/")
            NotificationCenter.default.post(
                name: .showPeopleBrowser, object: nil,
                userInfo: ["initialPerson": personName]
            )
            return true
        }

        return false
    }
}
