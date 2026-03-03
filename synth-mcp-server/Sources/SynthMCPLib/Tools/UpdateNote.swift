import Foundation

enum UpdateNote {
    static func definition(workspace: String) -> ToolDefinition {
        ToolDefinition(
            name: "update_note",
            description: "Append or prepend content to an existing file without rewriting the entire file.",
            inputSchema: jsonSchema(
                properties: [
                    "path": propertySchema(type: "string", description: "Relative path from workspace root"),
                    "content": propertySchema(type: "string", description: "Content to add"),
                    "position": enumSchema(
                        description: "Where to add the content",
                        values: ["append", "prepend"]
                    )
                ],
                required: ["path", "content", "position"]
            ),
            handler: { args in handle(args, workspace: workspace) }
        )
    }

    private static func handle(_ args: [String: AnyCodableValue], workspace: String) -> AnyCodableValue {
        guard let path = args["path"]?.stringValue else {
            return toolError("Missing required parameter: path")
        }
        guard let newContent = args["content"]?.stringValue else {
            return toolError("Missing required parameter: content")
        }
        guard let position = args["position"]?.stringValue else {
            return toolError("Missing required parameter: position")
        }

        guard let fullPath = resolvePath(path, workspace: workspace) else {
            return toolError("Path traversal not allowed: \(path)")
        }

        guard FileManager.default.fileExists(atPath: fullPath) else {
            return toolError("File not found: \(path)")
        }

        guard let existing = try? String(contentsOfFile: fullPath, encoding: .utf8) else {
            return toolError("Could not read file: \(path)")
        }

        let result: String
        switch position {
        case "append":
            result = existing + (existing.hasSuffix("\n") ? "" : "\n") + newContent
        case "prepend":
            result = newContent + (newContent.hasSuffix("\n") ? "" : "\n") + existing
        default:
            return toolError("Invalid position: \(position). Use 'append' or 'prepend'.")
        }

        do {
            try result.write(toFile: fullPath, atomically: true, encoding: .utf8)
            return toolResult("Updated \(path) (\(position)ed \(newContent.count) characters)")
        } catch {
            return toolError("Could not write file: \(error.localizedDescription)")
        }
    }
}
