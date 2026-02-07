import Foundation

/// Lightweight YAML frontmatter parser — handles the subset of YAML used
/// in markdown frontmatter without requiring the full Yams library.
///
/// Supports:
/// - Key-value pairs (`key: value`)
/// - Block sequences (`- item`)
/// - Inline arrays (`key: [a, b, c]`)
/// - Nested indented blocks
/// - Quoted strings (single and double)
enum FrontmatterParser {

    /// Parsed frontmatter result.
    struct Frontmatter {
        /// Raw frontmatter string (between the --- delimiters, not including them).
        let raw: String
        /// Parsed key-value pairs. Values are either a single String or [String].
        let fields: [String: FrontmatterValue]
        /// The body content after the closing ---.
        let body: String
        /// Full original content for reconstruction.
        let originalContent: String
    }

    enum FrontmatterValue: Equatable {
        case scalar(String)
        case list([String])

        var stringValue: String? {
            if case .scalar(let val) = self { return val }
            return nil
        }

        var listValue: [String]? {
            if case .list(let val) = self { return val }
            return nil
        }
    }

    // MARK: - Parsing

    /// Parse markdown content with optional YAML frontmatter.
    /// Returns nil if content has no valid frontmatter delimiters.
    static func parse(_ content: String) -> Frontmatter? {
        guard content.hasPrefix("---\n") || content.hasPrefix("---\r\n") else {
            return nil
        }

        // Find closing ---
        let searchStart: String.Index
        if content.hasPrefix("---\r\n") {
            searchStart = content.index(content.startIndex, offsetBy: 5)
        } else {
            searchStart = content.index(content.startIndex, offsetBy: 4)
        }

        // Look for \n---\n or \n---\r\n or \n--- at end of file
        guard let closingRange = findClosingDelimiter(content, from: searchStart) else {
            return nil
        }

        let rawFrontmatter = String(content[searchStart..<closingRange.lowerBound])
        let body = String(content[closingRange.upperBound...])
        let fields = parseYamlBlock(rawFrontmatter)

        return Frontmatter(
            raw: rawFrontmatter,
            fields: fields,
            body: body,
            originalContent: content
        )
    }

    /// Reconstruct content from modified frontmatter fields and body.
    static func reconstruct(fields: [String: FrontmatterValue], body: String, fieldOrder: [String]? = nil) -> String {
        var yaml = ""
        let keys = fieldOrder ?? fields.keys.sorted()
        for key in keys {
            guard let value = fields[key] else { continue }
            switch value {
            case .scalar(let str):
                yaml += "\(key): \(str)\n"
            case .list(let items):
                if items.isEmpty {
                    yaml += "\(key): []\n"
                } else {
                    yaml += "\(key):\n"
                    for item in items {
                        yaml += "  - \(item)\n"
                    }
                }
            }
        }
        return "---\n\(yaml)---\n\(body)"
    }

    // MARK: - Tags Helpers

    /// Extract the tags list from frontmatter, returns empty array if no tags field.
    static func tags(from frontmatter: Frontmatter) -> [String] {
        switch frontmatter.fields["tags"] {
        case .list(let items):
            return items
        case .scalar(let val):
            // Handle `tags: single-tag`
            let trimmed = val.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty || trimmed == "[]" ? [] : [trimmed]
        case nil:
            return []
        }
    }

    /// Return new content with a tag added to frontmatter.
    /// Creates frontmatter if none exists.
    static func addTag(_ tag: String, to content: String) -> String {
        if let frontmatter = parse(content) {
            var currentTags = tags(from: frontmatter)
            guard !currentTags.contains(tag) else { return content }
            currentTags.append(tag)

            var fields = frontmatter.fields
            fields["tags"] = .list(currentTags)

            // Preserve original field order
            let order = fieldOrder(from: frontmatter.raw)
            return reconstruct(
                fields: fields,
                body: frontmatter.body,
                fieldOrder: order.contains("tags") ? order : order + ["tags"]
            )
        } else {
            // No frontmatter — prepend one
            return "---\ntags:\n  - \(tag)\n---\n\(content)"
        }
    }

