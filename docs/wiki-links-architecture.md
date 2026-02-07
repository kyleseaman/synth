# Wiki Links & @Today -- Technical Architecture

## Overview

This document describes the architecture for adding `[[wiki link]]` and `@Today` features to Synth. The design follows existing codebase patterns: NSTextView subclass for keystroke handling, NSViewRepresentable Coordinator for delegate callbacks, `DocumentStore` for state management, and `MarkdownFormat` for rendering.

**Key references**:
- Requirements: `docs/wiki-links-requirements.md`
- Product spec: `docs/wiki-links-product-spec.md`

---

## 1. Keystroke Detection in FormattingTextView

### Approach

Override `insertText(_:replacementRange:)` in `FormattingTextView` to detect trigger sequences. Track a lightweight state machine on the text view itself.

### State Machine

```swift
enum WikiLinkState {
    case idle
    case singleBracket                  // user typed one [
    case wikiLinkActive(start: Int)     // user typed [[, popup is open; start = cursor position after [[
    case atActive(start: Int)           // user typed @, popup is open; start = cursor position after @
}
```

A new property `var wikiLinkState: WikiLinkState = .idle` on `FormattingTextView`.

### insertText Override (modified)

The existing `insertText` in `FormattingTextView` handles bullet conversion (`- ` to `* `). The wiki-link state machine integrates by running after `super.insertText` is called, so both systems coexist without conflict.

```swift
override func insertText(_ string: Any, replacementRange: NSRange) {
    super.insertText(string, replacementRange: replacementRange)

    guard let str = string as? String else { return }

    // Wiki link / @ state machine
    switch wikiLinkState {
    case .idle:
        if str == "[" {
            wikiLinkState = .singleBracket
        } else if str == "@" {
            let start = selectedRange().location
            wikiLinkState = .atActive(start: start)
            NotificationCenter.default.post(
                name: .wikiLinkTrigger,
                object: self,
                userInfo: ["mode": "at", "query": ""]
            )
        }

    case .singleBracket:
        if str == "[" {
            let start = selectedRange().location
            wikiLinkState = .wikiLinkActive(start: start)
            NotificationCenter.default.post(
                name: .wikiLinkTrigger,
                object: self,
                userInfo: ["mode": "wikilink", "query": ""]
            )
        } else {
            wikiLinkState = .idle
        }

    case .wikiLinkActive:
        if str == "\n" {
            // Newline cancels the popup
            wikiLinkState = .idle
            NotificationCenter.default.post(name: .wikiLinkDismiss, object: self)
        } else if str == "]" {
            // User may be manually typing ]] to close. Let them.
            // Check if the next char is also ] to close the link.
            // For now, just update query (the ] is part of the text).
            let query = extractCurrentQuery()
            NotificationCenter.default.post(
                name: .wikiLinkQueryUpdate,
                object: self,
                userInfo: ["query": query]
            )
        } else {
            let query = extractCurrentQuery()
            NotificationCenter.default.post(
                name: .wikiLinkQueryUpdate,
                object: self,
                userInfo: ["query": query]
            )
        }

    case .atActive:
        if str == " " || str == "\n" || str == "\t" {
            // Space/newline/tab dismisses @ popup
            wikiLinkState = .idle
            NotificationCenter.default.post(name: .wikiLinkDismiss, object: self)
        } else {
            let query = extractCurrentQuery()
            NotificationCenter.default.post(
                name: .wikiLinkQueryUpdate,
                object: self,
                userInfo: ["query": query]
            )
        }
    }

    // Existing bullet conversion logic (space after "- " or "* ") runs unchanged below...
    guard let bulletStr = string as? String, bulletStr == " ", let storage = textStorage else { return }
    // ... (rest of existing bullet code)
}
```

**Important**: The existing bullet conversion code in `insertText` must be preserved. The wiki-link state machine runs first (after `super`), then the bullet logic. Since the bullet logic has its own guard (`str == " "`), the two do not conflict.

### deleteBackward Override

```swift
override func deleteBackward(_ sender: Any?) {
    super.deleteBackward(sender)
    switch wikiLinkState {
    case .wikiLinkActive(let start), .atActive(let start):
        if selectedRange().location <= start {
            // User backspaced past the trigger point, dismiss
            wikiLinkState = .idle
            NotificationCenter.default.post(name: .wikiLinkDismiss, object: self)
        } else {
            let query = extractCurrentQuery()
            NotificationCenter.default.post(
                name: .wikiLinkQueryUpdate,
                object: self,
                userInfo: ["query": query]
            )
        }
    default:
        break
    }
}
```

### Helper: extractCurrentQuery

```swift
private func extractCurrentQuery() -> String {
    guard let storage = textStorage else { return "" }
    let cursor = selectedRange().location
    switch wikiLinkState {
    case .wikiLinkActive(let start), .atActive(let start):
        guard cursor > start else { return "" }
        let range = NSRange(location: start, length: cursor - start)
        return (storage.string as NSString).substring(with: range)
    default:
        return ""
    }
}
```

### New Notification Names

Add to the existing `Notification.Name` extension in `ContentView.swift`:

```swift
extension Notification.Name {
    // ... existing names ...
    static let wikiLinkTrigger = Notification.Name("wikiLinkTrigger")
    static let wikiLinkDismiss = Notification.Name("wikiLinkDismiss")
    static let wikiLinkQueryUpdate = Notification.Name("wikiLinkQueryUpdate")
    static let wikiLinkNavigate = Notification.Name("wikiLinkNavigate")
    static let wikiLinkSelect = Notification.Name("wikiLinkSelect")
}
```

---

## 2. Autocomplete Popup

### Why NSPopover (not SwiftUI overlay)

The autocomplete popup must appear at the cursor position inside the NSTextView. SwiftUI overlays on ContentView operate in window coordinates and cannot track the text cursor position within an NSTextView's coordinate system. NSPopover (or a child NSWindow) can be positioned using `NSTextView.firstRect(forCharacterRange:actualRange:)` which returns screen coordinates for any character position.

