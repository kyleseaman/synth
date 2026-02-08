import SwiftUI
import AppKit

protocol DocumentFormat {
    func render(_ text: String) -> NSAttributedString
    func toPlainText(_ attributed: NSAttributedString) -> String
}

struct MarkdownFormat: DocumentFormat {
    struct PendingImageRender {
        let imageURL: URL
        let markupRange: NSRange
        let markupText: String
        let attachmentRange: NSRange
    }

    var noteIndex: NoteIndex?
    var baseURL: URL?

    func render(_ text: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let bodyFont = NSFont.systemFont(ofSize: 16)
        let bodyParagraph = NSMutableParagraphStyle()
        bodyParagraph.lineHeightMultiple = 1.25
        let defaultAttrs: [NSAttributedString.Key: Any] = [
            .font: bodyFont, .foregroundColor: NSColor.textColor,
            .paragraphStyle: bodyParagraph
        ]

        let lines = text.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            var attrs = defaultAttrs

            // Style headings — hide # prefix visually
            var headingPrefixLen = 0
            if line.hasPrefix("# ") {
                attrs[.font] = NSFont.systemFont(ofSize: 28, weight: .bold)
                headingPrefixLen = 2
            } else if line.hasPrefix("## ") {
                attrs[.font] = NSFont.systemFont(ofSize: 22, weight: .bold)
                headingPrefixLen = 3
            } else if line.hasPrefix("### ") {
                attrs[.font] = NSFont.systemFont(ofSize: 18, weight: .semibold)
                headingPrefixLen = 4
            }

            // Enforce minimum line height so hidden prefix doesn't
            // collapse the line fragment (e.g. "# " with no content)
            if headingPrefixLen > 0, let headingFont = attrs[.font] as? NSFont {
                let para = NSMutableParagraphStyle()
                para.lineHeightMultiple = 1.25
                para.minimumLineHeight = ceil(
                    headingFont.ascender - headingFont.descender
                        + headingFont.leading
                )
                attrs[.paragraphStyle] = para
            }

            let lineStr = NSMutableAttributedString(string: line, attributes: attrs)
            if headingPrefixLen > 0 {
                let hiddenAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 0.01),
                    .foregroundColor: NSColor.clear
                ]
                lineStr.addAttributes(
                    hiddenAttrs,
                    range: NSRange(location: 0, length: headingPrefixLen)
                )
            }
            applyInlineFormatting(lineStr, baseFont: attrs[.font] as? NSFont ?? bodyFont)
            if index < lines.count - 1 {
                lineStr.append(NSAttributedString(string: "\n", attributes: defaultAttrs))
            }
            result.append(lineStr)
        }
        return result
    }

    func toPlainText(_ attributed: NSAttributedString) -> String {
        attributed.string
    }

    /// Character used by NSTextView to render inline attachments.
    static let attachmentCharacter = "\u{FFFC}"

    /// Custom attribute key storing the resolved image file URL.
    static let imageURLKey = NSAttributedString.Key("synth.imageURL")

    /// Custom attribute storing the original markup text for resize.
    static let imageMarkupKey = NSAttributedString.Key(
        "synth.imageMarkup"
    )

    @discardableResult
    static func applyImageRendering(
        in attributedText: NSMutableAttributedString,
        baseFont: NSFont,
        baseDirectoryURL: URL?
    ) -> [PendingImageRender] {
        let maxSize = maxRenderedImageSize(for: baseFont)
        var pendingRenders: [PendingImageRender] = []

        // Match ![alt](path) or ![alt](path =WIDTHx)
        // swiftlint:disable:next force_try
        let imagePattern = try! NSRegularExpression(
            pattern: "!\\[[^\\]]*\\]\\(([^)\\s]+)(?:\\s+=([0-9]+)x)?\\)"
        )
        let fullRange = NSRange(
            location: 0, length: attributedText.string.utf16.count
        )

        for imageMatch in imagePattern.matches(
            in: attributedText.string, range: fullRange
        ).reversed() {
            let markupRange = imageMatch.range
            let pathRange = imageMatch.range(at: 1)
            guard pathRange.location != NSNotFound,
                  let pathSwiftRange = Range(
                      pathRange, in: attributedText.string
                  ) else { continue }

            let pathValue = String(
                attributedText.string[pathSwiftRange]
            )
            guard let imageURL = MediaManager.resolvedImageURL(
                from: pathValue,
                baseDirectoryURL: baseDirectoryURL
            ) else { continue }

            // Parse optional width
            var requestedWidth: CGFloat?
            let widthRange = imageMatch.range(at: 2)
            if widthRange.location != NSNotFound,
               let widthSwiftRange = Range(
                   widthRange, in: attributedText.string
               ),
               let parsed = Int(
                   attributedText.string[widthSwiftRange]
               ) {
                requestedWidth = CGFloat(parsed)
            }

            let markupText = (attributedText.string as NSString)
                .substring(with: markupRange)
            let cachedImage = WorkspaceImageLoader.shared.cachedImage(
                at: imageURL,
                maxSize: maxSize
            )
            let attachment = NSTextAttachment()
            let displayImage = cachedImage
                ?? NSImage(
                    systemSymbolName: "photo",
                    accessibilityDescription: nil
                )
            attachment.image = displayImage

            if let width = requestedWidth,
               let img = displayImage,
               img.size.width > 0 {
                let scale = width / img.size.width
                attachment.bounds = CGRect(
                    x: 0, y: 0,
                    width: width,
                    height: img.size.height * scale
                )
            }

            // Hide the markdown syntax after the first character
            let tailRange = NSRange(
                location: markupRange.location + 1,
                length: markupRange.length - 1
            )
            let hiddenAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 0.01),
                .foregroundColor: NSColor.clear
            ]
            attributedText.addAttributes(
                hiddenAttributes, range: tailRange
            )

            // Replace leading "!" with the object replacement
            // character so NSTextView renders the attachment
            let bangRange = NSRange(
                location: markupRange.location, length: 1
            )
            let attachmentStr = NSMutableAttributedString(
                attributedString: NSAttributedString(
                    attachment: attachment
                )
            )
            let attrRange = NSRange(location: 0, length: 1)
            attachmentStr.addAttribute(
                imageURLKey, value: imageURL, range: attrRange
            )
            attachmentStr.addAttribute(
                imageMarkupKey,
                value: markupText,
                range: attrRange
            )
            attributedText.replaceCharacters(
                in: bangRange,
                with: attachmentStr
            )

            pendingRenders.append(
                PendingImageRender(
                    imageURL: imageURL,
                    markupRange: markupRange,
                    markupText: markupText,
                    attachmentRange: bangRange
                )
            )
        }

        return pendingRenders
    }

    /// Restore object replacement characters back to `!` so the
    /// underlying plain text stays valid markdown.
    static func restoreImageMarkup(in text: String) -> String {
        text.replacingOccurrences(of: attachmentCharacter, with: "!")
    }

    static func maxRenderedImageSize(for baseFont: NSFont) -> NSSize {
        NSSize(
            width: 560,
            height: max(baseFont.pointSize * 18, 220)
        )
    }

    /// Parse `=WIDTHx` from image markup like `![alt](path =300x)`.
    static func parseImageWidth(from markup: String) -> CGFloat? {
        guard let range = markup.range(of: #"=(\d+)x\)$"#, options: .regularExpression),
              let numRange = markup.range(of: #"\d+"#, options: .regularExpression, range: range)
        else { return nil }
        return CGFloat(Int(markup[numRange]) ?? 0)
    }

    /// Return new markup with the width set or updated.
    static func markupWithWidth(
        _ markup: String, width: Int
    ) -> String {
        // Remove existing =WIDTHx if present
        var cleaned = markup.replacingOccurrences(
            of: #"\s+=\d+x\)"#,
            with: ")",
            options: .regularExpression
        )
        // Insert =WIDTHx before closing paren
        if let parenIndex = cleaned.lastIndex(of: ")") {
            cleaned.insert(
                contentsOf: " =\(width)x",
                at: parenIndex
            )
        }
        return cleaned
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

            // Apply link styling to inner text (visible)
            str.addAttributes(linkAttrs, range: innerNSRange)

            // Hide [[ and ]] brackets visually (keep in source for save)
            let hiddenAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 0.01),
                .foregroundColor: NSColor.clear,
                .link: linkURL
            ]
            let openRange = NSRange(location: fullNSRange.location, length: 2)
            let closeRange = NSRange(
                location: fullNSRange.location + fullNSRange.length - 2,
                length: 2
            )
            str.addAttributes(hiddenAttrs, range: openRange)
            str.addAttributes(hiddenAttrs, range: closeRange)
        }

        // MARK: @Date mentions (@2026-02-07) — styled as daily note links
        // swiftlint:disable:next force_try
        let datePattern = try! NSRegularExpression(
            pattern: "@(\\d{4}-\\d{2}-\\d{2})"
        )
        let dateRange = NSRange(
            location: 0, length: str.string.utf16.count
        )
        for match in datePattern.matches(
            in: str.string, range: dateRange
        ).reversed() {
            let fullNSRange = match.range
            let innerNSRange = match.range(at: 1)
            guard let innerSwiftRange = Range(
                innerNSRange, in: str.string
            ) else { continue }
            let dateStr = String(str.string[innerSwiftRange])
            // swiftlint:disable:next force_unwrapping
            let linkURL = URL(string: "synth://daily/\(dateStr)")!
            // Style the date part as a link
            let linkAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(
                    ofSize: baseFont.pointSize, weight: .medium
                ),
                .foregroundColor: NSColor.controlAccentColor,
                .link: linkURL,
                .cursor: NSCursor.pointingHand
            ]
            str.addAttributes(linkAttrs, range: innerNSRange)

            // Hide the @ prefix
            let hiddenAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 0.01),
                .foregroundColor: NSColor.clear,
                .link: linkURL
            ]
            str.addAttributes(
                hiddenAttrs,
                range: NSRange(
                    location: fullNSRange.location, length: 1
                )
            )
        }



        // MARK: @People mentions
        let personPattern = PeopleIndex.personPattern
        let personRange = NSRange(location: 0, length: str.string.utf16.count)
        for match in personPattern.matches(in: str.string, range: personRange).reversed() {
            let fullNSRange = match.range
            let innerNSRange = match.range(at: 1)
            guard let innerSwiftRange = Range(innerNSRange, in: str.string) else { continue }
            let personName = String(str.string[innerSwiftRange])
            guard personName.count >= 2 else { continue }
            let personLower = personName.lowercased()
            // swiftlint:disable:next force_unwrapping
            let personURL = URL(string: "synth://person/\(personLower)")!
            let mediumFont = NSFont.systemFont(ofSize: baseFont.pointSize, weight: .medium)
            let replacement = NSAttributedString(
                string: "@\(personName)",
                attributes: [
                    .font: mediumFont,
                    .foregroundColor: NSColor.systemPurple,
                    .backgroundColor: NSColor.systemPurple.withAlphaComponent(0.10),
                    .link: personURL,
                    .cursor: NSCursor.pointingHand
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

        // MARK: Bold **text** — style inner text, keep markers
        // swiftlint:disable:next force_try
        let boldPattern = try! NSRegularExpression(pattern: "\\*\\*(.+?)\\*\\*")
        let boldRange = NSRange(location: 0, length: str.string.utf16.count)
        for match in boldPattern.matches(in: str.string, range: boldRange) {
            let innerRange = match.range(at: 1)
            let boldFont = NSFontManager.shared.convert(
                baseFont, toHaveTrait: .boldFontMask
            )
            str.addAttribute(.font, value: boldFont, range: innerRange)
        }

        // MARK: Italic *text* — style inner text, keep markers
        // swiftlint:disable:next force_try
        let italicPattern = try! NSRegularExpression(
            pattern: "(?<!\\*)\\*([^*]+)\\*(?!\\*)"
        )
        let italicRange = NSRange(location: 0, length: str.string.utf16.count)
        for match in italicPattern.matches(in: str.string, range: italicRange) {
            let innerRange = match.range(at: 1)
            let italicFont = NSFontManager.shared.convert(
                baseFont, toHaveTrait: .italicFontMask
            )
            str.addAttribute(.font, value: italicFont, range: innerRange)
        }

        // MARK: Underline __text__ — style inner text, keep markers
        // swiftlint:disable:next force_try
        let underlinePattern = try! NSRegularExpression(pattern: "__(.+?)__")
        let underlineRange = NSRange(location: 0, length: str.string.utf16.count)
        for match in underlinePattern.matches(in: str.string, range: underlineRange) {
            let innerRange = match.range(at: 1)
            str.addAttribute(
                .underlineStyle,
                value: NSUnderlineStyle.single.rawValue,
                range: innerRange
            )
        }

        // MARK: Inline code `text` — style inner text, keep backticks
        // swiftlint:disable:next force_try
        let codePattern = try! NSRegularExpression(pattern: "`([^`]+)`")
        let codeRange = NSRange(location: 0, length: str.string.utf16.count)
        for match in codePattern.matches(in: str.string, range: codeRange) {
            let innerRange = match.range(at: 1)
            str.addAttributes([
                .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
                .foregroundColor: NSColor.systemPink,
                .backgroundColor: NSColor.quaternaryLabelColor
            ], range: innerRange)
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
        // Draw two diagonal lines (bottom-right grip)
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
    var imagePasteHandler: ((NSImage) -> String?)?
    var onImageAction: ((ImageOverlayAction, URL) -> Void)?

    enum ImageOverlayAction { case copy, delete, open }

    /// Called when the user finishes dragging the resize handle.
    /// Parameters: original markup string, new width in points.
    var onImageResize: ((String, Int) -> Void)?

    private lazy var imageOverlay: ImageAttachmentOverlay = {
        let overlay = ImageAttachmentOverlay()
        overlay.isHidden = true
        overlay.onCopy = { [weak self] in
            guard let url = self?.hoveredImageURL else { return }
            self?.onImageAction?(.copy, url)
        }
        overlay.onDelete = { [weak self] in
            guard let url = self?.hoveredImageURL else { return }
            self?.onImageAction?(.delete, url)
        }
        addSubview(overlay)
        return overlay
    }()
    private var hoveredImageURL: URL?
    private var hoveredImageMarkup: String?
    private var hoveredImageRect: CGRect?
    private var hoveredImageCharIndex: Int?
    private var imageTrackingArea: NSTrackingArea?
    private var isResizeDragging = false
    private var resizeDragStartX: CGFloat = 0
    private var resizeDragStartWidth: CGFloat = 0
    private var resizeDragAspectRatio: CGFloat = 1
    /// Set during live resize to suppress textDidChange reformatting.
    var isResizing = false

    private lazy var resizeHandle: ResizeGripView = {
        let handle = ResizeGripView(
            frame: CGRect(x: 0, y: 0, width: 16, height: 16)
        )
        handle.isHidden = true
        addSubview(handle)
        return handle
    }()

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = imageTrackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        imageTrackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        updateImageOverlay(for: event)
        let point = convert(event.locationInWindow, from: nil)
        if !resizeHandle.isHidden,
           let rect = hoveredImageRect,
           resizeHandleRect(for: rect).contains(point) {
            NSCursor.resizeLeftRight.set()
        } else {
            NSCursor.iBeam.set()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        // Check if clicking the resize handle
        if !resizeHandle.isHidden,
           let rect = hoveredImageRect {
            let handleRect = resizeHandleRect(for: rect)
            if handleRect.contains(point) {
                isResizeDragging = true
                isResizing = true
                resizeDragStartX = point.x
                resizeDragStartWidth = rect.width
                resizeDragAspectRatio = rect.height > 0
                    ? rect.width / rect.height : 1
                return
            }
        }

        if let imageURL = imageURL(at: point) {
            onImageAction?(.open, imageURL)
            return
        }
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isResizeDragging,
              let charIndex = hoveredImageCharIndex,
              let storage = textStorage,
              charIndex < storage.length
        else {
            if !isResizeDragging {
                super.mouseDragged(with: event)
            }
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        let delta = point.x - resizeDragStartX
        let newWidth = max(80, resizeDragStartWidth + delta)
        let newHeight = newWidth / resizeDragAspectRatio

        // Rebuild the attachment with new bounds and replace in storage
        // to force NSLayoutManager to pick up the size change.
        guard let oldAttachment = storage.attribute(
            .attachment, at: charIndex, effectiveRange: nil
        ) as? NSTextAttachment else { return }

        let newAttachment = NSTextAttachment()
        newAttachment.image = oldAttachment.image
        newAttachment.bounds = CGRect(
            x: 0, y: 0, width: newWidth, height: newHeight
        )
        let replacement = NSMutableAttributedString(
            attributedString: NSAttributedString(
                attachment: newAttachment
            )
        )
        // Preserve custom attributes
        let attrRange = NSRange(location: 0, length: 1)
        if let url = hoveredImageURL {
            replacement.addAttribute(
                MarkdownFormat.imageURLKey,
                value: url, range: attrRange
            )
        }
        if let markup = hoveredImageMarkup {
            replacement.addAttribute(
                MarkdownFormat.imageMarkupKey,
                value: markup, range: attrRange
            )
        }
        let charRange = NSRange(location: charIndex, length: 1)
        storage.replaceCharacters(in: charRange, with: replacement)
    }

    override func mouseUp(with event: NSEvent) {
        guard isResizeDragging else {
            super.mouseUp(with: event)
            return
        }
        isResizeDragging = false
        isResizing = false
        let point = convert(event.locationInWindow, from: nil)
        let delta = point.x - resizeDragStartX
        let newWidth = Int(max(80, resizeDragStartWidth + delta))
        if let markup = hoveredImageMarkup {
            onImageResize?(markup, newWidth)
        }
    }

    private func updateImageOverlay(for event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let imageURL = imageURL(at: point),
              let attachRect = attachmentRect(at: point)
        else {
            if !imageOverlay.isHidden {
                imageOverlay.isHidden = true
                resizeHandle.isHidden = true
                hoveredImageURL = nil
                hoveredImageMarkup = nil
                hoveredImageRect = nil
                hoveredImageCharIndex = nil
            }
            return
        }
        hoveredImageURL = imageURL
        hoveredImageRect = attachRect
        hoveredImageMarkup = imageMarkup(at: point)
        hoveredImageCharIndex = charIndex(at: point)

        let overlaySize = CGSize(width: 64, height: 28)
        imageOverlay.frame = CGRect(
            x: attachRect.maxX - overlaySize.width - 6,
            y: attachRect.minY + 6,
            width: overlaySize.width,
            height: overlaySize.height
        )
        imageOverlay.isHidden = false

        let handleRect = resizeHandleRect(for: attachRect)
        resizeHandle.frame = handleRect
        resizeHandle.isHidden = false
    }

    private func resizeHandleRect(for imageRect: CGRect) -> CGRect {
        CGRect(
            x: imageRect.maxX - 16,
            y: imageRect.maxY - 16,
            width: 16,
            height: 16
        )
    }

    private func imageMarkup(at point: CGPoint) -> String? {
        guard let textStorage = textStorage else { return nil }
        guard let idx = charIndex(at: point),
              idx < textStorage.length else { return nil }
        return textStorage.attribute(
            MarkdownFormat.imageMarkupKey,
            at: idx,
            effectiveRange: nil
        ) as? String
    }

    private func imageURL(at point: CGPoint) -> URL? {
        guard let textStorage = textStorage
        else { return nil }
        let idx = charIndex(at: point)
        guard let idx, idx < textStorage.length else { return nil }
        return textStorage.attribute(
            MarkdownFormat.imageURLKey,
            at: idx,
            effectiveRange: nil
        ) as? URL
    }

    private func charIndex(at point: CGPoint) -> Int? {
        guard let textStorage = textStorage,
              let layoutManager = layoutManager,
              let textContainer = textContainer
        else { return nil }
        let textPoint = CGPoint(
            x: point.x - textContainerInset.width,
            y: point.y - textContainerInset.height
        )
        let idx = layoutManager.characterIndex(
            for: textPoint,
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: nil
        )
        guard idx < textStorage.length else { return nil }
        return idx
    }

    private func attachmentRect(at point: CGPoint) -> CGRect? {
        guard let layoutManager = layoutManager,
              let textContainer = textContainer
        else { return nil }
        let textPoint = CGPoint(
            x: point.x - textContainerInset.width,
            y: point.y - textContainerInset.height
        )
        let glyphIndex = layoutManager.glyphIndex(
            for: textPoint, in: textContainer
        )
        var lineRange = NSRange()
        let lineRect = layoutManager.lineFragmentRect(
            forGlyphAt: glyphIndex, effectiveRange: &lineRange
        )
        let glyphRect = layoutManager.boundingRect(
            forGlyphRange: NSRange(location: glyphIndex, length: 1),
            in: textContainer
        )
        let rect = CGRect(
            x: glyphRect.origin.x + textContainerInset.width,
            y: lineRect.origin.y + textContainerInset.height,
            width: glyphRect.width,
            height: lineRect.height
        )
        // Only return if the point is actually inside the image area
        guard rect.contains(point), rect.height > 20 else { return nil }
        return rect
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

    override func paste(_ sender: Any?) {
        let classes: [AnyClass] = [NSImage.self]
        if let imageObject = NSPasteboard.general.readObjects(
            forClasses: classes,
            options: nil
        )?.first as? NSImage {
            guard let markdownImage = imagePasteHandler?(imageObject) else {
                NSSound.beep()
                return
            }
            insertText(markdownImage, replacementRange: selectedRange())
            return
        }
        super.paste(sender)
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
                // Keep popup open for multi-word person names
                postQueryUpdate()
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

    func toggleBold() { toggleMarkdownWrap("**") }
    func toggleItalic() { toggleMarkdownWrap("*") }

    private func toggleMarkdownWrap(_ marker: String) {
        let range = selectedRange()
        guard range.length > 0, let storage = textStorage else { return }
        let text = storage.string as NSString
        let selected = text.substring(with: range)
        let markerLen = marker.count

        // Check if already wrapped with this marker
        let hasBefore = range.location >= markerLen
            && text.substring(
                with: NSRange(location: range.location - markerLen, length: markerLen)
            ) == marker
        let hasAfter = range.location + range.length + markerLen <= text.length
            && text.substring(
                with: NSRange(location: range.location + range.length, length: markerLen)
            ) == marker

        if hasBefore && hasAfter {
            // Remove markers
            let fullRange = NSRange(
                location: range.location - markerLen,
                length: range.length + markerLen * 2
            )
            storage.replaceCharacters(in: fullRange, with: selected)
            setSelectedRange(NSRange(
                location: range.location - markerLen,
                length: range.length
            ))
        } else {
            // Add markers
            let wrapped = "\(marker)\(selected)\(marker)"
            storage.replaceCharacters(in: range, with: wrapped)
            setSelectedRange(NSRange(
                location: range.location + markerLen,
                length: range.length
            ))
        }
    }

    func toggleUnderline() { toggleMarkdownWrap("__") }

    // MARK: - Shared Autocomplete Completion

    struct AutocompleteResult {
        let completedWikiLink: Bool
        let completedPerson: Bool
        let completedDate: Bool
    }

    func completeAutocomplete(title: String) -> AutocompleteResult {
        guard let storage = textStorage else {
            return AutocompleteResult(
                completedWikiLink: false,
                completedPerson: false,
                completedDate: false
            )
        }
        let cursor = selectedRange().location
        let previousState = wikiLinkState
        var didCompletePerson = false
        var didCompleteDate = false

        switch wikiLinkState {
        case .wikiLinkActive(let start):
            let replaceStart = max(start - 2, 0)
            let range = NSRange(
                location: replaceStart,
                length: cursor - replaceStart
            )
            let replacement = "[[\(title)]]"
            storage.replaceCharacters(in: range, with: replacement)
            setSelectedRange(NSRange(
                location: replaceStart + replacement.count,
                length: 0
            ))

        case .atActive(let start):
            let replaceStart = max(start - 1, 0)
            let range = NSRange(
                location: replaceStart,
                length: cursor - replaceStart
            )
            let isDateToken = DailyNoteResolver.resolveDate(
                title
            ) != nil
            let isPerson = !isDateToken
            let displayTitle = isPerson
                ? title.titleCased : title
            let replacement = isPerson
                ? "@\(displayTitle) " : "@\(title) "
            storage.replaceCharacters(
                in: range, with: replacement
            )
            setSelectedRange(NSRange(
                location: replaceStart + replacement.count,
                length: 0
            ))
            didCompletePerson = isPerson
            didCompleteDate = isDateToken

        case .hashtagActive(let start):
            let replaceStart = max(start - 1, 0)
            let range = NSRange(
                location: replaceStart,
                length: cursor - replaceStart
            )
            let tagText = title.hasPrefix("#")
                ? title : "#\(title)"
            let replacement = "\(tagText) "
            storage.replaceCharacters(
                in: range, with: replacement
            )
            setSelectedRange(NSRange(
                location: replaceStart + replacement.count,
                length: 0
            ))

        default:
            break
        }

        wikiLinkState = .idle

        let wasWikiLink: Bool
        if case .wikiLinkActive = previousState {
            wasWikiLink = true
        } else {
            wasWikiLink = false
        }

        return AutocompleteResult(
            completedWikiLink: wasWikiLink,
            completedPerson: didCompletePerson,
            completedDate: didCompleteDate
        )
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
        let baseDirectory = store?.currentDocumentURL?.deletingLastPathComponent()
        return MarkdownFormat(noteIndex: store?.noteIndex, baseURL: baseDirectory)
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
        let typingParagraph = NSMutableParagraphStyle()
        typingParagraph.lineHeightMultiple = 1.25
        textView.typingAttributes = [
            .font: NSFont.systemFont(ofSize: 16),
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: typingParagraph
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
        context.coordinator.bindImagePasteHandler(to: textView)
        context.coordinator.bindImageOverlay(to: textView)
        textView.layoutManager?.delegate = context.coordinator

        context.coordinator.boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { _ in
            context.coordinator.updateScrollOffset()
        }

        // MARK: Autocomplete (wiki links, @mentions, #tags)
        context.coordinator.setupAutocomplete()

        // Initialize line positions and set focus
        DispatchQueue.main.async {
            context.coordinator.updateLinePositions()
            textView.window?.makeFirstResponder(textView)
            // Place cursor after heading prefix for new notes
            if textView.string.hasPrefix("# \n") {
                textView.setSelectedRange(NSRange(location: 2, length: 0))
            }
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        context.coordinator.parent = self
        context.coordinator.store = store
        context.coordinator.autocomplete.store = store

        let restoredString = MarkdownFormat.restoreImageMarkup(
            in: textView.string
        )
        if !context.coordinator.isEditing && restoredString != text {
            textView.textStorage?.setAttributedString(format.render(text))
            context.coordinator.applyFormatting()
            DispatchQueue.main.async {
                context.coordinator.updateLinePositions()
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTextViewDelegate, NSLayoutManagerDelegate {
        var parent: MarkdownEditor
        var textView: FormattingTextView?
        var scrollView: NSScrollView?
        var isEditing = false
        var isFormatting = false
        var boundsObserver: NSObjectProtocol?
        weak var store: DocumentStore?
        let autocomplete = AutocompleteCoordinator()
        private var saveTimer: Timer?

        init(_ parent: MarkdownEditor) { self.parent = parent }

        deinit {
            saveTimer?.invalidate()
            if let observer = boundsObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        // MARK: - Autocomplete Setup

        func setupAutocomplete() {
            autocomplete.textView = textView
            autocomplete.store = store
            autocomplete.onTextChange = { [weak self] in
                guard let self = self,
                      let textView = self.textView
                else { return }
                self.parent.text = MarkdownFormat.restoreImageMarkup(
                    in: textView.string
                )
                self.applyFormatting()
            }
            autocomplete.setupObservers()
        }

        // MARK: - Image Paste

        func markdownForPastedImage(_ image: NSImage) -> String? {
            guard let store,
                  let noteURL = store.currentDocumentURL,
                  let relativePath = store.savePastedImageToMedia(
                      image, noteURL: noteURL
                  ) else { return nil }
            return "![Screenshot](\(relativePath))"
        }

        func bindImagePasteHandler(to textView: FormattingTextView) {
            textView.imagePasteHandler = { [weak self] image in
                self?.markdownForPastedImage(image)
            }
        }

        // MARK: - Image Overlay

        func bindImageOverlay(to textView: FormattingTextView) {
            textView.onImageAction = { [weak self] action, imageURL in
                self?.handleImageAction(action, imageURL: imageURL)
            }
            textView.onImageResize = { [weak self] markup, newWidth in
                self?.handleImageResize(
                    originalMarkup: markup, newWidth: newWidth
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
            parent.text = newText
            applyFormatting()
        }

        private func handleImageAction(
            _ action: FormattingTextView.ImageOverlayAction,
            imageURL: URL
        ) {
            switch action {
            case .copy:
                guard let image = NSImage(contentsOf: imageURL)
                else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([image])
            case .delete:
                try? FileManager.default.trashItem(
                    at: imageURL, resultingItemURL: nil
                )
                removeImageMarkup(for: imageURL)
                store?.loadFileTree()
                applyFormatting()
            case .open:
                guard let store else { return }
                let notes = store.notesReferencing(
                    mediaFilename: imageURL.lastPathComponent
                )
                NotificationCenter.default.post(
                    name: .showImageDetail,
                    object: nil,
                    userInfo: [
                        "mediaURL": imageURL,
                        "notes": notes.map { $0.url }
                    ]
                )
            }
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
                    + NSRegularExpression.escapedPattern(for: filename)
                    + "\\)\\n?"
            )
            let cleaned = pattern.stringByReplacingMatches(
                in: text,
                range: NSRange(location: 0, length: text.utf16.count),
                withTemplate: ""
            )
            parent.text = cleaned
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

            layoutManager.ensureLayout(for: textContainer)

            let textInset = textView.textContainerInset.height
            let baseFont = NSFont.systemFont(ofSize: 16)
            var positions: [CGFloat] = []
            let nsString = textView.string as NSString
            let length = nsString.length

            if length == 0 {
                positions.append(textInset + baseFont.pointSize / 2)
                parent.linePositions = positions
                return
            }

            // Walk logical lines, use layout rect for accurate Y
            var charIndex = 0
            while charIndex < length {
                let glyphIndex = layoutManager.glyphIndexForCharacter(
                    at: charIndex
                )
                var lineRange = NSRange()
                let rect = layoutManager.lineFragmentRect(
                    forGlyphAt: glyphIndex,
                    effectiveRange: &lineRange
                )
                positions.append(textInset + rect.midY)

                // Advance to next line
                let lineEnd = NSMaxRange(
                    nsString.lineRange(for: NSRange(
                        location: charIndex, length: 0
                    ))
                )
                charIndex = lineEnd == charIndex ? charIndex + 1 : lineEnd
            }

            // Trailing newline produces an empty last line with no
            // characters — use extraLineFragmentRect for its position
            let extraRect = layoutManager.extraLineFragmentRect
            if extraRect.height > 0 {
                positions.append(textInset + extraRect.midY)
            }

            DispatchQueue.main.async {
                self.parent.linePositions = positions
            }
        }

        // MARK: - Layout Delegate

        func layoutManager(
            _ layoutManager: NSLayoutManager,
            didCompleteLayoutFor textContainer: NSTextContainer?,
            atEnd layoutFinishedFlag: Bool
        ) {
            if layoutFinishedFlag && !isFormatting {
                updateLinePositions()
            }
        }

        // MARK: - Text Delegate Methods

        func textDidBeginEditing(_ notification: Notification) { isEditing = true }
        func textDidEndEditing(_ notification: Notification) {
            isEditing = false
            saveTimer?.invalidate()
            store?.saveAll()
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = textView,
                  !isFormatting,
                  !textView.isResizing
            else { return }
            parent.text = MarkdownFormat.restoreImageMarkup(
                in: textView.string
            )
            applyFormatting()
            updateLinePositions()
            scheduleSave()
        }

        private func scheduleSave() {
            saveTimer?.invalidate()
            saveTimer = Timer.scheduledTimer(
                withTimeInterval: 1.0, repeats: false
            ) { [weak self] _ in
                self?.store?.saveAll()
            }
        }

        // MARK: - Live Formatting

        func applyFormatting() {
            guard let textView = textView,
                  let storage = textView.textStorage
            else { return }
            isFormatting = true
            let cursor = textView.selectedRange()
            let cleanText = MarkdownFormat.restoreImageMarkup(
                in: textView.string
            )
            let format = MarkdownFormat(noteIndex: store?.noteIndex)
            storage.setAttributedString(
                format.render(cleanText)
            )

            let baseFont = NSFont.systemFont(ofSize: 16)
            let baseDirectory = store?.currentDocumentURL?
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
            let maxSize = MarkdownFormat.maxRenderedImageSize(for: baseFont)

            for request in requests {
                WorkspaceImageLoader.shared.loadImage(
                    at: request.imageURL,
                    maxSize: maxSize
                ) { [weak self] loadedImage in
                    guard let self,
                          let loadedImage,
                          let textView = self.textView,
                          let currentStorage = textView.textStorage,
                          currentStorage === storage else { return }

                    let storageString = currentStorage.string as NSString
                    let storageLength = storageString.length
                    let markupEnd = request.markupRange.location
                        + request.markupRange.length
                    guard markupEnd <= storageLength else { return }

                    let currentMarkup = storageString.substring(
                        with: request.markupRange
                    )
                    let expectedMarkup = MarkdownFormat.attachmentCharacter
                        + request.markupText.dropFirst()
                    guard currentMarkup == expectedMarkup
                    else { return }

                    let attachment = NSTextAttachment()
                    attachment.image = loadedImage

                    // Apply persisted width if present
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