    /// Return new content with a tag removed from frontmatter.
    static func removeTag(_ tag: String, fromFrontmatter content: String) -> (String, Bool) {
        guard let frontmatter = parse(content) else { return (content, false) }

        var currentTags = tags(from: frontmatter)
        guard currentTags.contains(tag) else { return (content, false) }
        currentTags.removeAll { $0 == tag }

        var fields = frontmatter.fields
        fields["tags"] = .list(currentTags)

        let order = fieldOrder(from: frontmatter.raw)
        let result = reconstruct(
            fields: fields,
            body: frontmatter.body,
            fieldOrder: order
        )
        return (result, true)
    }

    // MARK: - Internal

    private static func findClosingDelimiter(_ content: String, from start: String.Index) -> Range<String.Index>? {
        // Try \n---\n
        if let range = content.range(of: "\n---\n", range: start..<content.endIndex) {
            return range
        }
        // Try \n---\r\n
        if let range = content.range(of: "\n---\r\n", range: start..<content.endIndex) {
            return range
        }
        // Try \n--- at end of file
        if content[start...].hasSuffix("\n---") {
            let lower = content.index(content.endIndex, offsetBy: -4)
            return lower..<content.endIndex
        }
        return nil
    }

    private static func parseYamlBlock(_ yaml: String) -> [String: FrontmatterValue] {
        var result: [String: FrontmatterValue] = [:]
        let lines = yaml.components(separatedBy: "\n")

        var currentKey: String?
        var currentList: [String]?

        for line in lines {
            // Skip empty lines
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }

            let indent = line.prefix(while: { $0 == " " || $0 == "\t" }).count

            // Indented line — part of a list under currentKey
            if indent > 0, currentKey != nil {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("- ") {
                    let item = unquote(String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces))
                    if currentList == nil { currentList = [] }
                    currentList?.append(item)
                } else if trimmed == "-" {
                    // Empty list item
                    if currentList == nil { currentList = [] }
                    currentList?.append("")
                }
                continue
            }

            // Flush previous key's list
            if let key = currentKey, let list = currentList {
                result[key] = .list(list)
                currentKey = nil
                currentList = nil
            }

            // Top-level key: value
            let pair = line.split(separator: ":", maxSplits: 1)
            guard pair.count >= 1 else { continue }

            let key = pair[0].trimmingCharacters(in: .whitespaces)
            let rawValue = pair.count > 1
                ? pair[1].trimmingCharacters(in: .whitespaces)
                : ""

            if rawValue.isEmpty {
                // Might be followed by a list block
                currentKey = key
                currentList = nil
            } else if rawValue.hasPrefix("[") && rawValue.hasSuffix("]") {
                // Inline array: [a, b, c]
                let inner = rawValue.dropFirst().dropLast()
                if inner.trimmingCharacters(in: .whitespaces).isEmpty {
                    result[key] = .list([])
                } else {
                    let items = inner.split(separator: ",").map {
                        unquote($0.trimmingCharacters(in: .whitespaces))
                    }
                    result[key] = .list(items)
                }
            } else {
                result[key] = .scalar(unquote(rawValue))
            }
        }

        // Flush last key
        if let key = currentKey, let list = currentList {
            result[key] = .list(list)
        } else if let emptyKey = currentKey {
            // Key with no value and no list items = empty list
            result[emptyKey] = .list([])
        }

        return result
    }

    /// Remove surrounding quotes from a YAML string value.
    private static func unquote(_ value: String) -> String {
        if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
           (value.hasPrefix("'") && value.hasSuffix("'")) {
            return String(value.dropFirst().dropLast())
        }
        return value
    }

    /// Extract field order from raw frontmatter to preserve it during reconstruction.
    private static func fieldOrder(from raw: String) -> [String] {
        var order: [String] = []
        for line in raw.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            // Only top-level keys (no leading whitespace)
            if !line.hasPrefix(" ") && !line.hasPrefix("\t") && line.contains(":") {
                let key = line.split(separator: ":", maxSplits: 1)[0]
                    .trimmingCharacters(in: .whitespaces)
                if !order.contains(key) {
                    order.append(key)
                }
            }
        }
        return order
    }
}
