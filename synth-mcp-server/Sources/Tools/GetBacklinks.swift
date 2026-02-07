import Foundation

enum GetBacklinks {
    static func definition(workspace: String) -> ToolDefinition {
        ToolDefinition(
            name: "get_backlinks",
            description: "Find all files in the workspace that link to a given file using [[wiki link]] syntax.",
            inputSchema: jsonSchema(
                properties: [
                    "path": propertySchema(
                        type: "string",
                        description: "Relative path of the target file (the file being linked TO)"
                    ),
                    "extensions": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string("File extensions to search (default: [\"md\", \"txt\"])")
                    ])
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

        let extensions: Set<String> = {
            if let arr = args["extensions"]?.arrayValue {
                let exts = arr.compactMap { $0.stringValue?.lowercased() }
                return exts.isEmpty ? Set(["md", "txt"]) : Set(exts)
            }
            return Set(["md", "txt"])
        }()

        // Build search patterns for the target file
        let targetName = (path as NSString).lastPathComponent
        let nameWithoutExt = (targetName as NSString).deletingPathExtension

        // Match [[filename]] or [[filename.ext]] or [[path/to/filename]]
        let patterns = [
            "\\[\\[\(NSRegularExpression.escapedPattern(for: nameWithoutExt))\\]\\]",
            "\\[\\[\(NSRegularExpression.escapedPattern(for: targetName))\\]\\]",
            "\\[\\[\(NSRegularExpression.escapedPattern(for: path))\\]\\]"
        ]

        let regexes = patterns.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }

        let fileManager = FileManager.default
        let workspaceURL = URL(fileURLWithPath: workspace)

        guard let enumerator = fileManager.enumerator(
            at: workspaceURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return toolError("Could not enumerate workspace")
        }

        struct Backlink {
            let file: String
            let lineNumber: Int
            let line: String
        }

        var backlinks: [Backlink] = []

        while let url = enumerator.nextObject() as? URL {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDirectory { continue }

            guard extensions.contains(url.pathExtension.lowercased()) else { continue }

            // Skip the target file itself
            let relativePath = url.path.replacingOccurrences(of: workspace + "/", with: "")
            if relativePath == path { continue }

            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }

            let lines = content.components(separatedBy: "\n")
            for (index, line) in lines.enumerated() {
                let nsRange = NSRange(line.startIndex..., in: line)
                for regex in regexes {
                    if regex.firstMatch(in: line, range: nsRange) != nil {
                        backlinks.append(Backlink(
                            file: relativePath,
                            lineNumber: index + 1,
                            line: line.trimmingCharacters(in: .whitespaces)
                        ))
                        break // Don't double-count same line
                    }
                }
            }
        }

        if backlinks.isEmpty {
            return toolResult("No backlinks found for \(path)")
        }

        var result = "## Backlinks to \(path)\n\n"
        result += "Found \(backlinks.count) backlink(s) in \(Set(backlinks.map(\.file)).count) file(s)\n\n"

        var currentFile = ""
        for link in backlinks {
            if link.file != currentFile {
                currentFile = link.file
                result += "### \(currentFile)\n"
            }
            result += "- Line \(link.lineNumber): \(link.line)\n"
        }

        return toolResult(result)
    }
}
