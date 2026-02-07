import Foundation

enum ListNotes {
    static func definition(workspace: String) -> ToolDefinition {
        ToolDefinition(
            name: "list_notes",
            description: "List files and directories in the"
                + " workspace. Filter by extension, name"
                + " pattern, and recursion depth.",
            inputSchema: jsonSchema(
                properties: [
                    "directory": propertySchemaWithDefault(
                        type: "string",
                        description: "Subdirectory to list (relative to workspace root)",
                        defaultValue: .string(".")
                    ),
                    "extensions": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string("Filter by file extensions (e.g., [\"md\", \"txt\"])")
                    ]),
                    "pattern": propertySchema(
                        type: "string",
                        description: "Filter file names by regex pattern"
                    ),
                    "recursive": propertySchemaWithDefault(
                        type: "boolean",
                        description: "Recurse into subdirectories",
                        defaultValue: .bool(false)
                    ),
                    "max_depth": propertySchemaWithDefault(
                        type: "integer",
                        description: "Maximum recursion depth (only when recursive is true)",
                        defaultValue: .int(5)
                    )
                ]
            ),
            handler: { args in handle(args, workspace: workspace) }
        )
    }

    private static func handle(_ args: [String: AnyCodableValue], workspace: String) -> AnyCodableValue {
        let directory = args["directory"]?.stringValue ?? "."
        let recursive = args["recursive"]?.boolValue ?? false
        let maxDepth = args["max_depth"]?.intValue ?? 5

        guard let basePath = resolvePath(directory, workspace: workspace) else {
            return toolError("Path traversal not allowed: \(directory)")
        }

        let fileManager = FileManager.default
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: basePath, isDirectory: &isDir), isDir.boolValue else {
            return toolError("Directory not found: \(directory)")
        }

        // Parse extensions filter
        let extensions: Set<String>? = {
            guard let arr = args["extensions"]?.arrayValue else { return nil }
            let exts = arr.compactMap { $0.stringValue?.lowercased() }
            return exts.isEmpty ? nil : Set(exts)
        }()

        // Parse regex pattern (reject dangerous patterns)
        let regex: NSRegularExpression? = {
            guard let pattern = args["pattern"]?.stringValue,
                  pattern.count <= 500,
                  !GlobalSearch.hasNestedQuantifiers(pattern)
            else { return nil }
            return try? NSRegularExpression(
                pattern: pattern, options: [.caseInsensitive]
            )
        }()

        var entries: [(String, Bool)] = [] // (relativePath, isDirectory)
        let baseURL = URL(fileURLWithPath: basePath)
        let workspaceURL = URL(fileURLWithPath: workspace)

        if recursive {
            guard let enumerator = fileManager.enumerator(
                at: baseURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                return toolError("Could not enumerate directory: \(directory)")
            }

            while let url = enumerator.nextObject() as? URL {
                // Respect max depth
                let relativeToBase = url.path.dropFirst(basePath.count)
                let depth = relativeToBase.filter { $0 == "/" }.count
                if depth > maxDepth {
                    enumerator.skipDescendants()
                    continue
                }

                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                let relativePath = url.path.replacingOccurrences(of: workspaceURL.path + "/", with: "")

                if !isDirectory {
                    if let exts = extensions {
                        guard exts.contains(url.pathExtension.lowercased()) else { continue }
                    }
                    if let regex = regex {
                        let name = url.lastPathComponent
                        guard regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil else {
                            continue
                        }
                    }
                }
                entries.append((relativePath, isDirectory))
            }
        } else {
            guard let contents = try? fileManager.contentsOfDirectory(
                at: baseURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                return toolError("Could not list directory: \(directory)")
            }

            for url in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                let relativePath = url.path.replacingOccurrences(of: workspaceURL.path + "/", with: "")

                if !isDirectory {
                    if let exts = extensions {
                        guard exts.contains(url.pathExtension.lowercased()) else { continue }
                    }
                    if let regex = regex {
                        let name = url.lastPathComponent
                        guard regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil else {
                            continue
                        }
                    }
                }
                entries.append((relativePath, isDirectory))
            }
        }

        if entries.isEmpty {
            return toolResult("No files found matching the criteria in \(directory)")
        }

        var result = "## Files in \(directory)\n\n"
        for (path, isDir) in entries {
            let icon = isDir ? "📁" : "📄"
            result += "\(icon) \(path)\n"
        }
        result += "\nTotal: \(entries.count) items"

        return toolResult(result)
    }
}
