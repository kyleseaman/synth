import Foundation

enum ManageTags {
    static func definition(workspace: String) -> ToolDefinition {
        ToolDefinition(
            name: "manage_tags",
            description: "List, add, or remove tags in a file."
                + " Tags can be in YAML frontmatter"
                + " (tags: array) or inline (#tag).",
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

        let newContent = FrontmatterParser.addTag(cleanTag, to: content)

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

        // Remove from frontmatter using FrontmatterParser
        let (updatedContent, removedFromFrontmatter) = FrontmatterParser.removeTag(
            cleanTag, fromFrontmatter: newContent
        )
        if removedFromFrontmatter {
            newContent = updatedContent
            removed = true
        }

        // Remove inline #tags
        let escapedTag = NSRegularExpression.escapedPattern(for: cleanTag)
        if let regex = try? NSRegularExpression(pattern: "#\(escapedTag)\\b") {
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

        // Extract from frontmatter using FrontmatterParser
        if let frontmatter = FrontmatterParser.parse(content) {
            for tag in FrontmatterParser.tags(from: frontmatter) {
                tags.insert(tag)
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
