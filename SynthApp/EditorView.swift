import SwiftUI
import AppKit

struct EditorView: NSViewRepresentable {
    @EnvironmentObject var store: DocumentStore

    func makeNSView(context: Context) -> NSView {
        let container = NSView()

        let scrollView = LineNumberScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.backgroundColor = NSColor(white: 0.95, alpha: 1.0)
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let textView = RichTextView()
        textView.isEditable = true
        textView.isRichText = true
        textView.font = Theme.editorFont
        textView.textColor = .black
        textView.backgroundColor = NSColor(white: 0.95, alpha: 1.0)
        textView.insertionPointColor = .black
        textView.textContainerInset = NSSize(width: 20, height: 40)
        textView.textContainer?.lineFragmentPadding = 5
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = context.coordinator
        textView.allowsUndo = true

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 6
        textView.defaultParagraphStyle = paragraphStyle
        textView.typingAttributes = [.font: Theme.editorFont, .foregroundColor: NSColor.black, .paragraphStyle: paragraphStyle]

        scrollView.documentView = textView
        scrollView.setupLineNumbers(for: textView)
        context.coordinator.textView = textView

        // Formatting toolbar
        let toolbar = NSStackView()
        toolbar.orientation = .horizontal
        toolbar.spacing = 4
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        let buttons: [(String, Selector)] = [
            ("bold", #selector(RichTextView.toggleBold)),
            ("italic", #selector(RichTextView.toggleItalic)),
            ("underline", #selector(RichTextView.toggleUnderline)),
            ("list.bullet", #selector(RichTextView.insertBullet)),
            ("textformat.size.larger", #selector(RichTextView.makeHeader))
        ]

        for (icon, action) in buttons {
            let btn = NSButton(image: NSImage(systemSymbolName: icon, accessibilityDescription: nil)!, target: textView, action: action)
            btn.bezelStyle = .texturedRounded
            btn.isBordered = false
            toolbar.addArrangedSubview(btn)
        }
        toolbar.addArrangedSubview(NSView()) // spacer

        container.addSubview(toolbar)
        container.addSubview(scrollView)

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            toolbar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 60),
            toolbar.heightAnchor.constraint(equalToConstant: 28),
            scrollView.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        guard let textView = context.coordinator.textView,
              store.currentIndex >= 0 && store.currentIndex < store.openFiles.count else { return }

        let doc = store.openFiles[store.currentIndex]
        if context.coordinator.currentURL != doc.url {
            textView.textStorage?.setAttributedString(doc.content)
            context.coordinator.currentURL = doc.url
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(store: store) }

    class Coordinator: NSObject, NSTextViewDelegate {
        var textView: NSTextView?
        var currentURL: URL?
        var store: DocumentStore

        init(store: DocumentStore) { self.store = store }

        func textDidChange(_ notification: Notification) {
            guard let textView = textView else { return }
            store.updateContent(textView.attributedString())
        }
    }
}

class RichTextView: NSTextView {
    var selectionPopover: NSPopover?

    override func setSelectedRange(_ charRange: NSRange, affinity: NSSelectionAffinity, stillSelecting stillSelectingFlag: Bool) {
        super.setSelectedRange(charRange, affinity: affinity, stillSelecting: stillSelectingFlag)
        if !stillSelectingFlag {
            DispatchQueue.main.async { self.updateSelectionPopover() }
        }
    }

    func updateSelectionPopover() {
        selectionPopover?.close()
        selectionPopover = nil

        let range = selectedRange()
        guard range.length > 0, let layoutManager = layoutManager, let textContainer = textContainer else { return }

        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        rect.origin.x += textContainerInset.width
        rect.origin.y += textContainerInset.height

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: SelectionToolbar(textView: self))
        popover.show(relativeTo: rect, of: self, preferredEdge: .maxY)
        selectionPopover = popover
    }

    func getSelectedText() -> String {
        let range = selectedRange()
        guard range.length > 0, let storage = textStorage else { return "" }
        return (storage.string as NSString).substring(with: range)
    }

    @objc func askKiro() {
        let text = getSelectedText()
        guard !text.isEmpty else { return }
        selectionPopover?.close()
        NotificationCenter.default.post(name: .showChat, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            ChatController.shared.send?("Help me with this:", text)
        }
    }

    @objc func improveSelection() {
        let text = getSelectedText()
        guard !text.isEmpty else { return }
        selectionPopover?.close()
        NotificationCenter.default.post(name: .showChat, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            ChatController.shared.send?("Improve this text, make it clearer and more concise:", text)
        }
    }

    @objc func explainSelection() {
        let text = getSelectedText()
        guard !text.isEmpty else { return }
        selectionPopover?.close()
        NotificationCenter.default.post(name: .showChat, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            ChatController.shared.send?("Explain this:", text)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()

        if selectedRange().length > 0 {
            menu.insertItem(NSMenuItem.separator(), at: 0)

            let explainItem = NSMenuItem(title: "Explain This", action: #selector(explainSelection), keyEquivalent: "")
            explainItem.target = self
            menu.insertItem(explainItem, at: 0)

            let improveItem = NSMenuItem(title: "Improve This", action: #selector(improveSelection), keyEquivalent: "")
            improveItem.target = self
            menu.insertItem(improveItem, at: 0)

            let askItem = NSMenuItem(title: "Ask Kiro...", action: #selector(askKiro), keyEquivalent: "")
            askItem.target = self
            menu.insertItem(askItem, at: 0)
        }

        return menu
    }

    @objc func toggleBold() {
        let range = selectedRange()
        guard range.length > 0, let storage = textStorage else { return }

        var hasBold = false
        storage.enumerateAttribute(.font, in: range) { value, _, _ in
            if let font = value as? NSFont, font.fontDescriptor.symbolicTraits.contains(.bold) { hasBold = true }
        }

        storage.enumerateAttribute(.font, in: range) { value, attrRange, _ in
            if let font = value as? NSFont {
                let newFont = hasBold ? NSFontManager.shared.convert(font, toNotHaveTrait: .boldFontMask) : NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
                storage.addAttribute(.font, value: newFont, range: attrRange)
            }
        }
    }

    @objc func toggleItalic() {
        let range = selectedRange()
        guard range.length > 0, let storage = textStorage else { return }

        var hasItalic = false
        storage.enumerateAttribute(.font, in: range) { value, _, _ in
            if let font = value as? NSFont, font.fontDescriptor.symbolicTraits.contains(.italic) { hasItalic = true }
        }

        storage.enumerateAttribute(.font, in: range) { value, attrRange, _ in
            if let font = value as? NSFont {
                let newFont = hasItalic ? NSFontManager.shared.convert(font, toNotHaveTrait: .italicFontMask) : NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
                storage.addAttribute(.font, value: newFont, range: attrRange)
            }
        }
    }

    @objc func toggleUnderline() {
        let range = selectedRange()
        guard range.length > 0, let storage = textStorage else { return }

        var hasUnderline = false
        storage.enumerateAttribute(.underlineStyle, in: range) { value, _, _ in
            if let style = value as? Int, style != 0 { hasUnderline = true }
        }
        storage.addAttribute(.underlineStyle, value: hasUnderline ? 0 : NSUnderlineStyle.single.rawValue, range: range)
    }

    @objc func insertBullet() {
        insertText("• ", replacementRange: NSRange(location: selectedRange().location, length: 0))
    }

    @objc func makeHeader() {
        guard let storage = textStorage else { return }
        let lineRange = (storage.string as NSString).lineRange(for: selectedRange())
        storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 24, weight: .bold), range: lineRange)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else { return super.performKeyEquivalent(with: event) }
        switch event.charactersIgnoringModifiers {
        case "b": toggleBold(); return true
        case "i": toggleItalic(); return true
        case "u": toggleUnderline(); return true
        default: return super.performKeyEquivalent(with: event)
        }
    }
}

struct SelectionToolbar: View {
    let textView: RichTextView

    var body: some View {
        HStack(spacing: 8) {
            Button { textView.askKiro() } label: {
                Label("Ask Kiro", systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)

            Button { textView.improveSelection() } label: {
                Image(systemName: "wand.and.stars")
            }
            .help("Improve")

            Button { textView.explainSelection() } label: {
                Image(systemName: "questionmark.circle")
            }
            .help("Explain")
        }
        .padding(8)
    }
}

// MARK: - Line Numbers

class LineNumberScrollView: NSScrollView {
    private var lineNumberView: LineNumberRulerView?

    func setupLineNumbers(for textView: NSTextView) {
        let rulerView = LineNumberRulerView(textView: textView)
        self.verticalRulerView = rulerView
        self.hasVerticalRuler = true
        self.rulersVisible = true
        self.lineNumberView = rulerView

        NotificationCenter.default.addObserver(
            self, selector: #selector(textDidChange),
            name: NSText.didChangeNotification, object: textView
        )
    }

    @objc private func textDidChange(_ notification: Notification) {
        lineNumberView?.needsDisplay = true
    }
}

class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        self.clientView = textView
        self.ruleThickness = 40
    }

    required init(coder: NSCoder) { fatalError() }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = textView,
              let layoutManager = textView.layoutManager,
              textView.textContainer != nil else { return }

        let visibleRect = scrollView?.contentView.bounds ?? rect
        let textInset = textView.textContainerInset

        NSColor.textBackgroundColor.setFill()
        rect.fill()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]

        let text = textView.string as NSString
        var lineNumber = 1
        var glyphIndex = 0
        let numberOfGlyphs = layoutManager.numberOfGlyphs

        while glyphIndex < numberOfGlyphs {
            var lineRange = NSRange()
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &lineRange)
            let yOffset = lineRect.origin.y + textInset.height - visibleRect.origin.y

            if yOffset + lineRect.height >= 0 && yOffset <= rect.height {
                let numStr = "\(lineNumber)"
                let size = numStr.size(withAttributes: attrs)
                let drawY = yOffset + (lineRect.height - size.height) / 2
                let drawRect = NSRect(x: ruleThickness - size.width - 8, y: drawY, width: size.width, height: size.height)
                numStr.draw(in: drawRect, withAttributes: attrs)
            }

            glyphIndex = NSMaxRange(lineRange)
            lineNumber += 1

            // Check if this is a soft wrap vs actual newline
            let charIndex = layoutManager.characterIndexForGlyph(at: max(0, glyphIndex - 1))
            if charIndex < text.length && text.character(at: charIndex) != Character("\n").asciiValue! {
                lineNumber -= 1
            }
        }
    }
}
