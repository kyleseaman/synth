import Foundation

enum GlobalSearch {
    static func definition(workspace: String) -> ToolDefinition {
        ToolDefinition(
            name: "global_search",
            description: "Search across all files in the workspace using regex. Returns matching lines with surrounding context.",
            inputSchema: jsonSchema(
                properties: [
                    "query": propertySchema(type: "string", description: "Regex pattern to search for"),
                    "extensions": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string("File extensions to search (default: [\"md\", \"txt\"])")
                    ]),
                    "context_lines": propertySchemaWithDefault(
                        type: "integer",
                        description: "Lines of context around each match",
                        defaultValue: .int(2)
                    ),
                    "max_results": propertySchemaWithDefault(
                        type: "integer",
                        description: "Maximum number of matches to return",
                        defaultValue: .int(20)
                    ),
                    "case_sensitive": propertySchemaWithDefault(
                        type: "boolean",
                        description: "Case-sensitive search",
                        defaultValue: .bool(false)
                    )
                ],
                required: ["query"]
            ),
            handler: { args in handle(args, workspace: workspace) }
        )
    }

    private static func handle(_ args: [String: AnyCodableValue], workspace: String) -> AnyCodableValue {
        guard let query = args["query"]?.stringValue else {
            return toolError("Missing required parameter: query")
        }

        let contextLines = args["context_lines"]?.intValue ?? 2
        let maxResults = args["max_results"]?.intValue ?? 20
        let caseSensitive = args["case_sensitive"]?.boolValue ?? false

        let extensions: Set<String> = {
            if let arr = args["extensions"]?.arrayValue {
                let exts = arr.compactMap { $0.stringValue?.lowercased() }
                return exts.isEmpty ? Set(["md", "txt"]) : Set(exts)
            }
            return Set(["md", "txt"])
        }()

        let regexOptions: NSRegularExpression.Options = caseSensitive ? [] : [.caseInsensitive]
        guard let regex = try? NSRegularExpression(pattern: query, options: regexOptions) else {
            return toolError("Invalid regex pattern: \(query)")
        }

        let fileManager = FileManager.default
        let workspaceURL = URL(fileURLWithPath: workspace)

        guard let enumerator = fileManager.enumerator(
            at: workspaceURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return toolError("Could not enumerate workspace")
        }

        struct Match {
            let file: String
            let lineNumber: Int
            let context: String
        }

        var matches: [Match] = []

        while let url = enumerator.nextObject() as? URL {
            if matches.count >= maxResults { break }

            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDirectory { continue }

            guard extensions.contains(url.pathExtension.lowercased()) else { continue }

            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }

            let lines = content.components(separatedBy: "\n")
            let relativePath = url.path.replacingOccurrences(of: workspace + "/", with: "")

            for (index, line) in lines.enumerated() {
                if matches.count >= maxResults { break }

                let range = NSRange(line.startIndex..., in: line)
                guard regex.firstMatch(in: line, range: range) != nil else { continue }

                let start = max(0, index - contextLines)
                let end = min(lines.count - 1, index + contextLines)
                var contextBlock = ""

                for contextIdx in start...end {
                    let prefix = contextIdx == index ? "→ " : "  "
                    contextBlock += "\(prefix)\(contextIdx + 1): \(lines[contextIdx])\n"
                }

                matches.append(Match(
                    file: relativePath,
                    lineNumber: index + 1,
                    context: contextBlock
                ))
            }
        }

        if matches.isEmpty {
            return toolResult("No matches found for: \(query)")
        }

        var result = "## Search Results for `/\(query)/`\n\n"
        result += "Found \(matches.count) match(es)\n\n"

        var currentFile = ""
        for match in matches {
            if match.file != currentFile {
                currentFile = match.file
                result += "### \(currentFile)\n\n"
            }
            result += "**Line \(match.lineNumber):**\n```\n\(match.context)```\n\n"
        }

        return toolResult(result)
    }
}
