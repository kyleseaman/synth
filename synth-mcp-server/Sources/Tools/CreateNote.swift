import Foundation

enum CreateNote {
    static func definition(workspace: String) -> ToolDefinition {
        ToolDefinition(
            name: "create_note",
            description: "Create a new file in the workspace from a template. Supports blank, ADR, spec, and bug report templates.",
            inputSchema: jsonSchema(
                properties: [
                    "path": propertySchema(
                        type: "string",
                        description: "Relative path for the new file (including filename)"
                    ),
                    "template": enumSchema(
                        description: "Template to use for the new file",
                        values: ["blank", "adr", "spec", "bug"]
                    ),
                    "title": propertySchema(
                        type: "string",
                        description: "Title for the document (used in template heading)"
                    )
                ],
                required: ["path", "template"]
            ),
            handler: { args in handle(args, workspace: workspace) }
        )
    }

    private static func handle(_ args: [String: AnyCodableValue], workspace: String) -> AnyCodableValue {
        guard let path = args["path"]?.stringValue else {
            return toolError("Missing required parameter: path")
        }
        guard let template = args["template"]?.stringValue else {
            return toolError("Missing required parameter: template")
        }

        guard let fullPath = resolvePath(path, workspace: workspace) else {
            return toolError("Path traversal not allowed: \(path)")
        }

        if FileManager.default.fileExists(atPath: fullPath) {
            return toolError("File already exists: \(path)")
        }

        let title = args["title"]?.stringValue ?? (path as NSString).deletingPathExtension.components(separatedBy: "/").last ?? "Untitled"

        let content: String
        switch template {
        case "blank":
            content = blankTemplate(title: title)
        case "adr":
            content = adrTemplate(title: title)
        case "spec":
            content = specTemplate(title: title)
        case "bug":
            content = bugTemplate(title: title)
        default:
            return toolError("Unknown template: \(template). Use blank, adr, spec, or bug.")
        }

        // Create parent directories if needed
        let directory = (fullPath as NSString).deletingLastPathComponent
        do {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            try content.write(toFile: fullPath, atomically: true, encoding: .utf8)
            return toolResult("Created \(path) using \(template) template")
        } catch {
            return toolError("Could not create file: \(error.localizedDescription)")
        }
    }

    private static func blankTemplate(title: String) -> String {
        """
        ---
        title: \(title)
        created: \(iso8601Now())
        tags: []
        ---

        # \(title)

        """
    }

    private static func adrTemplate(title: String) -> String {
        """
        ---
        title: \(title)
        created: \(iso8601Now())
        status: proposed
        tags:
          - adr
        ---

        # \(title)

        ## Status

        Proposed

        ## Context

        What is the issue that we're seeing that is motivating this decision or change?

        ## Decision

        What is the change that we're proposing and/or doing?

        ## Consequences

        What becomes easier or more difficult to do because of this change?
        """
    }

    private static func specTemplate(title: String) -> String {
        """
        ---
        title: \(title)
        created: \(iso8601Now())
        status: draft
        tags:
          - spec
        ---

        # \(title)

        ## Problem

        What problem are we solving? Who is affected?

        ## Proposed Solution

        How do we plan to solve it?

        ## Success Criteria

        How do we know this is working?

        ## Open Questions

        - [ ] Question 1
        """
    }

    private static func bugTemplate(title: String) -> String {
        """
        ---
        title: \(title)
        created: \(iso8601Now())
        status: open
        severity: medium
        tags:
          - bug
        ---

        # \(title)

        ## Summary

        Brief description of the bug.

        ## Steps to Reproduce

        1. Step one
        2. Step two
        3. Step three

        ## Expected Behavior

        What should happen?

        ## Actual Behavior

        What actually happens?

        ## Environment

        - OS:
        - Version:
        """
    }

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter
    }()

    private static func iso8601Now() -> String {
        dateFormatter.string(from: Date())
    }
}