The existing `FileLauncher` uses a centered SwiftUI overlay, but it does not need to track cursor position. Wiki link autocomplete must appear anchored below the `[[` trigger point and stay positioned even as the user types.

### Implementation: WikiLinkPopover

A new class `WikiLinkPopover` managed by the Coordinator in `MarkdownEditor.swift`.

```swift
class WikiLinkPopover {
    private var popover: NSPopover?
    private let hostingController: NSHostingController<WikiLinkPopupContent>
    private let viewModel = WikiLinkPopupViewModel()
    private weak var textView: NSTextView?

    init() {
        hostingController = NSHostingController(
            rootView: WikiLinkPopupContent(viewModel: viewModel)
        )
    }

    func show(at characterIndex: Int, in textView: NSTextView, mode: String) {
        self.textView = textView
        viewModel.mode = mode

        let rect = textView.firstRect(forCharacterRange:
            NSRange(location: characterIndex, length: 0),
            actualRange: nil
        )
        // Convert screen rect to textView coordinates
        guard let window = textView.window else { return }
        let windowRect = window.convertFromScreen(rect)
        let viewRect = textView.convert(windowRect, from: nil)

        let pop = NSPopover()
        pop.behavior = .semitransient  // stays open while typing in the text view
        pop.contentViewController = hostingController
        pop.contentSize = NSSize(width: 300, height: 320)
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

    func updateQuery(_ query: String, results: [NoteSearchResult]) {
        viewModel.query = query
        viewModel.results = results
        viewModel.selectedIndex = 0
    }

    func moveSelectionUp() {
        viewModel.selectedIndex = max(0, viewModel.selectedIndex - 1)
    }

    func moveSelectionDown() {
        let maxIndex = viewModel.results.count + (viewModel.query.isEmpty ? -1 : 0)  // +1 for "Create" option
        viewModel.selectedIndex = min(maxIndex, viewModel.selectedIndex + 1)
    }

    var selectedResult: NoteSearchResult? {
        guard viewModel.selectedIndex < viewModel.results.count else { return nil }
        return viewModel.results[viewModel.selectedIndex]
    }

    var isCreateNewSelected: Bool {
        !viewModel.query.isEmpty && viewModel.selectedIndex >= viewModel.results.count
    }

    func dismiss() {
        popover?.close()
        popover = nil
    }

    var isShowing: Bool { popover?.isShown ?? false }
}
```

### WikiLinkPopupViewModel and View (SwiftUI)

Using an ObservableObject ViewModel so the NSHostingController can update reactively.

```swift
class WikiLinkPopupViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var results: [NoteSearchResult] = []
    @Published var selectedIndex: Int = 0
    @Published var mode: String = "wikilink"  // "wikilink" or "at"
}

struct WikiLinkPopupContent: View {
    @ObservedObject var viewModel: WikiLinkPopupViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Query display (not editable -- typing happens in the text view)
            HStack {
                Image(systemName: viewModel.mode == "at" ? "calendar" : "magnifyingglass")
                    .foregroundStyle(.secondary)
                Text(viewModel.query.isEmpty ? "Search notes..." : viewModel.query)
                    .foregroundStyle(viewModel.query.isEmpty ? .secondary : .primary)
                Spacer()
            }
            .padding(8)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(viewModel.results.enumerated()), id: \.element.id) { index, result in
                            noteRow(result: result, index: index)
                                .id(index)
                        }

                        // "Create new" option when query is non-empty
                        if !viewModel.query.isEmpty {
                            Divider()
                            createNewRow
                                .id(viewModel.results.count)
                        }
                    }
                }
                .onChange(of: viewModel.selectedIndex) { _, newIndex in
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }
            .frame(maxHeight: 280)  // ~8 rows at ~35pt each
        }
        .frame(width: 300)
        .background(.ultraThinMaterial)
    }

    private func noteRow(result: NoteSearchResult, index: Int) -> some View {
        HStack {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
            Text(result.title)
            Spacer()
            Text(result.relativePath)
                .foregroundStyle(.tertiary)
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(index == viewModel.selectedIndex
            ? Color.accentColor.opacity(0.2) : Color.clear)
    }

    private var createNewRow: some View {
        HStack {
            Image(systemName: "plus.circle")
                .foregroundStyle(.secondary)
            Text("Create \"\(viewModel.query)\"")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(viewModel.selectedIndex >= viewModel.results.count
            ? Color.accentColor.opacity(0.2) : Color.clear)
    }
}
```

### @ Date Popup Variant

When `mode == "at"`, the popup shows date options instead of note results:

```swift
// In WikiLinkPopupContent, when viewModel.mode == "at":
// Show predefined date options: Today, Yesterday, Tomorrow
// Each row shows: calendar icon + keyword + resolved date string
// Example: "calendar | Today | 2026-02-06"
```

The date options are provided as `NoteSearchResult` objects with synthesized titles (`"Today"`, `"Yesterday"`, `"Tomorrow"`) so the same UI works for both modes.

### Keyboard Navigation in FormattingTextView

Intercept arrow keys, Return, Tab, and Escape while the popover is open:

```swift
override func keyDown(with event: NSEvent) {
    switch wikiLinkState {
    case .wikiLinkActive, .atActive:
        switch event.keyCode {
        case 126: // Up arrow
            NotificationCenter.default.post(name: .wikiLinkNavigate,
                object: self, userInfo: ["direction": "up"])
        case 125: // Down arrow
            NotificationCenter.default.post(name: .wikiLinkNavigate,
                object: self, userInfo: ["direction": "down"])
        case 36: // Return -- select current result
            NotificationCenter.default.post(name: .wikiLinkSelect, object: self)
        case 48: // Tab -- also selects (per requirements 3.1.4)
            NotificationCenter.default.post(name: .wikiLinkSelect, object: self)
        case 53: // Escape -- dismiss without inserting
            wikiLinkState = .idle
            NotificationCenter.default.post(name: .wikiLinkDismiss, object: self)
        default:
            super.keyDown(with: event)
        }
    default:
        super.keyDown(with: event)
    }
}
```

