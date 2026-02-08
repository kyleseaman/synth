import SwiftUI
import AppKit

// MARK: - Daily Notes View

struct DailyNotesView: View {
    @EnvironmentObject var store: DocumentStore
    @State private var scrollTarget: String?

    private var noteDates: Set<String> {
        Set(
            store.dailyNoteManager.entries
                .filter { $0.exists }
                .map { DailyNoteManager.dateIdentifier($0.date) }
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            // Main scrollable daily notes
            dailyNotesScroll

            Divider()

            // Calendar sidebar
            CalendarSidebarView(
                onSelectDate: { date in scrollToDate(date) },
                noteDates: noteDates
            )
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear {
            loadAllEntries()
            scrollToToday()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .showDailyDate
            )
        ) { notification in
            guard let dateStr = notification.userInfo?["date"]
                as? String else { return }
            scrollTarget = dateStr
        }
    }

    // MARK: - Daily Notes Scroll

    private var dailyNotesScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: []) {
                    ForEach(store.dailyNoteManager.entries) { entry in
                        DailyNoteSection(
                            entry: entry,
                            onContentChange: { newContent in
                                let didCreate = store.dailyNoteManager
                                    .updateContent(
                                        for: entry.id,
                                        newContent: newContent
                                    )
                                if didCreate {
                                    store.loadFileTree()
                                }
                            },
                            store: store
                        )
                        .id(DailyNoteManager.dateIdentifier(entry.date))
                    }
                }
                .padding(.vertical, 16)
            }
            .onChange(of: scrollTarget) { _, target in
                guard let target = target else { return }
                proxy.scrollTo(target, anchor: .top)
                scrollTarget = nil
            }
        }
    }

    // MARK: - Actions

    private func loadAllEntries() {
        guard let workspace = store.workspace else { return }
        store.dailyNoteManager.load(workspace: workspace)
    }

    private func scrollToToday() {
        let todayId = DailyNoteManager.dateIdentifier(Date())
        DispatchQueue.main.async {
            scrollTarget = todayId
        }
    }

    private func scrollToDate(_ date: Date) {
        let dateId = DailyNoteManager.dateIdentifier(date)
        scrollTarget = dateId
    }

}

// MARK: - Daily Note Section

struct DailyNoteSection: View {
    let entry: DailyNoteEntry
    let onContentChange: (String) -> Void
    weak var store: DocumentStore?

    private var isToday: Bool {
        DailyNoteManager.isToday(entry.date)
    }

    private var dateLabel: String {
        DailyNoteManager.displayDate(entry.date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Date header
            dateHeader

            // Content area
            DailyNoteEditor(
                text: entry.content,
                noteURL: entry.url,
                onTextChange: onContentChange,
                noteIndex: store?.noteIndex,
                store: store
            )
            .frame(minHeight: isToday ? 240 : 120)
            .padding(.leading, 20)
            .padding(.trailing, 16)

            if let store = store {
                DailyNoteBacklinks(entry: entry, store: store)
            }

            Divider()
                .padding(.top, 12)
                .padding(.horizontal, 16)
        }
        .padding(.bottom, 8)
    }

    // MARK: - Date Header

    private var dateHeader: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    isToday
                        ? Color.accentColor
                        : Color.secondary.opacity(0.3)
                )
                .frame(width: 3, height: 20)

            Text(dateLabel)
                .font(.system(
                    size: 14,
                    weight: isToday ? .bold : .semibold
                ))
                .foregroundStyle(isToday ? .primary : .secondary)

            if isToday {
                Text("Today")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(Color.accentColor)
                    )
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

}

// MARK: - Daily Note Editor (FormattingTextView with markdown + wiki links)

struct DailyNoteEditor: NSViewRepresentable {
    let text: String
    let noteURL: URL?
    let onTextChange: (String) -> Void
    var noteIndex: NoteIndex?
    weak var store: DocumentStore?

    func makeNSView(context: Context) -> FormattingTextView {
        let textView = FormattingTextView()
        textView.isEditable = true
        textView.isRichText = true
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 4, height: 8)
        textView.allowsUndo = true
        textView.delegate = context.coordinator
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.insertionPointColor = NSColor.textColor
        textView.typingAttributes = [
            .font: NSFont.systemFont(ofSize: 16),
            .foregroundColor: NSColor.textColor
        ]

        let format = MarkdownFormat(noteIndex: noteIndex)
        textView.textStorage?.setAttributedString(
            format.render(text)
        )

