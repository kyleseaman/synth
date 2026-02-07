import SwiftUI
import AppKit

protocol DocumentFormat {
    func render(_ text: String) -> NSAttributedString
    func toPlainText(_ attributed: NSAttributedString) -> String
}

struct MarkdownFormat: DocumentFormat {
    var noteIndex: NoteIndex?

    func render(_ text: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let bodyFont = NSFont.systemFont(ofSize: 16)
        let defaultAttrs: [NSAttributedString.Key: Any] = [.font: bodyFont, .foregroundColor: NSColor.textColor]

        let lines = text.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            var attrs = defaultAttrs
            var content = line

            if line.hasPrefix("# ") {
                content = String(line.dropFirst(2))
                attrs[.font] = NSFont.systemFont(ofSize: 28, weight: .bold)
            } else if line.hasPrefix("## ") {
                content = String(line.dropFirst(3))
                attrs[.font] = NSFont.systemFont(ofSize: 22, weight: .bold)
            } else if line.hasPrefix("### ") {
                content = String(line.dropFirst(4))
                attrs[.font] = NSFont.systemFont(ofSize: 18, weight: .semibold)
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                content = "• " + String(line.dropFirst(2))
            } else if line.hasPrefix("\t- ") || line.hasPrefix("\t* ") {
                content = "\t• " + String(line.dropFirst(3))
            } else if line.hasPrefix("\t\t- ") || line.hasPrefix("\t\t* ") {
                content = "\t\t• " + String(line.dropFirst(4))
            }

            let lineStr = NSMutableAttributedString(string: content, attributes: attrs)
            applyInlineFormatting(lineStr, baseFont: attrs[.font] as? NSFont ?? bodyFont)
            if index < lines.count - 1 {
                lineStr.append(NSAttributedString(string: "\n", attributes: attrs))
            }
            result.append(lineStr)
        }
        return result
    }

    func toPlainText(_ attributed: NSAttributedString) -> String {
        attributed.string
    }

    // swiftlint:disable:next function_body_length
    private func applyInlineFormatting(_ str: NSMutableAttributedString, baseFont: NSFont) {
        // MARK: Wiki links [[Note Title]]
        // Must run BEFORE bold/italic so link content isn't further reformatted
        // swiftlint:disable:next force_try
        let wikiPattern = try! NSRegularExpression(pattern: "\\[\\[(.+?)\\]\\]")
        let wikiRange = NSRange(location: 0, length: str.string.utf16.count)
        for match in wikiPattern.matches(in: str.string, range: wikiRange).reversed() {
            let fullNSRange = match.range
            let innerNSRange = match.range(at: 1)
            guard let innerSwiftRange = Range(innerNSRange, in: str.string) else { continue }
            let noteTitle = String(str.string[innerSwiftRange])
            // Skip empty or whitespace-only links
            if noteTitle.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            let encodedTitle = noteTitle.addingPercentEncoding(
                withAllowedCharacters: .urlPathAllowed
            ) ?? noteTitle
            // swiftlint:disable:next force_unwrapping
            let linkURL = URL(string: "synth://wiki/\(encodedTitle)")!
            let mediumFont = NSFont.systemFont(ofSize: baseFont.pointSize, weight: .medium)

            // Broken link detection: check if target exists in noteIndex
            // If noteIndex hasn't populated yet, assume note exists to avoid broken-link flash on load
            let noteExists: Bool
            if let index = noteIndex, index.isPopulated {
                noteExists = index.findExact(noteTitle) != nil
            } else {
                noteExists = true
            }
            var linkAttrs: [NSAttributedString.Key: Any] = [
                .font: mediumFont,
                .link: linkURL,
                .cursor: NSCursor.pointingHand
            ]

            if noteExists {
                linkAttrs[.foregroundColor] = NSColor.controlAccentColor
            } else {
                linkAttrs[.foregroundColor] = NSColor.systemOrange
                linkAttrs[.underlineStyle] = NSUnderlineStyle.patternDash.rawValue
                    | NSUnderlineStyle.single.rawValue
                linkAttrs[.underlineColor] = NSColor.systemOrange.withAlphaComponent(0.6)
                linkAttrs[.toolTip] = "Note not found -- click to create"
            }

            let replacement = NSAttributedString(string: noteTitle, attributes: linkAttrs)
            str.replaceCharacters(in: fullNSRange, with: replacement)
        }

        // MARK: @Today, @Yesterday, @Tomorrow
        // swiftlint:disable:next force_try
        let atPattern = try! NSRegularExpression(
            pattern: "@(Today|Yesterday|Tomorrow)",
            options: .caseInsensitive
        )
        let atRange = NSRange(location: 0, length: str.string.utf16.count)
        for match in atPattern.matches(in: str.string, range: atRange).reversed() {
            let fullNSRange = match.range
            let tokenNSRange = match.range(at: 1)
            guard let tokenSwiftRange = Range(tokenNSRange, in: str.string) else { continue }
            let token = String(str.string[tokenSwiftRange])
            // swiftlint:disable:next force_unwrapping
            let linkURL = URL(string: "synth://daily/\(token.lowercased())")!
            guard let fullSwiftRange = Range(fullNSRange, in: str.string) else { continue }
            let displayText = String(str.string[fullSwiftRange])
            let replacement = NSAttributedString(
                string: displayText,
                attributes: [
                    .font: baseFont,
                    .foregroundColor: NSColor.controlAccentColor,
                    .link: linkURL
                ]
            )
            str.replaceCharacters(in: fullNSRange, with: replacement)
        }

        // MARK: #Tags
        // Must run after wiki links and @dates, before bold/italic/code
        let tagPattern = TagIndex.tagPattern
        let tagRange = NSRange(location: 0, length: str.string.utf16.count)
        for match in tagPattern.matches(in: str.string, range: tagRange).reversed() {
            let fullNSRange = match.range
            let innerNSRange = match.range(at: 1)
            guard let innerSwiftRange = Range(innerNSRange, in: str.string) else { continue }
            let tagName = String(str.string[innerSwiftRange])
            guard tagName.count >= 2 else { continue }
            let tagLower = tagName.lowercased()
            // swiftlint:disable:next force_unwrapping
            let tagURL = URL(string: "synth://tag/\(tagLower)")!
            let mediumFont = NSFont.systemFont(ofSize: baseFont.pointSize, weight: .medium)
            let replacement = NSAttributedString(
                string: "#\(tagName)",
                attributes: [
                    .font: mediumFont,
                    .foregroundColor: NSColor.systemTeal,
                    .backgroundColor: NSColor.systemTeal.withAlphaComponent(0.10),
                    .link: tagURL,
                    .cursor: NSCursor.pointingHand
                ]
            )
            str.replaceCharacters(in: fullNSRange, with: replacement)
        }

        // MARK: Bold **text**
        let text = str.string
        // swiftlint:disable:next force_try
        let boldPattern = try! NSRegularExpression(pattern: "\\*\\*(.+?)\\*\\*")
        let fullNSRange = NSRange(location: 0, length: text.utf16.count)
        for match in boldPattern.matches(in: text, range: fullNSRange).reversed() {
            if let fullRange = Range(match.range, in: text),
               let innerRange = Range(match.range(at: 1), in: text) {
                let boldFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: boldFont, .foregroundColor: NSColor.textColor
                ]
                let replacement = NSAttributedString(string: String(text[innerRange]), attributes: attrs)
                str.replaceCharacters(in: NSRange(fullRange, in: text), with: replacement)
            }
        }

        // MARK: Italic *text*
        // swiftlint:disable:next force_try
        let italicPattern = try! NSRegularExpression(pattern: "(?<!\\*)\\*([^*]+)\\*(?!\\*)")
        let strRange = NSRange(location: 0, length: str.string.utf16.count)
        for match in italicPattern.matches(in: str.string, range: strRange).reversed() {
            if let fullRange = Range(match.range, in: str.string),
               let innerRange = Range(match.range(at: 1), in: str.string) {
                let italicFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: italicFont, .foregroundColor: NSColor.textColor
                ]
                let replacement = NSAttributedString(
                    string: String(str.string[innerRange]),
                    attributes: attrs
                )
                str.replaceCharacters(in: NSRange(fullRange, in: str.string), with: replacement)
            }
        }

        // MARK: Inline code `text`
        // swiftlint:disable:next force_try
        let codePattern = try! NSRegularExpression(pattern: "`([^`]+)`")
        let codeRange = NSRange(location: 0, length: str.string.utf16.count)
        for match in codePattern.matches(in: str.string, range: codeRange).reversed() {
            if let fullRange = Range(match.range, in: str.string),
               let innerRange = Range(match.range(at: 1), in: str.string) {
                let replacement = NSAttributedString(
                    string: String(str.string[innerRange]),
                    attributes: [
                        .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
                        .foregroundColor: NSColor.systemPink,
                        .backgroundColor: NSColor.quaternaryLabelColor
                    ]
                )
                str.replaceCharacters(in: NSRange(fullRange, in: str.string), with: replacement)
            }
        }
    }
}