### Completion Insertion

When a result is selected, the Coordinator replaces the typed text with the completed link:

- **Wiki link mode**: Replace from the first `[` through cursor with `[[Note Title]]`
- **@ mode**: Replace from `@` through cursor with the date reference

```swift
// In Coordinator
func completeWikiLink(title: String) {
    guard let textView = textView, let storage = textView.textStorage else { return }
    let cursor = textView.selectedRange().location

    switch textView.wikiLinkState {
    case .wikiLinkActive(let start):
        // start = cursor position after "[[", so the "[[" starts at (start - 2)
        let replaceStart = start - 2
        let range = NSRange(location: replaceStart, length: cursor - replaceStart)
        let replacement = "[[\(title)]]"
        storage.replaceCharacters(in: range, with: replacement)
        textView.setSelectedRange(NSRange(location: replaceStart + replacement.count, length: 0))

    case .atActive(let start):
        let replaceStart = start - 1  // include the @
        let range = NSRange(location: replaceStart, length: cursor - replaceStart)
        // For @ dates, resolve at insertion time and store as [[daily/YYYY-MM-DD]]
        // (per product spec Section 6.1: stored format is [[daily/YYYY-MM-DD]])
        if let workspace = store?.workspace,
           let dailyURL = DailyNoteResolver.resolve(title, workspace: workspace) {
            let dateStr = dailyURL.deletingPathExtension().lastPathComponent
            let replacement = "[[daily/\(dateStr)]]"
            storage.replaceCharacters(in: range, with: replacement)
            textView.setSelectedRange(NSRange(location: replaceStart + replacement.count, length: 0))
        } else {
            // Non-date @ completion (shouldn't happen in Phase 1)
            let replacement = "@\(title)"
            storage.replaceCharacters(in: range, with: replacement)
            textView.setSelectedRange(NSRange(location: replaceStart + replacement.count, length: 0))
        }

    default:
        break
    }

    textView.wikiLinkState = .idle
}
```

**Note on @ persistence**: The product spec (Section 6.1) specifies that date references are stored as `[[daily/YYYY-MM-DD]]` in the markdown file, resolved at insertion time. This differs from the requirements doc (Section 4.2) which says `@Today` is stored literally. We follow the product spec: **resolve at insertion time** so the link always points to a concrete date. This avoids the complexity of render-time resolution where `@Today` would mean a different date each day.

---

## 3. NoteIndex

### Purpose

Maintains a searchable index of all note filenames in the workspace for fast fuzzy matching in the autocomplete popup. Performance target: fuzzy search completes in <16ms for 10,000 notes (per requirements Section 9.5).

### Data Structure

```swift
struct NoteSearchResult: Identifiable {
    let id: URL
    let title: String         // filename without extension
    let relativePath: String  // parent folder name for disambiguation
    let url: URL
}

class NoteIndex: ObservableObject {
    @Published private(set) var notes: [NoteSearchResult] = []
    private var allNotes: [NoteSearchResult] = []

    func rebuild(from fileTree: [FileTreeNode], workspace: URL?) {
        allNotes = Self.flatten(fileTree, workspace: workspace)
        notes = allNotes
    }

    /// Search notes using fuzzy matching. Reuses String.fuzzyScore from FileLauncher.swift.
    /// Returns results sorted by score, with recently opened files boosted.
    func search(_ query: String, recentFiles: [URL] = []) -> [NoteSearchResult] {
        if query.isEmpty {
            // Sort by recency first, then alphabetical
            let recentSet = Set(recentFiles)
            let recent = recentFiles.compactMap { url in
                allNotes.first { $0.url == url }
            }
            let others = allNotes
                .filter { !recentSet.contains($0.url) }
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            return recent + Array(others.prefix(20 - recent.count))
        }
        return allNotes
            .compactMap { note -> (NoteSearchResult, Int)? in
                guard let score = note.title.fuzzyScore(query) else { return nil }
                let recentBonus = recentFiles.contains(note.url) ? 2000 : 0
                return (note, score + recentBonus)
            }
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
    }

    /// Find exact match by title (case-insensitive). Used for link resolution.
    /// Implements disambiguation: prefers same-directory, then workspace root, then alphabetical.
    func resolve(_ title: String, from sourceURL: URL?, workspace: URL?) -> NoteSearchResult? {
        let lowered = title.lowercased()

        // Handle path-based links like "daily/2026-02-06"
        if title.contains("/"), let workspace = workspace {
            let targetURL = workspace.appendingPathComponent("\(title).md")
            if let match = allNotes.first(where: { $0.url == targetURL }) {
                return match
            }
        }

        let matches = allNotes.filter { $0.title.lowercased() == lowered }
        if matches.isEmpty { return nil }
        if matches.count == 1 { return matches.first }

        // Disambiguation per requirements Section 6.5:
        // 1. Same folder as the linking note
        if let sourceDir = sourceURL?.deletingLastPathComponent() {
            if let sameDir = matches.first(where: {
                $0.url.deletingLastPathComponent() == sourceDir
            }) {
                return sameDir
            }
        }
        // 2. Workspace root
        if let workspace = workspace {
            if let root = matches.first(where: {
                $0.url.deletingLastPathComponent() == workspace
            }) {
                return root
            }
        }
        // 3. Alphabetically first by path
        return matches.sorted { $0.url.path < $1.url.path }.first
    }

    private static func flatten(_ nodes: [FileTreeNode], workspace: URL?) -> [NoteSearchResult] {
        var result: [NoteSearchResult] = []
        for node in nodes {
            if !node.isDirectory {
                let ext = node.url.pathExtension.lowercased()
                // Only .md and .txt files per requirements Section 3.1.2
                if ext == "md" || ext == "txt" {
                    let title = node.url.deletingPathExtension().lastPathComponent
                    let parent = node.url.deletingLastPathComponent().lastPathComponent
                    result.append(NoteSearchResult(
                        id: node.url, title: title,
                        relativePath: parent, url: node.url
                    ))
                }
            }
            if let children = node.children {
                result.append(contentsOf: flatten(children, workspace: workspace))
            }
        }
        return result
    }
}
```

