import AppKit

// MARK: - Shared autocomplete logic for wiki links, @mentions, #tags
// Used by both MarkdownEditor.Coordinator and DailyNoteEditor.Coordinator

@MainActor
class AutocompleteCoordinator {
    weak var textView: FormattingTextView?
    weak var store: DocumentStore?
    weak var templateStore: TemplateStore?
    let wikiLinkPopover = WikiLinkPopover()
    private var observers: [NSObjectProtocol] = []

    /// Called after autocomplete text replacement finishes.
    /// The parent coordinator should update its binding and re-format.
    var onTextChange: (() -> Void)?

    // MARK: - Observer Setup

    func setupObservers() {
        let center = NotificationCenter.default

        let triggerObs = center.addObserver(
            forName: .wikiLinkTrigger,
            object: nil, queue: .main
        ) { [weak self] notification in
            let mode = notification.userInfo?["mode"] as? String ?? "wikilink"
            let query = notification.userInfo?["query"] as? String ?? ""
            let sourceIdentifier = notification.object.map { ObjectIdentifier($0 as AnyObject) }
            Task { @MainActor [weak self] in
                guard let self,
                      self.matchesCurrentTextView(sourceIdentifier)
                else { return }
                self.handleTrigger(mode: mode, query: query)
            }
        }
        observers.append(triggerObs)

        let dismissObs = center.addObserver(
            forName: .wikiLinkDismiss,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.wikiLinkPopover.dismiss()
            }
        }
        observers.append(dismissObs)

        let queryObs = center.addObserver(
            forName: .wikiLinkQueryUpdate,
            object: nil, queue: .main
        ) { [weak self] notification in
            let query = notification.userInfo?["query"] as? String ?? ""
            let sourceIdentifier = notification.object.map { ObjectIdentifier($0 as AnyObject) }
            Task { @MainActor [weak self] in
                guard let self,
                      self.matchesCurrentTextView(sourceIdentifier)
                else { return }
                self.handleQueryUpdate(query: query)
            }
        }
        observers.append(queryObs)

