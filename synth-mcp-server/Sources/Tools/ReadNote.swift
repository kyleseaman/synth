import Foundation

enum ReadNote {
    static func definition(workspace: String) -> ToolDefinition {
        ToolDefinition(
            name: "read_note",
            description: "Read the contents of a file in the workspace. Optionally include file statistics like word count, line count, and modification date.",
            inputSchema: jsonSchema(
                properties: [
                    "path": propertySchema(type: "string", description: "Relative path from workspace root"),
                    "include_stats": propertySchemaWithDefault(
                        type: "boolean",
                        description: "Include file statistics (word count, line count, dates)",
                        defaultValue: .bool(false)
                    )
                ],
                required: ["path"]
            ),
            handler: { args in handle(args, workspace: workspace) }
        )
    }

    private static func handle(_ args: [String: AnyCodableValue], workspace: String) -> AnyCodableValue {
        guard let path = args["path"]?.stringValue else {
            return toolError("Missing required parameter: path")
        }

        guard let fullPath = resolvePath(path, workspace: workspace) else {
            return toolError("Path traversal not allowed: \(path)")
        }

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fullPath) else {
            return toolError("File not found: \(path)")
        }

        guard let content = try? String(contentsOfFile: fullPath, encoding: .utf8) else {
            return toolError("Could not read file: \(path)")
        }

        let includeStats = args["include_stats"]?.boolValue ?? false

        if includeStats {
            var result = "# \(path)\n\n"
            result += content
            result += "\n\n---\n## File Stats\n"

            let lines = content.components(separatedBy: "\n")
            let words = content.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
            let characters = content.count

            result += "- Lines: \(lines.count)\n"
            result += "- Words: \(words)\n"
            result += "- Characters: \(characters)\n"

            if let attrs = try? fileManager.attributesOfItem(atPath: fullPath) {
                if let modified = attrs[.modificationDate] as? Date {
                    let formatter = ISO8601DateFormatter()
                    result += "- Modified: \(formatter.string(from: modified))\n"
                }
                if let created = attrs[.creationDate] as? Date {
                    let formatter = ISO8601DateFormatter()
                    result += "- Created: \(formatter.string(from: created))\n"
                }
                if let size = attrs[.size] as? UInt64 {
                    result += "- Size: \(size) bytes\n"
                }
            }

            return toolResult(result)
        }

        return toolResult(content)
    }
}