### Integration with DocumentStore

NoteIndex lives on `DocumentStore` as a property. Rebuilt whenever `fileTree` changes:

```swift
// In DocumentStore
let noteIndex = NoteIndex()

// In loadFileTree(), after setting self.fileTree:
noteIndex.rebuild(from: tree, workspace: workspace)
```

Reuses the existing `fuzzyScore` extension from `FileLauncher.swift` (already available on `String`).

---

## 4. Wiki Link Rendering in MarkdownFormat

### Approach

Add a new regex pass in `applyInlineFormatting` to detect `[[...]]` patterns and style them as clickable links. This pass runs **first** (before bold/italic/code) since wiki link content should not be further reformatted by those passes.

### Implementation

Add to `MarkdownFormat.applyInlineFormatting(_:baseFont:)` as the **first** inline formatting pass:

```swift
// Wiki links [[Note Title]] or [[Note Title|Display Text]]
// Must run before bold/italic/code to prevent inner reformatting
// swiftlint:disable:next force_try
let wikiPattern = try! NSRegularExpression(pattern: "\\[\\[(.+?)\\]\\]")
let wikiRange = NSRange(location: 0, length: str.string.utf16.count)
for match in wikiPattern.matches(in: str.string, range: wikiRange).reversed() {
    if let fullRange = Range(match.range, in: str.string),
       let innerRange = Range(match.range(at: 1), in: str.string) {
        let rawContent = String(str.string[innerRange])

        // Skip empty or whitespace-only links per requirements Section 6.8
        guard !rawContent.trimmingCharacters(in: .whitespaces).isEmpty else { continue }

        // Support alias syntax: [[Actual Title|Display Text]]
        // per requirements Section 6.4
        let parts = rawContent.split(separator: "|", maxSplits: 1)
        let noteTitle = String(parts[0]).trimmingCharacters(in: .whitespaces)
        let displayText = parts.count > 1
            ? String(parts[1]).trimmingCharacters(in: .whitespaces)
            : noteTitle

        let encodedTitle = noteTitle.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed) ?? noteTitle
        let linkURL = URL(string: "synth://wiki/\(encodedTitle)")!

        // Determine link styling based on whether target note exists
        let noteExists = noteIndex?.resolve(noteTitle, from: nil, workspace: nil) != nil
        let linkColor: NSColor
        let underlineStyle: Int
        if noteExists {
            linkColor = NSColor.controlAccentColor
            underlineStyle = 0  // no underline by default; underline on hover (handled in text view)
        } else {
            linkColor = NSColor.systemRed.withAlphaComponent(0.8)
            underlineStyle = NSUnderlineStyle.patternDash.rawValue | NSUnderlineStyle.single.rawValue
        }

        let fontWeight = NSFontManager.shared.convert(baseFont, toHaveTrait: [])
        // Use .medium weight per product spec Section 3.1
        let mediumFont = NSFont.systemFont(ofSize: baseFont.pointSize, weight: .medium)

        let replacement = NSAttributedString(
            string: displayText,
            attributes: [
                .font: mediumFont,
                .foregroundColor: linkColor,
                .underlineStyle: underlineStyle,
                .link: linkURL,
                .cursor: NSCursor.pointingHand
            ]
        )
        str.replaceCharacters(in: NSRange(fullRange, in: str.string), with: replacement)
    }
}
```

### @ Date Reference Rendering

Also add in `applyInlineFormatting`, after wiki links:

```swift
// Date references: [[daily/YYYY-MM-DD]] rendered as date pills
// swiftlint:disable:next force_try
let dailyPattern = try! NSRegularExpression(pattern: "\\[\\[daily/(\\d{4}-\\d{2}-\\d{2})\\]\\]")
let dailyRange = NSRange(location: 0, length: str.string.utf16.count)
for match in dailyPattern.matches(in: str.string, range: dailyRange).reversed() {
    if let fullRange = Range(match.range, in: str.string),
       let dateRange = Range(match.range(at: 1), in: str.string) {
        let dateStr = String(str.string[dateRange])
        let linkURL = URL(string: "synth://daily/\(dateStr)")!

        // Format display: show friendly date if it's today/yesterday/tomorrow
        let displayText = DailyNoteResolver.friendlyName(for: dateStr) ?? dateStr

        let replacement = NSAttributedString(
            string: "@\(displayText)",
            attributes: [
                .font: NSFont.systemFont(ofSize: baseFont.pointSize, weight: .medium),
                .foregroundColor: NSColor.controlAccentColor,
                .link: linkURL,
                .backgroundColor: NSColor.controlAccentColor.withAlphaComponent(0.12)
            ]
        )
        str.replaceCharacters(in: NSRange(fullRange, in: str.string), with: replacement)
    }
}
```

### NoteIndex Injection into MarkdownFormat

`MarkdownFormat` needs access to `NoteIndex` for broken link detection. Add an optional property:

```swift
struct MarkdownFormat: DocumentFormat {
    var noteIndex: NoteIndex?
    var currentFileURL: URL?  // for disambiguation in link resolution

    func render(_ text: String) -> NSAttributedString { ... }
    private func applyInlineFormatting(_ str: NSMutableAttributedString, baseFont: NSFont) {
        // Uses self.noteIndex and self.currentFileURL in wiki link pass
    }
}
```

