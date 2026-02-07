import Foundation

enum ManageTags {
    static func definition(workspace: String) -> ToolDefinition {
        ToolDefinition(
            name: "manage_tags",
            description: "List, add, or remove tags in a file. Tags can be in YAML frontmatter (tags: array) or inline (#tag).",
            inputSchema: jsonSchema(
                properties: [
                    "path": propertySchema(type: "string", description: "Relative path from workspace root"),
                    "action": enumSchema(
                        description: "Action to perform",
                        values: ["list", "add", "remove"]
                    ),
                    "tag": propertySchema(
                        type: "string",
                        description: "Tag name without # (required for add/remove)"
                    )
                ],
                required: ["path", "action"]
            ),
            handler: { args in handle(args, workspace: workspace) }
        )
    }

    private static func handle(_ args: [String: AnyCodableValue], workspace: String) -> AnyCodableValue {
        guard let path = args["path"]?.stringValue else {
            return toolError("Missing required parameter: path")
        }
        guard let action = args["action"]?.stringValue else {
            return toolError("Missing required parameter: action")
        }
        guard let fullPath = resolvePath(path, workspace: workspace) else {
            return toolError("Path traversal not allowed: \(path)")
        }

        guard FileManager.default.fileExists(atPath: fullPath) else {
            return toolError("File not found: \(path)")
        }

        guard let content = try? String(contentsOfFile: fullPath, encoding: .utf8) else {
            return toolError("Could not read file: \(path)")
        }

        switch action {
        case "list":
            return listTags(content: content, path: path)
        case "add":
            guard let tag = args["tag"]?.stringValue else {
                return toolError("Missing required parameter: tag (for add action)")
            }
            return addTag(content: content, tag: tag, fullPath: fullPath, path: path)
        case "remove":
            guard let tag = args["tag"]?.stringValue else {
                return toolError("Missing required parameter: tag (for remove action)")
            }
            return removeTag(content: content, tag: tag, fullPath: fullPath, path: path)
        default:
            return toolError("Unknown action: \(action). Use list, add, or remove.")
        }
    }

    private static func listTags(content: String, path: String) -> AnyCodableValue {
        let tags = extractAllTags(from: content)
        if tags.isEmpty {
            return toolResult("No tags found in \(path)")
        }
        var result = "## Tags in \(path)\n\n"
        for tag in tags.sorted() {
            result += "- #\(tag)\n"
        }
        return toolResult(result)
    }

    private static func addTag(content: String, tag: String, fullPath: String, path: String) -> AnyCodableValue {
        let cleanTag = tag.hasPrefix("#") ? String(tag.dropFirst()) : tag
        let existingTags = extractAllTags(from: content)

        if existingTags.contains(cleanTag) {
            return toolResult("Tag #\(cleanTag) already exists in \(path)")
        }

        var newContent = content

        // Check if file has frontmatter
        if content.hasPrefix("---\n") {
            if let endRange = content.range(of: "\n---\n", range: content.index(content.startIndex, offsetBy: 4)..<content.endIndex) {
                let frontmatter = String(content[content.index(content.startIndex, offsetBy: 4)..<endRange.lowerBound])

                // Check if tags: line exists in frontmatter
                if let tagsLineRange = frontmatter.range(of: "tags:") {
                    // Append to existing tags array
                    let afterTags = frontmatter[tagsLineRange.upperBound...]
                    if afterTags.hasPrefix(" [") || afterTags.hasPrefix("\n") {
                        // Add as new line item
                        let insertPoint = content.index(endRange.lowerBound, offsetBy: 0)
                        newContent = String(content[..<insertPoint]) + "\n  - \(cleanTag)" + String(content[insertPoint...])
                    }
                } else {
                    // Add tags: section to frontmatter
                    let insertPoint = endRange.lowerBound
                    newContent = String(content[..<insertPoint]) + "\ntags:\n  - \(cleanTag)" + String(content[insertPoint...])
                }
            }
        } else {
            // No frontmatter — add frontmatter with tags
            newContent = "---\ntags:\n  - \(cleanTag)\n---\n\(content)"
        }

        do {
            try newContent.write(toFile: fullPath, atomically: true, encoding: .utf8)
            return toolResult("Added tag #\(cleanTag) to \(path)")
        } catch {
            return toolError("Could not write file: \(error.localizedDescription)")
        }
    }

    private static func removeTag(content: String, tag: String, fullPath: String, path: String) -> AnyCodableValue {
        let cleanTag = tag.hasPrefix("#") ? String(tag.dropFirst()) : tag
        var newContent = content
        var removed = false

        // Remove from frontmatter tags array
        let frontmatterPattern = "\\s*-\\s*\(NSRegularExpression.escapedPattern(for: cleanTag))\\s*\\n"
        if let regex = try? NSRegularExpression(pattern: frontmatterPattern) {
            let range = NSRange(newContent.startIndex..., in: newContent)
            let modified = regex.stringByReplacingMatches(in: newContent, range: range, withTemplate: "")
            if modified != newContent {
                newContent = modified
                removed = true
            }
        }

        // Remove inline #tags
        let inlinePattern = "#\(NSRegularExpression.escapedPattern(for: cleanTag))\\b"
        if let regex = try? NSRegularExpression(pattern: inlinePattern) {
            let range = NSRange(newContent.startIndex..., in: newContent)
            let modified = regex.stringByReplacingMatches(in: newContent, range: range, withTemplate: "")
            if modified != newContent {
                newContent = modified
                removed = true
            }
        }

        guard removed else {
            return toolResult("Tag #\(cleanTag) not found in \(path)")
        }

        do {
            try newContent.write(toFile: fullPath, atomically: true, encoding: .utf8)
            return toolResult("Removed tag #\(cleanTag) from \(path)")
        } catch {
            return toolError("Could not write file: \(error.localizedDescription)")
        }
    }

    static func extractAllTags(from content: String) -> Set<String> {
        var tags = Set<String>()

        // Extract from frontmatter tags: array
        if content.hasPrefix("---\n"),
           let endRange = content.range(of: "\n---\n", range: content.index(content.startIndex, offsetBy: 4)..<content.endIndex) {
            let frontmatter = String(content[content.index(content.startIndex, offsetBy: 4)..<endRange.lowerBound])
            if let regex = try? NSRegularExpression(pattern: "^\\s*-\\s*(.+)$", options: .anchorsMatchLines) {
                var inTagsSection = false
                for line in frontmatter.components(separatedBy: "\n") {
                    if line.hasPrefix("tags:") {
                        inTagsSection = true
                        continue
                    }
                    if inTagsSection {
                        if line.hasPrefix("  ") || line.hasPrefix("\t") {
                            let range = NSRange(line.startIndex..., in: line)
                            if let match = regex.firstMatch(in: line, range: range),
                               let tagRange = Range(match.range(at: 1), in: line) {
                                tags.insert(String(line[tagRange]).trimmingCharacters(in: .whitespaces))
                            }
                        } else {
                            inTagsSection = false
                        }
                    }
                }
            }
        }

        // Extract inline #tags
        if let regex = try? NSRegularExpression(pattern: "(?:^|\\s)#([\\w-]+)", options: []) {
            let range = NSRange(content.startIndex..., in: content)
            let results = regex.matches(in: content, range: range)
            for match in results {
                if let tagRange = Range(match.range(at: 1), in: content) {
                    tags.insert(String(content[tagRange]))
                }
            }
        }

        return tags
    }
}