        context.coordinator.textView = textView
        context.coordinator.store = store
        context.coordinator.bindImagePasteHandler(to: textView)
        context.coordinator.bindImageOverlay(to: textView)
        context.coordinator.setupAutocomplete()
        context.coordinator.applyFormatting()
        return textView
    }

    func updateNSView(
        _ textView: FormattingTextView, context: Context
    ) {
        context.coordinator.store = store
        context.coordinator.autocomplete.store = store
        let restoredString = MarkdownFormat.restoreImageMarkup(
            in: textView.string
        )
        if !context.coordinator.isEditing
            && !context.coordinator.isFormatting
            && restoredString != text {
            context.coordinator.isFormatting = true
            let format = MarkdownFormat(noteIndex: noteIndex)
            textView.textStorage?.setAttributedString(
                format.render(text)
            )
            if let storage = textView.textStorage {
                let baseFont = NSFont.systemFont(ofSize: 16)
                let baseDirectory = noteURL?
                    .deletingLastPathComponent()
                MarkdownFormat.applyImageRendering(
                    in: storage,
                    baseFont: baseFont,
                    baseDirectoryURL: baseDirectory
                )
            }
            context.coordinator.isFormatting = false
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: DailyNoteEditor
        var textView: FormattingTextView?
        weak var store: DocumentStore?
        var isEditing = false
        var isFormatting = false
        let autocomplete = AutocompleteCoordinator()

        init(_ parent: DailyNoteEditor) { self.parent = parent }

        func setupAutocomplete() {
            autocomplete.textView = textView
            autocomplete.store = store
            autocomplete.onTextChange = { [weak self] in
                guard let self = self,
                      let textView = self.textView
                else { return }
                self.parent.onTextChange(
                    MarkdownFormat.restoreImageMarkup(
                        in: textView.string
                    )
                )
                self.applyFormatting()
            }
            autocomplete.setupObservers()
        }

        // MARK: - Text Delegate

        func textDidBeginEditing(_ notification: Notification) {
            isEditing = true
        }

        func textDidEndEditing(_ notification: Notification) {
            isEditing = false
            store?.dailyNoteManager.saveAll()
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = textView,
                  !isFormatting,
                  !textView.isResizing
            else { return }
            parent.onTextChange(
                MarkdownFormat.restoreImageMarkup(in: textView.string)
            )
            applyFormatting()
        }

        // MARK: - Formatting

        func applyFormatting() {
            guard let textView = textView,
                  let storage = textView.textStorage
            else { return }
            isFormatting = true
            let cursor = textView.selectedRange()
            let cleanText = MarkdownFormat.restoreImageMarkup(
                in: textView.string
            )
            let format = MarkdownFormat(
                noteIndex: parent.noteIndex
            )
            storage.setAttributedString(
                format.render(cleanText)
            )

            let baseFont = NSFont.systemFont(ofSize: 16)
            let baseDirectory = parent.noteURL?
                .deletingLastPathComponent()
            let pendingRenders = MarkdownFormat.applyImageRendering(
                in: storage,
                baseFont: baseFont,
                baseDirectoryURL: baseDirectory
            )
            loadInlineImages(
                pendingRenders,
                storage: storage,
                baseFont: baseFont
            )
            textView.setSelectedRange(cursor)
            isFormatting = false
        }

        private func loadInlineImages(
            _ requests: [MarkdownFormat.PendingImageRender],
            storage: NSTextStorage,
            baseFont: NSFont
        ) {
            let maxSize = MarkdownFormat.maxRenderedImageSize(
                for: baseFont
            )
            for request in requests {
                WorkspaceImageLoader.shared.loadImage(
                    at: request.imageURL,
                    maxSize: maxSize
                ) { [weak self] loadedImage in
                    guard let self,
                          let loadedImage,
                          let textView = self.textView,
                          let currentStorage = textView.textStorage,
                          currentStorage === storage
                    else { return }

                    let storageString = currentStorage.string as NSString
                    let markupEnd = request.markupRange.location
                        + request.markupRange.length
                    guard markupEnd <= storageString.length
                    else { return }

                    let currentMarkup = storageString.substring(
                        with: request.markupRange
                    )
                    let expectedMarkup = MarkdownFormat.attachmentCharacter
                        + request.markupText.dropFirst()
                    guard currentMarkup == expectedMarkup
                    else { return }

                    let attachment = NSTextAttachment()
                    attachment.image = loadedImage

                    if let width = MarkdownFormat.parseImageWidth(
                        from: request.markupText
                    ), loadedImage.size.width > 0 {
                        let scale = width / loadedImage.size.width
                        attachment.bounds = CGRect(
                            x: 0, y: 0,
                            width: width,
                            height: loadedImage.size.height * scale
                        )
                    }

                    let attachStr = NSMutableAttributedString(
                        attributedString: NSAttributedString(
                            attachment: attachment
                        )
                    )
                    let attrRange = NSRange(location: 0, length: 1)
                    attachStr.addAttribute(
                        MarkdownFormat.imageURLKey,
                        value: request.imageURL,
                        range: attrRange
                    )
                    attachStr.addAttribute(
                        MarkdownFormat.imageMarkupKey,
                        value: request.markupText,
                        range: attrRange
                    )
                    currentStorage.replaceCharacters(
                        in: request.attachmentRange,
                        with: attachStr
                    )
                }
            }
        }

        func bindImagePasteHandler(
            to textView: FormattingTextView
        ) {
            textView.imagePasteHandler = { [weak self] image in
                guard let self,
                      let store = self.store,
                      let noteURL = self.parent.noteURL,
                      let relativePath = store.savePastedImageToMedia(
                          image, noteURL: noteURL
                      ) else { return nil }
                return "![Screenshot](\(relativePath))"
            }
        }

        func bindImageOverlay(to textView: FormattingTextView) {
            textView.onImageAction = { [weak self] action, imageURL in
                guard let self else { return }
                switch action {
                case .copy:
                    guard let img = NSImage(contentsOf: imageURL)
                    else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects([img])
                case .delete:
                    self.removeImageMarkup(for: imageURL)
                    try? FileManager.default.trashItem(
                        at: imageURL, resultingItemURL: nil
                    )
                    self.store?.loadFileTree()
                    self.applyFormatting()
                case .open:
                    NotificationCenter.default.post(
                        name: .showImageDetail,
                        object: nil,
                        userInfo: ["mediaURL": imageURL]
                    )
                }
            }
            textView.onImageResize = { [weak self] markup, width in
                self?.handleImageResize(
                    originalMarkup: markup, newWidth: width
                )
            }
        }

        private func handleImageResize(
            originalMarkup: String, newWidth: Int
        ) {
            guard let textView = textView else { return }
            let text = MarkdownFormat.restoreImageMarkup(
                in: textView.string
            )
            let updated = MarkdownFormat.markupWithWidth(
                originalMarkup, width: newWidth
            )
            let newText = text.replacingOccurrences(
                of: originalMarkup, with: updated
            )
            parent.onTextChange(newText)
            applyFormatting()
        }

        private func removeImageMarkup(for imageURL: URL) {
            guard let textView = textView else { return }
            let filename = imageURL.lastPathComponent
            let text = MarkdownFormat.restoreImageMarkup(
                in: textView.string
            )
            // swiftlint:disable:next force_try
            let pattern = try! NSRegularExpression(
                pattern: "!\\[[^\\]]*\\]\\([^)]*"
                    + NSRegularExpression.escapedPattern(
                        for: filename
                    )
                    + "\\)\\n?"
            )
            let cleaned = pattern.stringByReplacingMatches(
                in: text,
                range: NSRange(
                    location: 0, length: text.utf16.count
                ),
                withTemplate: ""
            )
            parent.onTextChange(cleaned)
        }

        // MARK: - Link Click Handling

        func textView(
            _ textView: NSTextView,
            clickedOnLink link: Any,
            at charIndex: Int
        ) -> Bool {
            guard let url = link as? URL else { return false }
            return autocomplete.handleLinkClick(url: url)
        }
    }
}