### Ordering of Inline Formatting Passes

1. Wiki links `[[...]]` (new)
2. Daily note links `[[daily/...]]` (new)
3. Bold `**text**` (existing)
4. Italic `*text*` (existing)
5. Inline code `` `text` `` (existing)

Wiki links run first so their content is not split by bold/italic patterns.

---

## 5. Link Click Handling

### Approach

Use the `NSTextViewDelegate` method `textView(_:clickedOnLink:at:)` in the existing Coordinator. This is the standard NSTextView approach for handling `.link` attributes and requires no custom mouse event handling.

### Implementation

Add to `MarkdownEditor.Coordinator`:

```swift
func textView(
    _ textView: NSTextView,
    clickedOnLink link: Any,
    at charIndex: Int
) -> Bool {
    guard let url = link as? URL, url.scheme == "synth" else { return false }

    if url.host == "wiki" {
        let noteTitle = url.pathComponents.dropFirst().joined(separator: "/")
            .removingPercentEncoding ?? ""
        handleWikiLinkClick(noteTitle: noteTitle)
        return true
    }

    if url.host == "daily" {
        let dateStr = url.pathComponents.dropFirst().joined(separator: "/")
        handleDailyLinkClick(dateStr: dateStr)
        return true
    }

    return false
}

private func handleWikiLinkClick(noteTitle: String) {
    guard let store = store else { return }
    let currentURL = store.currentIndex >= 0 ? store.openFiles[store.currentIndex].url : nil

    if let match = store.noteIndex.resolve(noteTitle, from: currentURL, workspace: store.workspace) {
        store.open(match.url)
    } else {
        // Note doesn't exist -- prompt to create
        promptCreateNote(title: noteTitle)
    }
}

private func promptCreateNote(title: String) {
    guard let store = store, let workspace = store.workspace else { return }

    let alert = NSAlert()
    alert.messageText = "Create '\(title)'?"
    alert.informativeText = "This note does not exist yet. Create it?"
    alert.addButton(withTitle: "Create")
    alert.addButton(withTitle: "Cancel")

    if alert.runModal() == .alertFirstButtonReturn {
        // Strip illegal filesystem characters per requirements Section 6.4
        let safeName = title
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
        let url = workspace.appendingPathComponent("\(safeName).md")
        let content = "# \(title)\n\n"
        try? content.write(to: url, atomically: true, encoding: .utf8)
        store.loadFileTree()
        store.open(url)
    }
}

private func handleDailyLinkClick(dateStr: String) {
    guard let store = store, let workspace = store.workspace else { return }
    let url = workspace
        .appendingPathComponent("daily")
        .appendingPathComponent("\(dateStr).md")
    DailyNoteResolver.ensureExists(at: url, dateStr: dateStr)
    store.loadFileTree()
    store.open(url)
}
```

### Accessing DocumentStore from Coordinator

The Coordinator needs access to `DocumentStore`. Add a weak reference:

```swift
class Coordinator: NSObject, NSTextViewDelegate {
    // ... existing properties ...
    weak var store: DocumentStore?
}
```

Set it in `updateNSView` by passing it through the `MarkdownEditor` struct:

```swift
struct MarkdownEditor: NSViewRepresentable {
    // ... existing bindings ...
    var store: DocumentStore?  // new -- set from EditorViewSimple's @EnvironmentObject

    func makeNSView(context: Context) -> NSScrollView {
        // ... existing setup ...
        context.coordinator.store = store
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.store = store  // keep up to date
        // ... existing update logic ...
    }
}
```

In `EditorViewSimple`, pass the store through:

```swift
MarkdownEditor(
    text: $text,
    scrollOffset: $scrollOffset,
    linePositions: $linePositions,
    selectedText: $selectedText,
    selectedLineRange: $selectedLineRange,
    store: store
)
```

---

## 6. @Today and Daily Notes

### Trigger

When user types `@`, the autocomplete popup opens in "at" mode with predefined date options:

- **Today** (YYYY-MM-DD)
- **Yesterday** (YYYY-MM-DD)
- **Tomorrow** (YYYY-MM-DD)

As the user types after `@`, options are filtered (e.g., `@to` shows Today and Tomorrow).

### DailyNoteResolver

```swift
struct DailyNoteResolver {
    static let dailyFolder = "daily"

    private static let isoFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt
    }()

    private static let longFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM d, yyyy"
        return fmt
    }()

    /// Resolve a keyword (Today, Yesterday, Tomorrow) to a daily note URL.
    static func resolve(_ token: String, workspace: URL) -> URL? {
        guard let date = dateForToken(token) else { return nil }
        let filename = isoFormatter.string(from: date)
        let folder = workspace.appendingPathComponent(dailyFolder)
        return folder.appendingPathComponent("\(filename).md")
    }

    /// Get the date for a keyword token.
    static func dateForToken(_ token: String) -> Date? {
        switch token.lowercased() {
        case "today": return Date()
        case "yesterday": return Calendar.current.date(byAdding: .day, value: -1, to: Date())
        case "tomorrow": return Calendar.current.date(byAdding: .day, value: 1, to: Date())
        default: return nil
        }
    }

    /// Format an ISO date string to a friendly name if it's today/yesterday/tomorrow.
    static func friendlyName(for dateStr: String) -> String? {
        guard let date = isoFormatter.date(from: dateStr) else { return nil }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        return nil  // return nil for other dates, caller will use ISO string
    }

    /// Create the daily note file if it doesn't exist.
    /// Template uses long-form date heading per requirements Section 3.3.4.
    static func ensureExists(at url: URL, dateStr: String) {
        let folder = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            let longDate: String
            if let date = isoFormatter.date(from: dateStr) {
                longDate = longFormatter.string(from: date)
            } else {
                longDate = dateStr
            }
            let content = "# \(longDate)\n\n"
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// Generate the predefined date options for the @ popup.
    static func dateOptions() -> [(keyword: String, dateStr: String)] {
        let today = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        return [
            ("Today", isoFormatter.string(from: today)),
            ("Yesterday", isoFormatter.string(from: yesterday)),
            ("Tomorrow", isoFormatter.string(from: tomorrow))
        ]
    }
}
```

