import SwiftUI
import AppKit

protocol DocumentFormat {
    func render(_ text: String) -> NSAttributedString
    func toPlainText(_ attributed: NSAttributedString) -> String
}

struct MarkdownFormat: DocumentFormat {
    func render(_ text: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let bodyFont = NSFont.systemFont(ofSize: 16)
        let defaultAttrs: [NSAttributedString.Key: Any] = [.font: bodyFont, .foregroundColor: NSColor.textColor]

        for line in text.components(separatedBy: "\n") {
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
            lineStr.append(NSAttributedString(string: "\n", attributes: attrs))
            result.append(lineStr)
        }
        return result
    }

    func toPlainText(_ attributed: NSAttributedString) -> String {
        attributed.string
    }

    private func applyInlineFormatting(_ str: NSMutableAttributedString, baseFont: NSFont) {
        let text = str.string

        // Bold **text**
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

        // Italic *text*
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

        // Inline code `text`
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

class FormattingTextView: NSTextView {
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

        guard let str = string as? String, str == " ", let storage = textStorage else { return }
        let lineRange = (storage.string as NSString).lineRange(for: selectedRange())
        let line = (storage.string as NSString).substring(with: lineRange)

        // Check if line is "- " or "* " or indented versions
        let trimmed = line.trimmingCharacters(in: .newlines)
        var indent = ""
        for char in trimmed { if char == "\t" { indent += "\t" } else { break } }
        let rest = String(trimmed.dropFirst(indent.count))

        if rest == "- " || rest == "* " {
            let bulletRange = NSRange(location: lineRange.location + indent.count, length: 2)
            storage.replaceCharacters(in: bulletRange, with: "• ")
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
    var format: DocumentFormat = MarkdownFormat()

    func makeNSView(context: Context) -> NSScrollView {
        let textView = FormattingTextView()
        textView.isEditable = true
        textView.isRichText = true
        textView.textContainerInset = NSSize(width: 20, height: 20)
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.delegate = context.coordinator
        textView.typingAttributes = [.font: NSFont.systemFont(ofSize: 16), .foregroundColor: NSColor.textColor]
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

        NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { _ in
            context.coordinator.updateScrollOffset()
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        context.coordinator.parent = self

        if !context.coordinator.isEditing && textView.string != text {
            textView.textStorage?.setAttributedString(format.render(text))
            DispatchQueue.main.async {
                context.coordinator.updateLinePositions()
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditor
        var textView: FormattingTextView?
        var scrollView: NSScrollView?
        var isEditing = false

        init(_ parent: MarkdownEditor) { self.parent = parent }

        func updateScrollOffset() {
            guard let scrollView = scrollView else { return }
            DispatchQueue.main.async {
                self.parent.scrollOffset = scrollView.contentView.bounds.origin.y
            }
        }

        func updateLinePositions() {
            guard let textView = textView, let layoutManager = textView.layoutManager else { return }
            let textInset = textView.textContainerInset.height
            var positions: [CGFloat] = []
            let string = textView.string

            // Count lines by splitting on newlines
            let lines = string.components(separatedBy: "\n")
            var charIndex = 0

            for (lineIndex, line) in lines.enumerated() {
                if layoutManager.numberOfGlyphs > 0 {
                    let safeIndex = min(charIndex, max(0, (string as NSString).length - 1))
                    let glyphIndex = layoutManager.glyphIndexForCharacter(at: safeIndex)
                    if layoutManager.isValidGlyphIndex(glyphIndex) {
                        let rect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
                        positions.append(rect.origin.y + textInset + rect.height / 2 + 4)
                    }
                } else if lineIndex == 0 {
                    positions.append(textInset + 12)
                }
                charIndex += line.count + 1 // +1 for newline
            }

            if positions.isEmpty { positions = [textInset + 12] }

            DispatchQueue.main.async {
                self.parent.linePositions = positions
            }
        }

        func textDidBeginEditing(_ notification: Notification) { isEditing = true }
        func textDidEndEditing(_ notification: Notification) { isEditing = false }

        func textDidChange(_ notification: Notification) {
            guard let textView = textView else { return }
            parent.text = textView.string
            updateLinePositions()
        }
    }
}
