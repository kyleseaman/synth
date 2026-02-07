import Foundation

enum GetPeople {
    static func definition(workspace: String) -> ToolDefinition {
        ToolDefinition(
            name: "get_people",
            description: "Find @mentioned people across the workspace. List all people or find files mentioning a specific person.",
            inputSchema: jsonSchema(
                properties: [
                    "person": propertySchema(
                        type: "string",
                        description: "Name of person to search for (without @). If omitted, lists all mentioned people."
                    ),
                    "extensions": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string("File extensions to search (default: [\"md\", \"txt\"])")
                    ])
                ]
            ),
            handler: { args in handle(args, workspace: workspace) }
        )
    }

    private static func handle(_ args: [String: AnyCodableValue], workspace: String) -> AnyCodableValue {
        let extensions: Set<String> = {
            if let arr = args["extensions"]?.arrayValue {
                let exts = arr.compactMap { $0.stringValue?.lowercased() }
                return exts.isEmpty ? Set(["md", "txt"]) : Set(exts)
            }
            return Set(["md", "txt"])
        }()

        let fileManager = FileManager.default
        let workspaceURL = URL(fileURLWithPath: workspace)

        guard let enumerator = fileManager.enumerator(
            at: workspaceURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return toolError("Could not enumerate workspace")
        }

        // Match @Name patterns (supports multi-word names like @John Smith via @{John Smith})
        guard let mentionRegex = try? NSRegularExpression(
            pattern: "@\\{([^}]+)\\}|@([A-Z][a-zA-Z]+(?:\\s[A-Z][a-zA-Z]+)*)",
            options: []
        ) else {
            return toolError("Internal error: could not create mention regex")
        }

        struct Mention {
            let person: String
            let file: String
            let lineNumber: Int
            let line: String
        }

        var allMentions: [Mention] = []

        while let url = enumerator.nextObject() as? URL {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDirectory { continue }

            guard extensions.contains(url.pathExtension.lowercased()) else { continue }

            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }

            let relativePath = url.path.replacingOccurrences(of: workspace + "/", with: "")
            let lines = content.components(separatedBy: "\n")

            for (index, line) in lines.enumerated() {
                let nsRange = NSRange(line.startIndex..., in: line)
                let matches = mentionRegex.matches(in: line, range: nsRange)

                for match in matches {
                    var name: String?
                    // Check braced group first: @{Name}
                    if match.range(at: 1).location != NSNotFound,
                       let range = Range(match.range(at: 1), in: line) {
                        name = String(line[range])
                    }
                    // Then unbraced: @Name
                    else if match.range(at: 2).location != NSNotFound,
                            let range = Range(match.range(at: 2), in: line) {
                        name = String(line[range])
                    }

                    if let name = name {
                        allMentions.append(Mention(
                            person: name,
                            file: relativePath,
                            lineNumber: index + 1,
                            line: line.trimmingCharacters(in: .whitespaces)
                        ))
                    }
                }
            }
        }

        // If searching for a specific person
        if let targetPerson = args["person"]?.stringValue {
            let filtered = allMentions.filter {
                $0.person.lowercased() == targetPerson.lowercased()
            }

            if filtered.isEmpty {
                return toolResult("No mentions of @\(targetPerson) found")
            }

            var result = "## Mentions of @\(targetPerson)\n\n"
            result += "Found in \(Set(filtered.map(\.file)).count) file(s)\n\n"

            var currentFile = ""
            for mention in filtered {
                if mention.file != currentFile {
                    currentFile = mention.file
                    result += "### \(currentFile)\n"
                }
                result += "- Line \(mention.lineNumber): \(mention.line)\n"
            }
            return toolResult(result)
        }

        // List all people
        var peopleCounts: [String: Int] = [:]
        for mention in allMentions {
            peopleCounts[mention.person, default: 0] += 1
        }

        if peopleCounts.isEmpty {
            return toolResult("No @mentions found in the workspace")
        }

        var result = "## People in Workspace\n\n"
        let sorted = peopleCounts.sorted { $0.value > $1.value }
        for (person, count) in sorted {
            let files = Set(allMentions.filter { $0.person == person }.map(\.file)).count
            result += "- @\(person) (\(count) mention(s) in \(files) file(s))\n"
        }

        return toolResult(result)
    }
}
