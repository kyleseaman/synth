import Foundation

enum GlobalSearch {
    static func definition(workspace: String) -> ToolDefinition {
        ToolDefinition(
            name: "global_search",
            description: "Search across all files in the"
                + " workspace using regex. Returns matching"
                + " lines with surrounding context.",
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

        let maxResults = args["max_results"]?.intValue ?? 20

        // Try QMD first for better search quality
        if let qmdResult = tryQmdSearch(query: query, maxResults: maxResults) {
            return qmdResult
        }

        // Fall back to regex-based search
        return regexSearch(args, query: query, workspace: workspace)
    }

    // MARK: - QMD Search

    private static var _qmdPath: String??
    private static var qmdPath: String? {
        if let cached = _qmdPath { return cached }
        let resolved = resolveQmdPath()
        if resolved != nil { _qmdPath = resolved }
        return resolved
    }

    private static func resolveQmdPath() -> String? {
        let candidates = [
            "/usr/local/bin/qmd",
            "/opt/homebrew/bin/qmd",
            "\(NSHomeDirectory())/.local/bin/qmd",
            "\(NSHomeDirectory())/.bun/bin/qmd",
            "\(NSHomeDirectory())/.npm-global/bin/qmd"
        ]
        if let found = candidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0)
        }) {
            return found
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = ["qmd"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty,
           FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    private static func tryQmdSearch(
        query: String,
        maxResults: Int
    ) -> AnyCodableValue? {
        guard let qmd = qmdPath else { return nil }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: qmd)
        proc.arguments = [
            "query", query, "--json",
            "-n", String(maxResults)
        ]
        let stdout = Pipe()
        proc.standardOutput = stdout
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
        } catch {
            return nil
        }
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        guard !data.isEmpty else { return nil }

        // Parse QMD JSON and format as tool result
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data)
        } catch {
            return nil
        }

        let entries: [[String: Any]]
        if let array = json as? [[String: Any]] {
            entries = array
        } else if let wrapper = json as? [String: Any],
                  let array = wrapper["results"] as? [[String: Any]] {
            entries = array
        } else {
            return nil
        }

        guard !entries.isEmpty else { return nil }

        var result = "## Search Results for \"\(query)\"\n\n"
        result += "Found \(entries.count) result(s) via QMD (hybrid search)\n\n"

        for entry in entries {
            let path = (entry["path"] as? String)
                ?? (entry["file"] as? String) ?? "unknown"
            let title = (entry["title"] as? String) ?? path
            let score = (entry["score"] as? Double) ?? 0
            let snippet = (entry["snippet"] as? String)
                ?? (entry["context"] as? String) ?? ""
            let context = entry["context"] as? String
            let scorePercent = Int(score * 100)
            result += "### \(path)\n"
            result += "**\(title)** (score: \(scorePercent)%)\n"
            if let context, !context.isEmpty {
                result += "Context: \(context)\n"
            }
            if !snippet.isEmpty {
                result += "```\n\(snippet)\n```\n"
            }
            result += "\n"
        }

        return toolResult(result)
    }

    // MARK: - Regex Fallback

    private static func regexSearch(
        _ args: [String: AnyCodableValue],
        query: String,
        workspace: String
    ) -> AnyCodableValue {
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

        guard query.count <= 500 else {
            return toolError("Regex pattern too long (max 500 characters)")
        }
        if hasNestedQuantifiers(query) {
            return toolError(
                "Regex pattern rejected: nested quantifiers"
                + " like (a+)+ can cause excessive backtracking"
            )
        }

        let regexOptions: NSRegularExpression.Options = caseSensitive
            ? [] : [.caseInsensitive]
        guard let regex = try? NSRegularExpression(
            pattern: query, options: regexOptions
        ) else {
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

            let isDir = (try? url.resourceValues(
                forKeys: [.isDirectoryKey]
            ))?.isDirectory ?? false
            if isDir { continue }

            guard extensions.contains(
                url.pathExtension.lowercased()
            ) else { continue }

            guard let content = try? String(
                contentsOf: url, encoding: .utf8
            ) else { continue }

            let lines = content.components(separatedBy: "\n")
            let relativePath = url.path.replacingOccurrences(
                of: workspace + "/", with: ""
            )

            for (index, line) in lines.enumerated() {
                if matches.count >= maxResults { break }
                guard line.count <= 10_000 else { continue }

                let range = NSRange(line.startIndex..., in: line)
                guard regex.firstMatch(
                    in: line, range: range
                ) != nil else { continue }

                let start = max(0, index - contextLines)
                let end = min(lines.count - 1, index + contextLines)
                var contextBlock = ""

                for contextIdx in start...end {
                    let prefix = contextIdx == index ? "→ " : "  "
                    contextBlock
                        += "\(prefix)\(contextIdx + 1): \(lines[contextIdx])\n"
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
            result += "**Line \(match.lineNumber):**\n"
            result += "```\n\(match.context)```\n\n"
        }

        return toolResult(result)
    }

    /// Detects nested quantifiers that can cause catastrophic
    /// backtracking (e.g. `(a+)+`, `(a*)*`, `(a+)*`).
    /// Walks the pattern tracking group nesting depth and
    /// whether a quantifier appears inside a quantified group.
    public static func hasNestedQuantifiers(
        _ pattern: String
    ) -> Bool {
        let quantifiers: Set<Character> = ["+", "*", "?"]
        var depth = 0
        var hasQuantifierAtDepth: [Int: Bool] = [:]
        var escaped = false
        var inCharClass = false

        for char in pattern {
            if escaped {
                escaped = false
                continue
            }
            if char == "\\" {
                escaped = true
                continue
            }
            if char == "[" { inCharClass = true; continue }
            if char == "]" { inCharClass = false; continue }
            if inCharClass { continue }

            if char == "(" {
                depth += 1
                hasQuantifierAtDepth[depth] = false
            } else if char == ")" {
                let hadQuantifier = hasQuantifierAtDepth[depth]
                    ?? false
                hasQuantifierAtDepth[depth] = nil
                depth = max(0, depth - 1)
                // If next char is a quantifier and the group
                // contained a quantifier, that's nested.
                if hadQuantifier {
                    hasQuantifierAtDepth[-1] = true
                }
            } else if quantifiers.contains(char) {
                if hasQuantifierAtDepth[-1] == true {
                    return true
                }
                if depth > 0 {
                    hasQuantifierAtDepth[depth] = true
                }
            } else {
                hasQuantifierAtDepth[-1] = nil
            }
        }
        return false
    }
}