// MARK: - Daily Note Backlinks

struct DailyNoteBacklinks: View {
    let entry: DailyNoteEntry
    @ObservedObject var store: DocumentStore
    @State private var isExpanded = true

    private static let titleFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM d, yyyy"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt
    }()

    private var filename: String {
        entry.url.deletingPathExtension().lastPathComponent
    }

    private var dateTitle: String {
        Self.titleFormatter.string(from: entry.date)
    }

    private var backlinks: [(url: URL, title: String, snippet: String, relativePath: String)] {
        let byFilename = store.backlinkIndex.links(to: filename)
        let byTitle = store.backlinkIndex.links(to: dateTitle)
        let allURLs = byFilename.union(byTitle)
        let lowerFilename = filename.lowercased()
        return allURLs.compactMap { url in
            let title = url.deletingPathExtension().lastPathComponent
            guard title.lowercased() != lowerFilename else { return nil }
            let snippet = Self.contentPreview(for: url)
            let parent = url.deletingLastPathComponent()
                .lastPathComponent
            return (
                url: url, title: title,
                snippet: snippet, relativePath: parent
            )
        }
        .sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title)
                == .orderedAscending
        }
    }

    /// First meaningful content line from a file (skips headings and blanks).
    private static func contentPreview(for url: URL) -> String {
        guard let content = try? String(
            contentsOf: url, encoding: .utf8
        ) else { return "" }
        let lines = content.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            if trimmed.count > 120 {
                return String(trimmed.prefix(120)) + "..."
            }
            return trimmed
        }
        return ""
    }

    var body: some View {
        let links = backlinks
        if !links.isEmpty {
            VStack(spacing: 0) {
                DisclosureGroup(isExpanded: $isExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(links.prefix(10), id: \.url) { link in
                            BacklinkRow(
                                title: link.title,
                                snippet: link.snippet,
                                relativePath: link.relativePath,
                                url: link.url,
                                onNavigate: { store.open($0) }
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                store.open(link.url)
                            }
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    HStack(spacing: 4) {
                        Text(
                            "Incoming backlinks (\(links.count))"
                        )
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .animation(
                    .easeOut(duration: 0.15), value: isExpanded
                )
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
    }
}
