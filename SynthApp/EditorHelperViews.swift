import AppKit

protocol DocumentFormat {
    func render(_ text: String) -> NSAttributedString
    func toPlainText(_ attributed: NSAttributedString) -> String
}

// MARK: - Wiki Link State Machine

enum WikiLinkState {
    case idle
    case singleBracket
    case wikiLinkActive(start: Int)
    case atActive(start: Int)
    case hashtagActive(start: Int)
    case slashActive(start: Int)
}

// MARK: - Resize Grip View

class ResizeGripView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 3
        layer?.backgroundColor = NSColor.windowBackgroundColor
            .withAlphaComponent(0.8).cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext
        else { return }
        let inset: CGFloat = 4
        let lineWidth: CGFloat = 1.5
        context.setStrokeColor(
            NSColor.secondaryLabelColor.cgColor
        )
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        // Line 1: shorter
        context.move(to: CGPoint(
            x: bounds.maxX - inset,
            y: bounds.maxY - inset - 4
        ))
        context.addLine(to: CGPoint(
            x: bounds.maxX - inset - 4,
            y: bounds.maxY - inset
        ))
        // Line 2: longer
        context.move(to: CGPoint(
            x: bounds.maxX - inset,
            y: bounds.maxY - inset - 8
        ))
        context.addLine(to: CGPoint(
            x: bounds.maxX - inset - 8,
            y: bounds.maxY - inset
        ))
        context.strokePath()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// MARK: - Image Attachment Overlay

class ImageAttachmentOverlay: NSView {
    var onCopy: (() -> Void)?
    var onDelete: (() -> Void)?

    private let copyButton = NSButton()
    private let deleteButton = NSButton()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = NSColor.windowBackgroundColor
            .withAlphaComponent(0.85).cgColor

        copyButton.image = NSImage(
            systemSymbolName: "doc.on.doc",
            accessibilityDescription: "Copy"
        )
        copyButton.bezelStyle = .inline
        copyButton.isBordered = false
        copyButton.target = self
        copyButton.action = #selector(copyTapped)
        copyButton.toolTip = "Copy image"
        addSubview(copyButton)

        deleteButton.image = NSImage(
            systemSymbolName: "trash",
            accessibilityDescription: "Delete"
        )
        deleteButton.bezelStyle = .inline
        deleteButton.isBordered = false
        deleteButton.contentTintColor = .systemRed
        deleteButton.target = self
        deleteButton.action = #selector(deleteTapped)
        deleteButton.toolTip = "Delete image"
        addSubview(deleteButton)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let buttonSize: CGFloat = 24
        let padding: CGFloat = 4
        copyButton.frame = CGRect(
            x: padding, y: (bounds.height - buttonSize) / 2,
            width: buttonSize, height: buttonSize
        )
        deleteButton.frame = CGRect(
            x: padding + buttonSize + 4,
            y: (bounds.height - buttonSize) / 2,
            width: buttonSize, height: buttonSize
        )
    }

    // Prevent clicks from passing through to the text view
    override func mouseDown(with event: NSEvent) {}

    @objc private func copyTapped() { onCopy?() }
    @objc private func deleteTapped() { onDelete?() }
}

struct RichTextFormat: DocumentFormat {
    func render(_ text: String) -> NSAttributedString {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: Theme.editorNSFont(ofSize: 16),
            .foregroundColor: NSColor.textColor
        ]
        return NSAttributedString(string: text, attributes: attrs)
    }

    func toPlainText(_ attributed: NSAttributedString) -> String {
        attributed.string
    }
}

// MARK: - MarkdownFormat Image Helpers

extension MarkdownFormat {
    static func restoreImageMarkup(in text: String) -> String {
        text.replacingOccurrences(of: attachmentCharacter, with: "!")
    }

    /// Restore markdown from rendered attributed content:
    /// image attachments and visually replaced list markers.
    static func restoreMarkup(in attributed: NSAttributedString) -> String {
        let mutableText = NSMutableString(string: attributed.string)
        let fullRange = NSRange(location: 0, length: attributed.length)

        attributed.enumerateAttribute(listMarkerKey, in: fullRange) { value, range, _ in
            guard let marker = value as? String, marker.count == 1 else { return }
            for offset in 0..<range.length {
                mutableText.replaceCharacters(
                    in: NSRange(location: range.location + offset, length: 1),
                    with: marker
                )
            }
        }

        return restoreImageMarkup(in: String(mutableText))
    }

    static func maxRenderedImageSize(for baseFont: NSFont) -> NSSize {
        NSSize(width: 560, height: max(baseFont.pointSize * 18, 220))
    }

    /// Parse `=WIDTHx` from image markup like `![alt](path =300x)`.
    static func parseImageWidth(from markup: String) -> CGFloat? {
        guard let range = markup.range(of: #"=(\d+)x\)$"#, options: .regularExpression),
              let numRange = markup.range(of: #"\d+"#, options: .regularExpression, range: range)
        else { return nil }
        return CGFloat(Int(markup[numRange]) ?? 0)
    }

    /// Return new markup with the width set or updated.
    static func markupWithWidth(_ markup: String, width: Int) -> String {
        var cleaned = markup.replacingOccurrences(
            of: #"\s+=\d+x\)"#, with: ")", options: .regularExpression
        )
        if let parenIndex = cleaned.lastIndex(of: ")") {
            cleaned.insert(contentsOf: " =\(width)x", at: parenIndex)
        }
        return cleaned
    }
}
