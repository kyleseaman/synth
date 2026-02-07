import SwiftUI
import AppKit

// MARK: - Wiki Link Popover

class WikiLinkPopover {
    private var popover: NSPopover?
    private var hostingController: NSHostingController<WikiLinkPopupView>
    private weak var textView: NSTextView?
    var selectedIndex: Int = 0
    var currentResults: [NoteSearchResult] = []
    var currentQuery: String = ""
    var mode: String = "wikilink"
    var onSelect: ((String) -> Void)?

    init() {
        hostingController = NSHostingController(
            rootView: WikiLinkPopupView()
        )
    }

    func show(at characterIndex: Int, in textView: NSTextView, mode: String) {
        self.textView = textView
        self.mode = mode
        self.selectedIndex = 0

        let rect = textView.firstRect(
            forCharacterRange: NSRange(location: characterIndex, length: 0),
            actualRange: nil
        )
        guard let window = textView.window else { return }
        let windowRect = window.convertFromScreen(rect)
        let viewRect = textView.convert(windowRect, from: nil)

        let pop = NSPopover()
        pop.behavior = .semitransient
        pop.contentViewController = hostingController
        pop.contentSize = NSSize(width: 300, height: 250)
        pop.animates = true
        pop.show(
            relativeTo: CGRect(
                origin: viewRect.origin,
                size: CGSize(width: 1, height: rect.height)
            ),
            of: textView,
            preferredEdge: .maxY
        )
        self.popover = pop
    }

    func updateResults(query: String, results: [NoteSearchResult]) {
        currentQuery = query
        currentResults = results
        selectedIndex = min(selectedIndex, max(results.count - 1, 0))

        var rootView = WikiLinkPopupView()
        rootView.query = query
        rootView.results = results
        rootView.selectedIndex = selectedIndex
        rootView.mode = mode
        rootView.onSelect = { [weak self] title in
            self?.onSelect?(title)
        }
        hostingController.rootView = rootView
    }

    func moveSelectionUp() {
        if selectedIndex > 0 {
            selectedIndex -= 1
            updateResults(query: currentQuery, results: currentResults)
        }
    }

    func moveSelectionDown() {
        let maxIndex = currentResults.isEmpty ? 0 : currentResults.count - 1
        if selectedIndex < maxIndex {
            selectedIndex += 1
            updateResults(query: currentQuery, results: currentResults)
        }
    }

    func selectedTitle() -> String? {
        // Check if the "Create" option is selected (past end of results)
        if currentResults.isEmpty && !currentQuery.isEmpty {
            return currentQuery
        }
        guard selectedIndex >= 0, selectedIndex < currentResults.count else {
            return currentQuery.isEmpty ? nil : currentQuery
        }
        return currentResults[selectedIndex].title
    }

    func dismiss() {
        popover?.close()
        popover = nil
        selectedIndex = 0
        currentResults = []
        currentQuery = ""
    }

    var isShowing: Bool { popover?.isShown ?? false }
}

// MARK: - Wiki Link Popup View

struct WikiLinkPopupView: View {
    var query: String = ""
    var results: [NoteSearchResult] = []
    var selectedIndex: Int = 0
    var mode: String = "wikilink"
    var onSelect: ((String) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // Query display header
            HStack {
                Image(systemName: headerIcon)
                    .foregroundStyle(.secondary)
                Text(query.isEmpty ? searchPlaceholder : displayQuery)
                    .foregroundStyle(query.isEmpty ? .secondary : .primary)
                Spacer()
            }
            .padding(8)

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                        HStack {
                            Image(systemName: rowIcon)
                                .foregroundStyle(.secondary)
                            Text(result.title)
                                .foregroundColor(
                                    mode == "hashtag"
                                        ? Color(nsColor: .systemTeal) : .primary
                                )
                            Spacer()
                            Text(result.relativePath)
                                .foregroundStyle(.tertiary)
                                .font(.caption)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            index == selectedIndex
                                ? Color.accentColor.opacity(0.2) : Color.clear
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onSelect?(result.title)
                        }
                    }

                    if !query.isEmpty {
                        Divider()
                        HStack {
                            Image(systemName: "plus")
                                .foregroundStyle(.secondary)
                            Text(createLabel)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            selectedIndex >= results.count
                                ? Color.accentColor.opacity(0.2) : Color.clear
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if mode == "hashtag" {
                                onSelect?("#\(query)")
                            } else {
                                onSelect?(query)
                            }
                        }
                    }

                    if results.isEmpty && query.isEmpty {
                        Text(emptyText)
                            .foregroundStyle(.secondary)
                            .padding(8)
                    }
                }
            }
            .frame(maxHeight: 200)
        }
        .frame(width: 280)
    }

    // MARK: - Mode-Specific Properties

    private var headerIcon: String {
        switch mode {
        case "at": return "calendar"
        case "hashtag": return "number"
        default: return "magnifyingglass"
        }
    }

    private var rowIcon: String {
        switch mode {
        case "at": return "calendar"
        case "hashtag": return "number"
        default: return "doc.text"
        }
    }

    private var searchPlaceholder: String {
        switch mode {
        case "at": return "Search dates..."
        case "hashtag": return "Search tags..."
        default: return "Search notes..."
        }
    }

    private var displayQuery: String {
        if mode == "hashtag" { return "#\(query)" }
        return query
    }

    private var createLabel: String {
        if mode == "hashtag" { return "Create #\(query)" }
        return "Create \"\(query)\""
    }

    private var emptyText: String {
        switch mode {
        case "hashtag": return "No tags in workspace"
        default: return "No notes in workspace"
        }
    }
}