### Storage Format Decision

**The `@` keyword is resolved to a concrete date at insertion time.** In the `.md` file, a date reference appears as `[[daily/2026-02-06]]`, not as `@Today`. This means:

- The link always points to the correct date, even when viewed on a different day.
- The render pass detects `[[daily/YYYY-MM-DD]]` and displays it as `@Today` (or the ISO date) based on the current date at render time.
- The raw markdown is portable and self-documenting.

---

## 7. BacklinkIndex

### Purpose

Tracks which notes link to which other notes, enabling a "Backlinks" section below the editor content. Per requirements Section 5.1, stores both links and context snippets.

### Data Structure

```swift
class BacklinkIndex: ObservableObject {
    /// Map from note title (lowercased) -> set of URLs that reference it
    @Published private(set) var incomingLinks: [String: Set<URL>] = [:]

    /// Map from source URL -> set of note titles it links to (for incremental updates)
    private var outgoingLinks: [URL: Set<String>] = [:]

    /// Map from source URL -> (note title -> context line containing the link)
    @Published private(set) var contextSnippets: [URL: [String: String]] = [:]

    // swiftlint:disable:next force_try
    private let wikiPattern = try! NSRegularExpression(pattern: "\\[\\[(.+?)\\]\\]")

    /// Full rebuild -- scans all .md files. Run on background thread.
    /// Performance target: <2 seconds for 10,000 notes (requirements Section 3.4.3).
    func rebuild(fileTree: [FileTreeNode]) {
        var newIncoming: [String: Set<URL>] = [:]
        var newOutgoing: [URL: Set<String>] = [:]
        var newSnippets: [URL: [String: String]] = [:]

        let files = flattenMarkdownFiles(fileTree)
        for file in files {
            guard let content = try? String(contentsOf: file.url, encoding: .utf8) else { continue }
            let (targets, snippets) = scanFile(content: content)
            newOutgoing[file.url] = targets
            newSnippets[file.url] = snippets
            for target in targets {
                newIncoming[target, default: []].insert(file.url)
            }
        }

        DispatchQueue.main.async {
            self.incomingLinks = newIncoming
            self.outgoingLinks = newOutgoing
            self.contextSnippets = newSnippets
        }
    }

    /// Incremental update for a single file (on save).
    /// Performance target: <100ms (requirements Section 3.4.3).
    func updateFile(_ url: URL, content: String) {
        // Remove old outgoing links for this file
        if let oldTargets = outgoingLinks[url] {
            for target in oldTargets {
                incomingLinks[target]?.remove(url)
                if incomingLinks[target]?.isEmpty == true {
                    incomingLinks.removeValue(forKey: target)
                }
            }
        }

        // Re-scan the file
        let (targets, snippets) = scanFile(content: content)
        outgoingLinks[url] = targets
        contextSnippets[url] = snippets
        for target in targets {
            incomingLinks[target, default: []].insert(url)
        }
    }

    /// Get all URLs that link to a given note title.
    func links(to noteTitle: String) -> Set<URL> {
        incomingLinks[noteTitle.lowercased()] ?? []
    }

    /// Get the context snippet for a given source URL linking to a given target.
    func snippet(from source: URL, to noteTitle: String) -> String? {
        contextSnippets[source]?[noteTitle.lowercased()]
    }

    // MARK: - Private

    private func scanFile(content: String) -> (targets: Set<String>, snippets: [String: String]) {
        var targets: Set<String> = []
        var snippets: [String: String] = [:]
        let lines = content.components(separatedBy: "\n")

        for line in lines {
            let range = NSRange(location: 0, length: line.utf16.count)
            let matches = wikiPattern.matches(in: line, range: range)
            for match in matches {
                if let innerRange = Range(match.range(at: 1), in: line) {
                    var target = String(line[innerRange]).lowercased()
                    // Strip alias if present
                    if let pipeIndex = target.firstIndex(of: "|") {
                        target = String(target[..<pipeIndex])
                            .trimmingCharacters(in: .whitespaces)
                    }
                    targets.insert(target)
                    // Store context: the full line, trimmed
                    snippets[target] = line.trimmingCharacters(in: .whitespaces)
                }
            }
        }

        return (targets, snippets)
    }

    private func flattenMarkdownFiles(_ nodes: [FileTreeNode]) -> [FileTreeNode] {
        var result: [FileTreeNode] = []
        for node in nodes {
            if !node.isDirectory, node.url.pathExtension.lowercased() == "md" {
                result.append(node)
            }
            if let children = node.children {
                result.append(contentsOf: flattenMarkdownFiles(children))
            }
        }
        return result
    }
}
```

### Integration with DocumentStore

```swift
// In DocumentStore
let backlinkIndex = BacklinkIndex()

// In loadFileTree(), after setting self.fileTree:
let treeSnapshot = tree
Task.detached(priority: .utility) { [weak self] in
    self?.backlinkIndex.rebuild(fileTree: treeSnapshot)
}

// In save(), after writing the file -- incremental update:
let content = openFiles[currentIndex].content.string
let url = openFiles[currentIndex].url
backlinkIndex.updateFile(url, content: content)
```

### BacklinksView

A collapsible section below the editor content in `EditorViewSimple`:

```swift
// In EditorViewSimple body, after MarkdownEditor:
BacklinksSection(
    noteTitle: currentNoteTitle,
    backlinkIndex: store.backlinkIndex,
    noteIndex: store.noteIndex,
    onNavigate: { url in store.open(url) }
)
```

