import SwiftUI
import AppKit

struct MarkdownFormat: DocumentFormat {
    struct PendingImageRender {
        let imageURL: URL
        let markupRange: NSRange
        let markupText: String
        let attachmentRange: NSRange
    }

    // MARK: - Precompiled Patterns

    // swiftlint:disable force_try
    static let wikiPattern = try! NSRegularExpression(pattern: "\\[\\[(.+?)\\]\\]")
    static let datePattern = try! NSRegularExpression(pattern: "@(\\d{4}-\\d{2}-\\d{2})")
    static let boldPattern = try! NSRegularExpression(pattern: "\\*\\*(.+?)\\*\\*")
    static let italicPattern = try! NSRegularExpression(
        pattern: "(?<!\\*)\\*([^*]+)\\*(?!\\*)"
    )
    static let underscoreItalicPattern = try! NSRegularExpression(
        pattern: "(?<!_)_([^_]+)_(?!_)"
    )
    static let underlinePattern = try! NSRegularExpression(pattern: "__(.+?)__")
    static let codePattern = try! NSRegularExpression(pattern: "`([^`]+)`")
    static let listPattern = try! NSRegularExpression(pattern: #"^(\s*)([-*])\s+"#)
    static let imagePattern = try! NSRegularExpression(
        pattern: "!\\[[^\\]]*\\]\\((.+?)(?:\\s+=([0-9]+)x)?\\)"
    )
    static let tableSeparatorPattern = try! NSRegularExpression(
        pattern: "^\\|[-:| ]+\\|$"
    )
    // swiftlint:enable force_try

    var noteIndex: NoteIndex?
    var baseURL: URL?
    var hideSyntax: Bool {
        UserDefaults.standard.bool(forKey: "hideSyntax")
    }

    // MARK: - Cached Paragraph Styles

    nonisolated(unsafe) private static let bodyParagraphStyle: NSParagraphStyle = {
        let para = NSMutableParagraphStyle()
        para.lineHeightMultiple = 1.25
        return para
    }()

    private static func headingParagraphStyle(for font: NSFont) -> NSParagraphStyle {
        let para = NSMutableParagraphStyle()
        para.lineHeightMultiple = 1.25
        para.minimumLineHeight = ceil(font.ascender - font.descender + font.leading)
        return para
    }

    // Cache heading paragraph styles keyed by font size
    nonisolated(unsafe) private static let h1ParagraphStyle = headingParagraphStyle(
        for: Theme.editorNSFont(ofSize: 28, weight: .bold)
    )
    nonisolated(unsafe) private static let h2ParagraphStyle = headingParagraphStyle(
        for: Theme.editorNSFont(ofSize: 22, weight: .bold)
    )
    nonisolated(unsafe) private static let h3ParagraphStyle = headingParagraphStyle(
        for: Theme.editorNSFont(ofSize: 18, weight: .semibold)
    )

    func render(_ text: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let bodyFont = Theme.editorNSFont(ofSize: 16)
        let defaultAttrs: [NSAttributedString.Key: Any] = [
            .font: bodyFont, .foregroundColor: NSColor.textColor,
            .paragraphStyle: Self.bodyParagraphStyle
        ]

        let lines = text.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            var attrs = defaultAttrs

            // Style headings — hide # prefix visually
            var headingPrefixLen = 0
            if line.hasPrefix("# ") {
                attrs[.font] = Theme.editorNSFont(ofSize: 28, weight: .bold)
                attrs[.paragraphStyle] = Self.h1ParagraphStyle
                headingPrefixLen = 2
            } else if line.hasPrefix("## ") {
                attrs[.font] = Theme.editorNSFont(ofSize: 22, weight: .bold)
                attrs[.paragraphStyle] = Self.h2ParagraphStyle
                headingPrefixLen = 3
            } else if line.hasPrefix("### ") {
                attrs[.font] = Theme.editorNSFont(ofSize: 18, weight: .semibold)
                attrs[.paragraphStyle] = Self.h3ParagraphStyle
                headingPrefixLen = 4
            }

            let lineStr = NSMutableAttributedString(string: line, attributes: attrs)
            if headingPrefixLen > 0 {
                let prefixRange = NSRange(location: 0, length: headingPrefixLen)
                if hideSyntax {
                    lineStr.addAttributes([
                        .font: NSFont.systemFont(ofSize: 0.01),
                        .foregroundColor: NSColor.clear
                    ], range: prefixRange)
                } else {
                    lineStr.addAttribute(
                        .foregroundColor,
                        value: NSColor.tertiaryLabelColor,
                        range: prefixRange
                    )
                }
            }
            // Table separator rows: hide entirely
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            let lineRange = NSRange(location: 0, length: lineStr.length)
            let isSeparator = trimmedLine.hasPrefix("|")
                && Self.tableSeparatorPattern.firstMatch(
                    in: trimmedLine, range: NSRange(location: 0, length: trimmedLine.utf16.count)
                ) != nil
            if isSeparator {
                lineStr.addAttributes([
                    .font: NSFont.systemFont(ofSize: 0.01),
                    .foregroundColor: NSColor.clear
                ], range: lineRange)
            } else if trimmedLine.hasPrefix("|") && trimmedLine.hasSuffix("|") {
                // Table data rows: monospace font, dim pipes
                let monoFont = NSFont.monospacedSystemFont(
                    ofSize: 14, weight: .regular
                )
                lineStr.addAttribute(.font, value: monoFont, range: lineRange)
                let pipeRegex = try? NSRegularExpression(pattern: "\\|")
                pipeRegex?.enumerateMatches(
                    in: lineStr.string, range: lineRange
                ) { match, _, _ in
                    if let matchRange = match?.range {
                        lineStr.addAttribute(
                            .foregroundColor,
                            value: NSColor.tertiaryLabelColor,
                            range: matchRange
                        )
                    }
                }
            }
            applyListFormatting(lineStr)
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

    /// Attribute storing original markdown bullet marker (`-` or `*`).
    static let listMarkerKey = NSAttributedString.Key(
        "synth.listMarker"
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
        let fullRange = NSRange(
            location: 0, length: attributedText.string.utf16.count
        )

        for imageMatch in MarkdownFormat.imagePattern.matches(
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

    private func applyListFormatting(_ str: NSMutableAttributedString) {
        // Markdown bullets: "- item" or "* item" (with optional indentation).
        let fullRange = NSRange(
            location: 0, length: str.string.utf16.count
        )
        guard let match = MarkdownFormat.listPattern.firstMatch(
            in: str.string,
            range: fullRange
        ) else { return }

        let markerRange = match.range(at: 2)
        guard markerRange.location != NSNotFound,
              markerRange.length == 1,
              markerRange.location < str.length,
              let markerSwiftRange = Range(
                  markerRange, in: str.string
              )
        else { return }

        let marker = String(str.string[markerSwiftRange])
        let markerAttributes = str.attributes(
            at: markerRange.location,
            effectiveRange: nil
        )

        str.replaceCharacters(in: markerRange, with: "•")
        var bulletAttributes = markerAttributes
        bulletAttributes[MarkdownFormat.listMarkerKey] = marker
        str.setAttributes(
            bulletAttributes,
            range: NSRange(
                location: markerRange.location,
                length: 1
            )
        )
    }

    // swiftlint:disable:next function_body_length
    private func applyInlineFormatting(_ str: NSMutableAttributedString, baseFont: NSFont) {
        let hiddenInlineAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 0.01),
            .foregroundColor: NSColor.clear
        ]
        let dimInlineAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.tertiaryLabelColor
        ]
        let mediumFont = Theme.editorNSFont(ofSize: baseFont.pointSize, weight: .medium)
        let boldFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
        let italicFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)

        func hideInlineSyntax(range syntaxRange: NSRange) {
            guard syntaxRange.location >= 0,
                  syntaxRange.length > 0,
                  syntaxRange.location + syntaxRange.length <= str.length
            else { return }
            str.addAttributes(
                hideSyntax ? hiddenInlineAttrs : dimInlineAttrs,
                range: syntaxRange
            )
        }

        // MARK: Wiki links [[Note Title]]
        // Must run BEFORE bold/italic so link content isn't further reformatted
        let wikiRange = NSRange(location: 0, length: str.string.utf16.count)
        for match in MarkdownFormat.wikiPattern.matches(in: str.string, range: wikiRange).reversed() {
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
            var bracketAttrs: [NSAttributedString.Key: Any] = hideSyntax
                ? [.font: NSFont.systemFont(ofSize: 0.01), .foregroundColor: NSColor.clear]
                : [.foregroundColor: NSColor.tertiaryLabelColor]
            bracketAttrs[.link] = linkURL
            let openRange = NSRange(location: fullNSRange.location, length: 2)
            let closeRange = NSRange(
                location: fullNSRange.location + fullNSRange.length - 2,
                length: 2
            )
            str.addAttributes(bracketAttrs, range: openRange)
            str.addAttributes(bracketAttrs, range: closeRange)
        }

        // MARK: @Date mentions (@2026-02-07) — styled as daily note links
        let dateRange = NSRange(
            location: 0, length: str.string.utf16.count
        )
        for match in MarkdownFormat.datePattern.matches(
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
                .font: mediumFont,
                .foregroundColor: NSColor.controlAccentColor,
                .link: linkURL,
                .cursor: NSCursor.pointingHand
            ]
            str.addAttributes(linkAttrs, range: innerNSRange)

            // Hide the @ prefix
            var atPrefixAttrs: [NSAttributedString.Key: Any] = hideSyntax
                ? [.font: NSFont.systemFont(ofSize: 0.01), .foregroundColor: NSColor.clear]
                : [.foregroundColor: NSColor.tertiaryLabelColor]
            atPrefixAttrs[.link] = linkURL
            str.addAttributes(
                atPrefixAttrs,
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

        // MARK: Bold **text** — style inner text, hide markers
        let boldRange = NSRange(location: 0, length: str.string.utf16.count)
        for match in MarkdownFormat.boldPattern.matches(in: str.string, range: boldRange) {
            let innerRange = match.range(at: 1)
            str.addAttribute(.font, value: boldFont, range: innerRange)

            let fullRange = match.range
            let openRange = NSRange(location: fullRange.location, length: 2)
            let closeRange = NSRange(
                location: fullRange.location + fullRange.length - 2,
                length: 2
            )
            hideInlineSyntax(range: openRange)
            hideInlineSyntax(range: closeRange)
        }

        // MARK: Italic *text* — style inner text, hide markers
        let italicRange = NSRange(location: 0, length: str.string.utf16.count)
        for match in MarkdownFormat.italicPattern.matches(in: str.string, range: italicRange) {
            let innerRange = match.range(at: 1)
            str.addAttribute(.font, value: italicFont, range: innerRange)

            let fullRange = match.range
            let openRange = NSRange(location: fullRange.location, length: 1)
            let closeRange = NSRange(
                location: fullRange.location + fullRange.length - 1,
                length: 1
            )
            hideInlineSyntax(range: openRange)
            hideInlineSyntax(range: closeRange)
        }

        // MARK: Italic _text_ — style inner text, hide markers
        let underscoreItalicRange = NSRange(
            location: 0, length: str.string.utf16.count
        )
        for match in MarkdownFormat.underscoreItalicPattern.matches(
            in: str.string,
            range: underscoreItalicRange
        ) {
            let innerRange = match.range(at: 1)
            str.addAttribute(.font, value: italicFont, range: innerRange)

            let fullRange = match.range
            let openRange = NSRange(location: fullRange.location, length: 1)
            let closeRange = NSRange(
                location: fullRange.location + fullRange.length - 1,
                length: 1
            )
            hideInlineSyntax(range: openRange)
            hideInlineSyntax(range: closeRange)
        }

        // MARK: Underline __text__ — style inner text, hide markers
        let underlineRange = NSRange(location: 0, length: str.string.utf16.count)
        for match in MarkdownFormat.underlinePattern.matches(in: str.string, range: underlineRange) {
            let innerRange = match.range(at: 1)
            str.addAttribute(
                .underlineStyle,
                value: NSUnderlineStyle.single.rawValue,
                range: innerRange
            )

            let fullRange = match.range
            let openRange = NSRange(location: fullRange.location, length: 2)
            let closeRange = NSRange(
                location: fullRange.location + fullRange.length - 2,
                length: 2
            )
            hideInlineSyntax(range: openRange)
            hideInlineSyntax(range: closeRange)
        }

        // MARK: Inline code `text` — style inner text, keep backticks
        let codeRange = NSRange(location: 0, length: str.string.utf16.count)
        for match in MarkdownFormat.codePattern.matches(in: str.string, range: codeRange) {
            let innerRange = match.range(at: 1)
            str.addAttributes([
                .font: Theme.terminalNSFont(ofSize: 14),
                .foregroundColor: NSColor.systemPink,
                .backgroundColor: NSColor.quaternaryLabelColor
            ], range: innerRange)
            let fullRange = match.range
            hideInlineSyntax(range: NSRange(location: fullRange.location, length: 1))
            hideInlineSyntax(range: NSRange(
                location: fullRange.location + fullRange.length - 1, length: 1
            ))
        }
    }
}