struct RichTextFormat: DocumentFormat {
    func render(_ text: String) -> NSAttributedString {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16),
            .foregroundColor: NSColor.textColor
        ]
        return NSAttributedString(string: text, attributes: attrs)
    }

    func toPlainText(_ attributed: NSAttributedString) -> String {
        attributed.string
    }
}

// MARK: - Wiki Link State Machine

enum WikiLinkState {
    case idle
    case singleBracket
    case wikiLinkActive(start: Int)
    case atActive(start: Int)
    case hashtagActive(start: Int)
}

class FormattingTextView: NSTextView {
    var wikiLinkState: WikiLinkState = .idle

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else { return super.performKeyEquivalent(with: event) }
        switch event.charactersIgnoringModifiers {
        case "b": toggleBold(); return true
        case "i": toggleItalic(); return true
        case "u": toggleUnderline(); return true
        default: return super.performKeyEquivalent(with: event)
        }
    }

    override func insertNewline(_ sender: Any?) {
        // Dismiss wiki link popup on newline
        switch wikiLinkState {
        case .wikiLinkActive, .atActive, .hashtagActive:
            wikiLinkState = .idle
            NotificationCenter.default.post(name: .wikiLinkDismiss, object: self)
        default:
            break
        }

        guard let storage = textStorage else { super.insertNewline(sender); return }
        let lineRange = (storage.string as NSString).lineRange(for: selectedRange())
        let line = (storage.string as NSString).substring(with: lineRange).trimmingCharacters(in: .newlines)

        // Count leading tabs
        var indent = ""
        for char in line { if char == "\t" { indent += "\t" } else { break } }

        // If current line is just a bullet (empty item), remove it instead
        if line == "\(indent)•" {
            storage.replaceCharacters(in: lineRange, with: "")
            return
        }

        // If line starts with bullet, continue the list
        if line.hasPrefix("\(indent)•") {
            super.insertNewline(sender)
            insertText("\(indent)• ", replacementRange: selectedRange())
            return
        }

        super.insertNewline(sender)
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        super.insertText(string, replacementRange: replacementRange)
        guard let str = string as? String else { return }

        handleAutocompleteState(for: str)
        handleBulletConversion(for: str)
    }

    // MARK: - Autocomplete State Machine

    private func handleAutocompleteState(for str: String) {
        switch wikiLinkState {
        case .idle:
            handleIdleState(for: str)
        case .singleBracket:
            handleSingleBracketState(for: str)
        case .wikiLinkActive, .atActive:
            handleLinkActiveState(for: str)
        case .hashtagActive(let start):
            handleHashtagActiveState(for: str, start: start)
        }
    }

    private func handleIdleState(for str: String) {
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
        } else if str == "#" {
            let cursor = selectedRange().location
            let isAtStart = cursor <= 1
            var precededBySpace = isAtStart
            if !isAtStart, let storage = textStorage {
                let charBefore = (storage.string as NSString).substring(
                    with: NSRange(location: cursor - 2, length: 1)
                )
                precededBySpace = charBefore.rangeOfCharacter(
                    from: .whitespacesAndNewlines
                ) != nil
            }
            if precededBySpace {
                wikiLinkState = .hashtagActive(start: cursor)
            }
        }
    }

    private func handleSingleBracketState(for str: String) {
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
    }

    private func handleLinkActiveState(for str: String) {
        if str == "]" || str == "\n" || str == "\t" {
            wikiLinkState = .idle
            NotificationCenter.default.post(name: .wikiLinkDismiss, object: self)
        } else if str == " " {
            if case .atActive = wikiLinkState {
                let query = extractCurrentQuery()
                let lowered = query.trimmingCharacters(in: .whitespaces).lowercased()
                let dateTokens = ["today", "yesterday", "tomorrow"]
                let hasPartialMatch = dateTokens.contains { $0.hasPrefix(lowered) }
                if !hasPartialMatch {
                    wikiLinkState = .idle
                    NotificationCenter.default.post(name: .wikiLinkDismiss, object: self)
                } else {
                    postQueryUpdate()
                }
            } else {
                postQueryUpdate()
            }
        } else {
            postQueryUpdate()
        }
    }

    private func handleHashtagActiveState(for str: String, start: Int) {
        if str == " " || str == "\n" || str == "\t" {
            wikiLinkState = .idle
            NotificationCenter.default.post(name: .wikiLinkDismiss, object: self)
        } else {
            let cursor = selectedRange().location
            let queryLength = cursor - start
            if queryLength == 1 {
                let firstChar = str.first ?? Character(" ")
                if firstChar.isLetter {
                    NotificationCenter.default.post(
                        name: .wikiLinkTrigger,
                        object: self,
                        userInfo: ["mode": "hashtag", "query": str]
                    )
                } else {
                    wikiLinkState = .idle
                }
            } else {
                postQueryUpdate()
            }
        }
    }

    private func postQueryUpdate() {
        let query = extractCurrentQuery()
        NotificationCenter.default.post(
            name: .wikiLinkQueryUpdate,
            object: self,
            userInfo: ["query": query]
        )
    }

    // MARK: - Bullet Conversion

    private func handleBulletConversion(for str: String) {
        guard str == " ", let storage = textStorage else { return }
        let lineRange = (storage.string as NSString).lineRange(for: selectedRange())
        let line = (storage.string as NSString).substring(with: lineRange)

        let trimmed = line.trimmingCharacters(in: .newlines)
        var indent = ""
        for char in trimmed { if char == "\t" { indent += "\t" } else { break } }
        let rest = String(trimmed.dropFirst(indent.count))

        if rest == "- " || rest == "* " {
            let bulletRange = NSRange(location: lineRange.location + indent.count, length: 2)
            storage.replaceCharacters(in: bulletRange, with: "• ")
        }
    }

    // MARK: - Delete Backward

    override func deleteBackward(_ sender: Any?) {
        super.deleteBackward(sender)
        switch wikiLinkState {
        case .wikiLinkActive(let start), .atActive(let start), .hashtagActive(let start):
            if selectedRange().location <= start {
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
        case .singleBracket:
            wikiLinkState = .idle
        default:
            break
        }
    }

    // MARK: - Key Down (Arrow/Return/Escape interception)

    override func keyDown(with event: NSEvent) {
        let isPopupActive: Bool
        switch wikiLinkState {
        case .wikiLinkActive, .atActive, .hashtagActive:
            isPopupActive = true
        default:
            isPopupActive = false
        }

        guard isPopupActive else {
            super.keyDown(with: event)
            return
        }

        switch event.keyCode {
        case 126: // Up arrow
            NotificationCenter.default.post(
                name: .wikiLinkNavigate,
                object: self,
                userInfo: ["direction": "up"]
            )
        case 125: // Down arrow
            NotificationCenter.default.post(
                name: .wikiLinkNavigate,
                object: self,
                userInfo: ["direction": "down"]
            )
        case 36: // Return -- select current result
            NotificationCenter.default.post(name: .wikiLinkSelect, object: self)
        case 53: // Escape -- dismiss
            wikiLinkState = .idle
            NotificationCenter.default.post(name: .wikiLinkDismiss, object: self)
        default:
            super.keyDown(with: event)
        }
    }

    // MARK: - Extract Current Query

    func extractCurrentQuery() -> String {
        guard let storage = textStorage else { return "" }
        let cursor = selectedRange().location
        switch wikiLinkState {
        case .wikiLinkActive(let start), .atActive(let start), .hashtagActive(let start):
            guard cursor > start else { return "" }
            let range = NSRange(location: start, length: cursor - start)
            return (storage.string as NSString).substring(with: range)
        default:
            return ""
        }
    }

    override func insertTab(_ sender: Any?) {
        guard let storage = textStorage else { super.insertTab(sender); return }
        let lineRange = (storage.string as NSString).lineRange(for: selectedRange())
        let line = (storage.string as NSString).substring(with: lineRange)

        if line.contains("•") {
            storage.insert(NSAttributedString(string: "\t"), at: lineRange.location)
            return
        }
        super.insertTab(sender)
    }

    override func insertBacktab(_ sender: Any?) {
        guard let storage = textStorage else { super.insertBacktab(sender); return }
        let lineRange = (storage.string as NSString).lineRange(for: selectedRange())
        let line = (storage.string as NSString).substring(with: lineRange)

        if line.hasPrefix("\t") && line.contains("•") {
            storage.deleteCharacters(in: NSRange(location: lineRange.location, length: 1))
            return
        }
        super.insertBacktab(sender)
    }

    func toggleBold() { toggleTrait(.boldFontMask) }
    func toggleItalic() { toggleTrait(.italicFontMask) }

    private func toggleTrait(_ trait: NSFontTraitMask) {
        let range = selectedRange()
        guard range.length > 0, let storage = textStorage else { return }

        var hasTrait = false
        storage.enumerateAttribute(.font, in: range) { value, _, _ in
            if let font = value as? NSFont {
                let traits = font.fontDescriptor.symbolicTraits
                let check = trait == .boldFontMask ? traits.contains(.bold) : traits.contains(.italic)
                hasTrait = hasTrait || check
            }
        }

        storage.enumerateAttribute(.font, in: range) { value, attrRange, _ in
            if let font = value as? NSFont {
                let mgr = NSFontManager.shared
                let newFont = hasTrait
                    ? mgr.convert(font, toNotHaveTrait: trait)
                    : mgr.convert(font, toHaveTrait: trait)
                storage.addAttribute(.font, value: newFont, range: attrRange)
            }
        }
    }

    func toggleUnderline() {
        let range = selectedRange()
        guard range.length > 0, let storage = textStorage else { return }

        var hasUnderline = false
        storage.enumerateAttribute(.underlineStyle, in: range) { value, _, _ in
            if let style = value as? Int, style != 0 { hasUnderline = true }
        }
        storage.addAttribute(.underlineStyle, value: hasUnderline ? 0 : NSUnderlineStyle.single.rawValue, range: range)
    }
}

struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var scrollOffset: CGFloat
    @Binding var linePositions: [CGFloat]
    @Binding var selectedText: String
    @Binding var selectedLineRange: String
    weak var store: DocumentStore?

    var format: DocumentFormat {
        MarkdownFormat(noteIndex: store?.noteIndex)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = FormattingTextView()
        textView.isEditable = true
        textView.isRichText = true
        textView.isAutomaticLinkDetectionEnabled = false
        textView.textContainerInset = NSSize(width: 20, height: 20)
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.delegate = context.coordinator
        textView.typingAttributes = [
            .font: NSFont.systemFont(ofSize: 16),
            .foregroundColor: NSColor.textColor
        ]
        textView.insertionPointColor = NSColor.textColor
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.documentView = textView
        scrollView.contentView.postsBoundsChangedNotifications = true

        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        context.coordinator.parent = self
        context.coordinator.store = store

        context.coordinator.boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { _ in
            context.coordinator.updateScrollOffset()
        }

        // MARK: Wiki link notification observers
        context.coordinator.setupWikiLinkObservers()

        // Initialize line positions for empty documents and set focus
        DispatchQueue.main.async {
            context.coordinator.updateLinePositions()
            textView.window?.makeFirstResponder(textView)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        context.coordinator.parent = self
        context.coordinator.store = store

        if !context.coordinator.isEditing && textView.string != text {
            textView.textStorage?.setAttributedString(format.render(text))
            DispatchQueue.main.async {
                context.coordinator.updateLinePositions()
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditor
        var textView: FormattingTextView?
        var scrollView: NSScrollView?
        var isEditing = false
        var boundsObserver: NSObjectProtocol?
        weak var store: DocumentStore?
        var wikiLinkPopover = WikiLinkPopover()
        var wikiLinkObservers: [NSObjectProtocol] = []

        init(_ parent: MarkdownEditor) { self.parent = parent }

        deinit {
            if let observer = boundsObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            for observer in wikiLinkObservers {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        // MARK: - Wiki Link Observer Setup

        func setupWikiLinkObservers() {
            let center = NotificationCenter.default

            let triggerObs = center.addObserver(
                forName: .wikiLinkTrigger, object: nil, queue: .main
            ) { [weak self] notification in
                self?.handleWikiLinkTrigger(notification)
            }
            wikiLinkObservers.append(triggerObs)

            let dismissObs = center.addObserver(
                forName: .wikiLinkDismiss, object: nil, queue: .main
            ) { [weak self] _ in
                self?.wikiLinkPopover.dismiss()
            }
            wikiLinkObservers.append(dismissObs)

            let queryObs = center.addObserver(
                forName: .wikiLinkQueryUpdate, object: nil, queue: .main
            ) { [weak self] notification in
                self?.handleWikiLinkQueryUpdate(notification)
            }
            wikiLinkObservers.append(queryObs)

            let selectObs = center.addObserver(
                forName: .wikiLinkSelect, object: nil, queue: .main
            ) { [weak self] _ in
                self?.handleWikiLinkSelect()
            }
            wikiLinkObservers.append(selectObs)

            let navObs = center.addObserver(
                forName: .wikiLinkNavigate, object: nil, queue: .main
            ) { [weak self] notification in
                self?.handleWikiLinkNavigate(notification)
            }
            wikiLinkObservers.append(navObs)

            // Set up the selection callback on the popover
            wikiLinkPopover.onSelect = { [weak self] title in
                self?.completeWikiLink(title: title)
            }
        }

        // MARK: - Wiki Link Trigger

        private func handleWikiLinkTrigger(_ notification: Notification) {
            guard let textView = textView else { return }
            let mode = notification.userInfo?["mode"] as? String ?? "wikilink"
            let initialQuery = notification.userInfo?["query"] as? String ?? ""
            let cursorPos = textView.selectedRange().location

            // Position the popover at the trigger location
            let triggerStart: Int
            if mode == "wikilink" {
                triggerStart = max(cursorPos - 2, 0)
            } else if mode == "hashtag" {
                // Popup anchored at the # character
                triggerStart = max(cursorPos - 2, 0) // # + first letter
            } else {
                triggerStart = max(cursorPos - 1, 0)
            }

            wikiLinkPopover.show(at: triggerStart, in: textView, mode: mode)

            // Initial results
            let results: [NoteSearchResult]
            if mode == "at" {
                results = dateAutocompleteResults(query: "")
            } else if mode == "hashtag" {
                results = tagAutocompleteResults(query: initialQuery)
            } else {
                results = store?.noteIndex.search("") ?? []
            }
            wikiLinkPopover.updateResults(query: initialQuery, results: results)
        }

        // MARK: - Wiki Link Query Update

        private func handleWikiLinkQueryUpdate(_ notification: Notification) {
            let query = notification.userInfo?["query"] as? String ?? ""
            guard let textView = textView else { return }

            let results: [NoteSearchResult]
            switch textView.wikiLinkState {
            case .atActive:
                results = dateAutocompleteResults(query: query)
            case .hashtagActive:
                results = tagAutocompleteResults(query: query)
            default:
                results = store?.noteIndex.search(query) ?? []
            }
            wikiLinkPopover.updateResults(query: query, results: results)
        }

        // MARK: - Wiki Link Selection

        private func handleWikiLinkSelect() {
            guard let title = wikiLinkPopover.selectedTitle() else { return }
            completeWikiLink(title: title)
        }

        // MARK: - Wiki Link Navigation

        private func handleWikiLinkNavigate(_ notification: Notification) {
            let direction = notification.userInfo?["direction"] as? String ?? ""
            if direction == "up" {
                wikiLinkPopover.moveSelectionUp()
            } else {
                wikiLinkPopover.moveSelectionDown()
            }
        }

        // MARK: - Complete Wiki Link Insertion

        func completeWikiLink(title: String) {
            guard let textView = textView,
                  let storage = textView.textStorage else { return }
            let cursor = textView.selectedRange().location

            switch textView.wikiLinkState {
            case .wikiLinkActive(let start):
                // start points to after "[[", so replace from start-2 to cursor
                let replaceStart = max(start - 2, 0)
                let range = NSRange(location: replaceStart, length: cursor - replaceStart)
                let replacement = "[[\(title)]]"
                storage.replaceCharacters(in: range, with: replacement)
                textView.setSelectedRange(
                    NSRange(location: replaceStart + replacement.count, length: 0)
                )

            case .atActive(let start):
                // start points to after "@", so replace from start-1 to cursor
                let replaceStart = max(start - 1, 0)
                let range = NSRange(location: replaceStart, length: cursor - replaceStart)
                let replacement = "@\(title)"
                storage.replaceCharacters(in: range, with: replacement)
                textView.setSelectedRange(
                    NSRange(location: replaceStart + replacement.count, length: 0)
                )

            case .hashtagActive(let start):
                // start points to after "#", so replace from start-1 to cursor
                let replaceStart = max(start - 1, 0)
                let range = NSRange(location: replaceStart, length: cursor - replaceStart)
                // title already includes "#" prefix from tagAutocompleteResults
                let tagText = title.hasPrefix("#") ? title : "#\(title)"
                let replacement = "\(tagText) "
                storage.replaceCharacters(in: range, with: replacement)
                textView.setSelectedRange(
                    NSRange(location: replaceStart + replacement.count, length: 0)
                )

            default:
                break
            }

            textView.wikiLinkState = .idle
            wikiLinkPopover.dismiss()

            // Trigger text update
            parent.text = textView.string
        }

        // MARK: - Date Autocomplete Results

        private func dateAutocompleteResults(query: String) -> [NoteSearchResult] {
            let tokens = ["Today", "Yesterday", "Tomorrow"]
            let filtered: [String]
            if query.isEmpty {
                filtered = tokens
            } else {
                filtered = tokens.filter {
                    $0.lowercased().hasPrefix(query.lowercased())
                }
            }
            return filtered.map { token in
                let dateStr = resolveDateLabel(token)
                return NoteSearchResult(
                    // swiftlint:disable:next force_unwrapping
                    id: URL(string: "synth://daily/\(token.lowercased())")!,
                    title: token,
                    relativePath: dateStr,
                    // swiftlint:disable:next force_unwrapping
                    url: URL(string: "synth://daily/\(token.lowercased())")!
                )
            }
        }

        // MARK: - Tag Autocomplete Results

        private func tagAutocompleteResults(query: String) -> [NoteSearchResult] {
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

        private func resolveDateLabel(_ token: String) -> String {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            let date: Date?
            switch token.lowercased() {
            case "today":
                date = Date()
            case "yesterday":
                date = Calendar.current.date(byAdding: .day, value: -1, to: Date())
            case "tomorrow":
                date = Calendar.current.date(byAdding: .day, value: 1, to: Date())
            default:
                date = nil
            }
            guard let resolved = date else { return "" }
            return formatter.string(from: resolved)
        }

        // MARK: - Link Click Handling

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
                let token = url.pathComponents.dropFirst().joined(separator: "/")
                handleDailyNoteClick(token: token)
                return true
            }

            if url.host == "tag" {
                let tagName = url.pathComponents.dropFirst().joined(separator: "/")
                handleTagClick(tagName: tagName)
                return true
            }

            return false
        }

        private func handleWikiLinkClick(noteTitle: String) {
            guard let store = store else { return }

            // Search for matching file in the workspace
            if let exact = store.noteIndex.findExact(noteTitle) {
                store.open(exact.url)
            } else {
                // Create new note
                createAndOpenNote(title: noteTitle, store: store)
            }
        }

        private func handleDailyNoteClick(token: String) {
            guard let store = store, let workspace = store.workspace else { return }
            guard let url = DailyNoteResolver.resolve(token, workspace: workspace) else { return }
            DailyNoteResolver.ensureExists(at: url)
            store.loadFileTree()
            store.open(url)
        }

        private func createAndOpenNote(title: String, store: DocumentStore) {
            guard let workspace = store.workspace else { return }
            // Sanitize title: strip path traversal and invalid filename characters
            let sanitized = title
                .replacingOccurrences(of: "[/:\\x00-\\x1F\\x7F]", with: "-", options: .regularExpression)
                .replacingOccurrences(of: "..", with: "-")
                .trimmingCharacters(in: .whitespaces)
            guard !sanitized.isEmpty else { return }
            let url = workspace.appendingPathComponent("\(sanitized).md")
            // Validate the resolved path stays within the workspace
            guard url.standardizedFileURL.path.hasPrefix(workspace.standardizedFileURL.path) else { return }
            let content = "# \(sanitized)\n\n"
            try? content.write(to: url, atomically: true, encoding: .utf8)
            store.loadFileTree()
            store.open(url)
        }

        private func handleTagClick(tagName: String) {
            NotificationCenter.default.post(
                name: .showTagBrowser,
                object: nil,
                userInfo: ["initialTag": tagName]
            )
        }

        // MARK: - Scroll Offset

        func updateScrollOffset() {
            guard let scrollView = scrollView else { return }
            DispatchQueue.main.async {
                self.parent.scrollOffset = scrollView.contentView.bounds.origin.y
            }
        }

        // MARK: - Line Positions

        func updateLinePositions() {
            guard let textView = textView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }

            // Force layout to complete
            layoutManager.ensureLayout(for: textContainer)

            let textInset = textView.textContainerInset.height
            let font = textView.typingAttributes[.font] as? NSFont ?? NSFont.systemFont(ofSize: 16)
            var positions: [CGFloat] = []
            let string = textView.string

            // Empty document
            if string.isEmpty {
                positions.append(textInset + font.pointSize / 2)
                parent.linePositions = positions
                return
            }

            // Get default line height from first line fragment
            var defaultLineHeight: CGFloat = font.pointSize * 1.4
            if layoutManager.numberOfGlyphs > 0 {
                let rect = layoutManager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
                defaultLineHeight = rect.height
            }

            // Count actual lines by newlines
            let lines = string.components(separatedBy: "\n")
            for lineIndex in 0..<lines.count {
                let yPos = textInset + CGFloat(lineIndex) * defaultLineHeight
                    + defaultLineHeight / 2
                positions.append(yPos)
            }

            DispatchQueue.main.async {
                self.parent.linePositions = positions
            }
        }

        // MARK: - Text Delegate Methods

        func textDidBeginEditing(_ notification: Notification) { isEditing = true }
        func textDidEndEditing(_ notification: Notification) { isEditing = false }

        func textDidChange(_ notification: Notification) {
            guard let textView = textView else { return }
            parent.text = textView.string
            updateLinePositions()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = textView else { return }
            let range = textView.selectedRange()
            if range.length > 0 {
                let text = (textView.string as NSString).substring(with: range)
                let beforeSelection = (textView.string as NSString)
                    .substring(to: range.location)
                let startLine = beforeSelection.components(separatedBy: "\n").count
                let selectedLines = text.components(separatedBy: "\n").count
                let endLine = startLine + selectedLines - 1
                DispatchQueue.main.async {
                    self.parent.selectedText = text
                    self.parent.selectedLineRange = "lines \(startLine)-\(endLine)"
                }
            } else {
                DispatchQueue.main.async {
                    self.parent.selectedText = ""
                    self.parent.selectedLineRange = ""
                }
            }
        }
    }
}
