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
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(target, anchor: .top)
                }
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
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
                onTextChange: onContentChange,
                noteIndex: store?.noteIndex,
                store: store
            )
            .frame(minHeight: isToday ? 240 : 120)
            .padding(.leading, 20)
            .padding(.trailing, 16)

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
        context.coordinator.setupAutocomplete()
        return textView
    }

    func updateNSView(
        _ textView: FormattingTextView, context: Context
    ) {
        context.coordinator.store = store
        context.coordinator.autocomplete.store = store
        if !context.coordinator.isEditing
            && !context.coordinator.isFormatting
            && textView.string != text {
            context.coordinator.isFormatting = true
            let format = MarkdownFormat(noteIndex: noteIndex)
            textView.textStorage?.setAttributedString(
                format.render(text)
            )
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
                self.parent.onTextChange(textView.string)
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
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = textView,
                  !isFormatting else { return }
            parent.onTextChange(textView.string)
            applyFormatting()
        }

        // MARK: - Formatting

        private func applyFormatting() {
            guard let textView = textView,
                  let storage = textView.textStorage
            else { return }
            isFormatting = true
            let cursor = textView.selectedRange()
            let format = MarkdownFormat(
                noteIndex: parent.noteIndex
            )
            storage.setAttributedString(
                format.render(textView.string)
            )
            textView.setSelectedRange(cursor)
            isFormatting = false
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