```swift
struct BacklinksSection: View {
    let noteTitle: String
    @ObservedObject var backlinkIndex: BacklinkIndex
    let noteIndex: NoteIndex
    let onNavigate: (URL) -> Void
    @AppStorage("backlinksExpanded") private var isExpanded = false

    var backlinks: [(url: URL, title: String, snippet: String)] {
        let urls = backlinkIndex.links(to: noteTitle)
        return urls.compactMap { url in
            let title = url.deletingPathExtension().lastPathComponent
            let snippet = backlinkIndex.snippet(from: url, to: noteTitle) ?? ""
            return (url: url, title: title, snippet: snippet)
        }
        .sorted { $0.title < $1.title }
    }

    var body: some View {
        if !backlinks.isEmpty {
            Divider()
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(backlinks, id: \.url) { link in
                        BacklinkRow(title: link.title, snippet: link.snippet)
                            .onTapGesture { onNavigate(link.url) }
                    }
                }
                .padding(.horizontal, 16)
            } label: {
                Text("Backlinks (\(backlinks.count))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}
```

---

## 8. File Rename/Delete Handling

### Rename with Reference Update (requirements Section 6.1)

When a note is renamed via `DocumentStore.promptRename`, scan for references and offer to update them:

```swift
// In DocumentStore.promptRename, after successful rename:
func updateReferencesAfterRename(oldName: String, newName: String) {
    guard let workspace = workspace else { return }
    let links = backlinkIndex.links(to: oldName)
    guard !links.isEmpty else { return }

    let alert = NSAlert()
    alert.messageText = "Update \(links.count) reference(s)?"
    alert.informativeText = "Update [[\(oldName)]] to [[\(newName)]] in \(links.count) file(s)?"
    alert.addButton(withTitle: "Update All")
    alert.addButton(withTitle: "Skip")

    if alert.runModal() == .alertFirstButtonReturn {
        for url in links {
            guard var content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            content = content.replacingOccurrences(
                of: "[[\(oldName)]]",
                with: "[[\(newName)]]"
            )
            // Also handle alias form
            // [[Old Name|display]] -> [[New Name|display]]
            // Use regex for this
            try? content.write(to: url, atomically: true, encoding: .utf8)

            // Reload if this file is open
            if let idx = openFiles.firstIndex(where: { $0.url == url }) {
                if let reloaded = Document.load(from: url) {
                    openFiles[idx] = reloaded
                }
            }
        }
        loadFileTree()  // triggers NoteIndex + BacklinkIndex rebuild
    }
}
```

### Delete Handling

When a note is deleted via `DocumentStore.delete`:

1. **NoteIndex** and **BacklinkIndex** automatically update on next `loadFileTree()` call.
2. All `[[Deleted Note]]` references render with broken-link styling (red, dashed underline) on next render.
3. No automatic cleanup of references -- user must manually update or remove.

### Broken Link Detection

In the wiki link rendering pass (Section 4), the `noteExists` check uses `noteIndex.resolve()`. When a linked note doesn't exist, the link renders with:
- `NSColor.systemRed` at 80% opacity
- `NSUnderlineStyle.patternDash | NSUnderlineStyle.single`

---

## File-by-File Change Summary

### New Files

| File | Purpose |
|------|---------|
| `SynthApp/NoteIndex.swift` | `NoteSearchResult` model, `NoteIndex` class with fuzzy search and link resolution |
| `SynthApp/BacklinkIndex.swift` | `BacklinkIndex` class with full/incremental rebuild, context snippets |
| `SynthApp/WikiLinkPopover.swift` | `WikiLinkPopover` class (NSPopover wrapper), `WikiLinkPopupViewModel`, `WikiLinkPopupContent` (SwiftUI view) |
| `SynthApp/DailyNoteResolver.swift` | `DailyNoteResolver` struct, date token resolution, daily note creation with template |
| `SynthApp/BacklinksSection.swift` | `BacklinksSection` SwiftUI view, `BacklinkRow`, collapsible backlinks UI |

### Modified Files

| File | Changes |
|------|---------|
| `SynthApp/MarkdownEditor.swift` (FormattingTextView) | Add `WikiLinkState` enum and property. Override `insertText` to detect `[[` and `@` triggers (coexists with existing bullet logic). Override `deleteBackward` to dismiss on backspace past trigger. Override `keyDown` for arrow/return/tab/escape in popup. Add `extractCurrentQuery()` helper. |
| `SynthApp/MarkdownEditor.swift` (MarkdownFormat) | Add `noteIndex: NoteIndex?` and `currentFileURL: URL?` properties. Add wiki link regex pass as first inline formatting step. Add daily note link regex pass. Support `[[Title\|Alias]]` syntax. Broken link detection via `noteIndex.resolve()`. |
| `SynthApp/MarkdownEditor.swift` (Coordinator) | Add `weak var store: DocumentStore?`. Add `WikiLinkPopover` property. Wire up NotificationCenter observers for wiki link events in `makeNSView`. Add `textView(_:clickedOnLink:at:)` delegate method. Add `completeWikiLink(title:)`. Add `handleWikiLinkClick`, `handleDailyLinkClick`, `promptCreateNote` methods. |
| `SynthApp/MarkdownEditor.swift` (MarkdownEditor struct) | Add `store: DocumentStore?` parameter. Pass to Coordinator in `makeNSView`/`updateNSView`. |
| `SynthApp/ContentView.swift` | Add new `Notification.Name` constants for wiki link events (`.wikiLinkTrigger`, `.wikiLinkDismiss`, `.wikiLinkQueryUpdate`, `.wikiLinkNavigate`, `.wikiLinkSelect`). |
| `SynthApp/ContentView.swift` (EditorViewSimple) | Pass `store` to `MarkdownEditor`. Add `BacklinksSection` below the editor. |
| `SynthApp/DocumentStore.swift` | Add `noteIndex: NoteIndex` and `backlinkIndex: BacklinkIndex` properties. Rebuild both in `loadFileTree()`. Add incremental backlink update in `save()`. Add `updateReferencesAfterRename()` method. Call it from `promptRename()`. |