        let selectObs = center.addObserver(
            forName: .wikiLinkSelect,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleSelect()
            }
        }
        observers.append(selectObs)

        let navObs = center.addObserver(
            forName: .wikiLinkNavigate,
            object: nil, queue: .main
        ) { [weak self] notification in
            let direction = notification.userInfo?["direction"] as? String ?? ""
            let sourceIdentifier = notification.object.map { ObjectIdentifier($0 as AnyObject) }
            Task { @MainActor [weak self] in
                guard let self,
                      self.matchesCurrentTextView(sourceIdentifier)
                else { return }
                self.handleNavigate(direction: direction)
            }
        }
        observers.append(navObs)

        let insertTemplateObs = center.addObserver(
            forName: .insertTemplate,
            object: nil, queue: .main
        ) { [weak self] notification in
            let templateIdentifierText = notification.userInfo?["templateIdentifier"] as? String
            Task { @MainActor [weak self] in
                self?.handleTemplateInsertion(templateIdentifierText: templateIdentifierText)
            }
        }
        observers.append(insertTemplateObs)

        let insertTableObs = center.addObserver(
            forName: .insertTableNow,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.textView?.insertTable()
                self?.onTextChange?()
            }
        }
        observers.append(insertTableObs)

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

    private func matchesCurrentTextView(_ sourceIdentifier: ObjectIdentifier?) -> Bool {
        guard let sourceIdentifier,
              let textView else { return false }
        return ObjectIdentifier(textView) == sourceIdentifier
    }

    private func handleTrigger(mode: String, query: String) {
        guard let textView = textView else { return }
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
        } else if mode == "template" {
            results = templateResults(query: query)
        } else {
            results = store?.noteIndex.search("") ?? []
        }
        wikiLinkPopover.updateResults(
            query: query, results: results
        )
    }

    private func handleQueryUpdate(query: String) {
        guard let textView = textView else { return }

        let results: [NoteSearchResult]
        switch textView.wikiLinkState {
        case .atActive:
            results = atResults(query: query)
        case .hashtagActive:
            results = tagResults(query: query)
        case .slashActive:
            results = templateResults(query: query)
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

    private func handleNavigate(direction: String) {
        if direction == "up" {
            wikiLinkPopover.moveSelectionUp()
        } else {
            wikiLinkPopover.moveSelectionDown()
        }
    }

    private func handleTemplateInsertion(templateIdentifierText: String?) {
        guard let textView = textView,
              textView.window?.firstResponder === textView,
              let identifierText = templateIdentifierText,
              let templateIdentifier = UUID(uuidString: identifierText),
              let template = templateStore?.templates.first(
                  where: { $0.identifier == templateIdentifier }
              ) else { return }

        // Get context for variable expansion
        let title = store?.currentDocumentURL?.deletingPathExtension().lastPathComponent
        let filename = store?.currentDocumentURL?
            .deletingPathExtension().lastPathComponent

        // Expand template with variables
        let expanded = templateStore?.expandTemplate(template, title: title, filename: filename)
            ?? ExpandedTemplate(content: template.content, cursorOffset: nil)

        insertTemplateContent(expanded.content, cursorOffset: expanded.cursorOffset)
    }

    // MARK: - Completion

    private static let dateFileFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt
    }()

    func completeWikiLink(title: String) {
        guard let textView = textView else { return }
        let previousState = textView.wikiLinkState

        // Unfurl ALL date tokens to concrete yyyy-MM-dd filenames
        // e.g. "Today" → "2026-02-07", "Next Monday" → "2026-02-10"
        // The rendering layer displays them relatively (@Today, etc.)
        var completionTitle = title
        if case .slashActive = previousState {
            guard let template = templateStore?.template(named: title) else { return }
            // Get context for variable expansion
            let docTitle = store?.currentDocumentURL?.deletingPathExtension().lastPathComponent
            let filename = store?.currentDocumentURL?
                .deletingPathExtension().lastPathComponent
            let expanded = templateStore?.expandTemplate(template, title: docTitle, filename: filename)
                ?? ExpandedTemplate(content: template.content, cursorOffset: nil)
            completionTitle = expanded.content
        } else if let resolved = DailyNoteResolver.resolveDate(title),
                  title.range(
                      of: "^\\d{4}-\\d{2}-\\d{2}$",
                      options: .regularExpression
                  ) == nil {
            completionTitle = Self.dateFileFormatter.string(from: resolved)
        }

        let result = textView.completeAutocomplete(
            title: completionTitle
        )
        wikiLinkPopover.dismiss()

        if case .slashActive = previousState {
            onTextChange?()
            return
        }

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
            store.addFileToInMemoryTree(fileURL)
        }

        onTextChange?()

        // Auto-save after person mention so the people
        // index updates immediately
        if result.completedPerson {
            store?.save()
        }
    }

    private func insertTemplateContent(_ content: String, cursorOffset: Int? = nil) {
        guard let textView = textView,
              let storage = textView.textStorage else { return }
        let selectionRange = textView.selectedRange()
        storage.replaceCharacters(in: selectionRange, with: content)

        // Position cursor at {{cursor}} location if specified, otherwise at end
        let nextCursor: Int
        if let cursorOffset {
            nextCursor = selectionRange.location + cursorOffset
        } else {
            nextCursor = selectionRange.location + content.count
        }
        textView.setSelectedRange(NSRange(location: nextCursor, length: 0))
        onTextChange?()
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

    func templateResults(query: String) -> [NoteSearchResult] {
        guard let templateStore else { return [] }
        return templateStore.search(query).prefix(20).compactMap { template in
            guard let templateURL = URL(
                string: "synth://template/\(template.identifier.uuidString)"
            ) else { return nil }

            // Build a descriptive label showing category and/or shortcut
            var labelParts: [String] = []
            if let category = template.category {
                labelParts.append(category)
            }
            if let shortcutSlot = template.shortcutSlot {
                labelParts.append("⌥⌘\(shortcutSlot)")
            }
            let label = labelParts.isEmpty ? "Template" : labelParts.joined(separator: " · ")

            return NoteSearchResult(
                id: templateURL,
                title: template.name,
                relativePath: label,
                url: templateURL
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
            store.addFileToInMemoryTree(resolved)
            store.requestDailyDateScroll(token)
            return true
        }

        if url.host == "tag" {
            let tagName = url.pathComponents.dropFirst()
                .joined(separator: "/")
            store?.showTagBrowserModal(tag: tagName)
            return true
        }

        if url.host == "person" {
            let personName = url.pathComponents.dropFirst()
                .joined(separator: "/")
            store?.showPeopleBrowserModal(person: personName)
            return true
        }

        return false
    }
}