### Unchanged Files

`Document.swift`, `FileTreeNode.swift`, `FileLauncher.swift`, `LinkStore.swift`, `LinksView.swift`, `LinkCaptureView.swift`, `SynthApp.swift`, `Theme.swift`, `ACPClient.swift`, `ACPTypes.swift`, `ChatBubbles.swift`, `ChatInputBar.swift`, `DocumentChatTray.swift`, `DocumentChatState.swift`, `GlobalHotkeyMonitor.swift`, `SettingsView.swift`.

---

## Interaction Flow

```
User types "[[no"
  |
  v
FormattingTextView.insertText("[") -> state = .singleBracket
FormattingTextView.insertText("[") -> state = .wikiLinkActive(start: cursorPos)
  Posts .wikiLinkTrigger notification with mode="wikilink"
  |
  v
Coordinator receives .wikiLinkTrigger
  -> Opens WikiLinkPopover at cursor via firstRect(forCharacterRange:)
  -> Queries NoteIndex.search("", recentFiles: store.recentFiles) for initial results
  -> Updates popup ViewModel
  |
  v
User types "no"
  FormattingTextView.insertText("n"), then "o"
  Each posts .wikiLinkQueryUpdate with query="n", then "no"
  Coordinator queries NoteIndex.search("no", recentFiles: ...)
  -> Updates popup ViewModel with filtered results
  |
  v
User presses Down arrow, then Return (or Tab)
  FormattingTextView.keyDown posts .wikiLinkNavigate(down), then .wikiLinkSelect
  Coordinator calls completeWikiLink(title: "Notes on Architecture")
  -> Replaces "[[no" with "[[Notes on Architecture]]" in text storage
  -> Dismisses popover
  -> State resets to .idle
  -> textDidChange fires -> parent.text updates -> re-render
  |
  v
MarkdownFormat.render re-renders the text
  applyInlineFormatting detects [[Notes on Architecture]]
  -> noteIndex.resolve("Notes on Architecture") finds the file
  -> Renders "Notes on Architecture" in accent color, medium weight, with .link attribute
  -> [[ and ]] delimiters are hidden
  |
  v
User clicks the rendered link
  NSTextView detects click on .link attribute
  Coordinator.textView(_:clickedOnLink:at:) called with synth://wiki/...
  -> Calls store.noteIndex.resolve("Notes on Architecture", ...)
  -> Calls store.open(matchingURL)
  -> Note opens in a tab (or switches to existing tab)
```

---

## Design Decisions & Rationale

1. **NSPopover over SwiftUI overlay**: The popup must track cursor position inside NSTextView. `firstRect(forCharacterRange:)` provides screen coordinates that NSPopover can use directly. A SwiftUI overlay on ContentView would require complex coordinate conversion and wouldn't track scrolling properly.

2. **NotificationCenter for FormattingTextView -> Coordinator communication**: Follows the existing app pattern (`.toggleChat`, `.showFileLauncher`, etc.). The text view doesn't have a direct reference to the Coordinator, so notifications are the cleanest bridge without adding coupling.

3. **State machine on FormattingTextView**: Keeps state close to where keystrokes are processed. The alternative (tracking in Coordinator via delegate) would require additional delegate methods and more complex state synchronization.

4. **NoteIndex as separate class (not on FileTreeNode)**: Decoupled from file tree scanning. Can be tested independently. Provides both fuzzy search (for autocomplete) and exact resolution with disambiguation (for link clicking). Reuses existing `fuzzyScore` from FileLauncher.

5. **synth:// URL scheme for links**: Uses `.link` attribute on NSAttributedString which NSTextView natively handles via `textView(_:clickedOnLink:at:)` delegate method. No custom mouse event handling needed. The custom scheme prevents accidental web browser navigation.

6. **Rendering strips [[ ]] delimiters**: The raw markdown keeps `[[Note Title]]` for persistence and portability, but the rendered view shows just "Note Title" styled as a link. This matches Obsidian's behavior.

7. **Date resolution at insertion time**: `@Today` is immediately resolved to `[[daily/2026-02-06]]` in the markdown. The render pass shows it as `@Today` or the ISO date. This avoids ambiguity about which date a link refers to when viewing a note on a different day.

8. **Incremental backlink updates on save**: Full rebuild on workspace changes; single-file re-scan on save. Meets the <100ms target for incremental updates. Full rebuild targets <2 seconds for 10,000 notes.

9. **Rename prompts for reference updates**: Rather than silently breaking links or silently updating them, the user is prompted with the count and asked to approve. This keeps the user in control.

10. **Alias support via pipe syntax**: `[[Actual Title|Display Text]]` is parsed in the rendering pass. The link URL uses "Actual Title" for resolution, while "Display Text" is shown. This is deferred from initial implementation but the architecture supports it from the start.

---

## Implementation Phases (aligned with requirements Section 8)

| Phase | Components to Build | Estimated Complexity |
|-------|-------------------|---------------------|
| **Phase 1** | `MarkdownFormat` wiki link rendering, `NoteIndex`, link click handling | Medium -- extends existing rendering pipeline |
| **Phase 2** | `WikiLinkState` on `FormattingTextView`, `WikiLinkPopover`, keystroke detection, completion insertion | High -- NSPopover positioning, state machine, keyboard interception |
| **Phase 3** | `DailyNoteResolver`, `@` trigger, date popup variant, daily note creation | Medium -- builds on Phase 2 popup infrastructure |
| **Phase 4** | `BacklinkIndex` (full + incremental), `BacklinksSection` UI | Medium -- independent of popup, mostly new code |
| **Phase 5** | Rename refactoring, broken link detection, create-on-click | Low-Medium -- builds on existing index infrastructure |
