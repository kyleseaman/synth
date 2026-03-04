import Foundation

// MARK: - Tool Definition

public struct ToolDefinition {
    public let name: String
    public let description: String
    public let inputSchema: AnyCodableValue
    public let handler: ([String: AnyCodableValue]) -> AnyCodableValue
}

// MARK: - Tool Router

public class ToolRouter {
    private var tools: [String: ToolDefinition] = [:]
    public let workspacePath: String

    public init(workspacePath: String) {
        self.workspacePath = workspacePath
        registerAllTools()
    }

    public func register(_ tool: ToolDefinition) {
        tools[tool.name] = tool
    }

    public func listTools() -> [AnyCodableValue] {
        tools.values.sorted(by: { $0.name < $1.name }).map { tool in
            .object([
                "name": .string(tool.name),
                "description": .string(tool.description),
                "inputSchema": tool.inputSchema
            ])
        }
    }

    public func callTool(name: String, arguments: [String: AnyCodableValue]) -> AnyCodableValue {
        guard let tool = tools[name] else {
            return toolError("Unknown tool: \(name)")
        }
        return tool.handler(arguments)
    }

    private func registerAllTools() {
        register(ReadNote.definition(workspace: workspacePath))
        register(ListNotes.definition(workspace: workspacePath))
        register(GlobalSearch.definition(workspace: workspacePath))
        register(ManageTags.definition(workspace: workspacePath))
        register(UpdateNote.definition(workspace: workspacePath))
        register(GetBacklinks.definition(workspace: workspacePath))
        register(GetPeople.definition(workspace: workspacePath))
        register(CreateNote.definition(workspace: workspacePath))
    }
}

// MARK: - Helpers

public func toolResult(_ text: String) -> AnyCodableValue {
    .object([
        "content": .array([
            .object([
                "type": .string("text"),
                "text": .string(text)
            ])
        ])
    ])
}

public func toolError(_ message: String) -> AnyCodableValue {
    .object([
        "content": .array([
            .object([
                "type": .string("text"),
                "text": .string("Error: \(message)")
            ])
        ]),
        "isError": .bool(true)
    ])
}

public func resolvePath(_ relativePath: String, workspace: String) -> String? {
    let fullPath: String
    if relativePath.hasPrefix("/") {
        fullPath = relativePath
    } else {
        fullPath = (workspace as NSString).appendingPathComponent(relativePath)
    }

    // Resolve symlinks and standardize to prevent traversal via symlinks
    let resolved = URL(fileURLWithPath: fullPath).resolvingSymlinksInPath().path
    let resolvedWorkspace = URL(fileURLWithPath: workspace).resolvingSymlinksInPath().path
    guard resolved.hasPrefix(resolvedWorkspace) else {
        return nil
    }
    return resolved
}

public func jsonSchema(
    type: String = "object",
    properties: [String: AnyCodableValue],
    required: [String] = []
) -> AnyCodableValue {
    var schema: [String: AnyCodableValue] = [
        "type": .string(type),
        "properties": .object(properties)
    ]
    if !required.isEmpty {
        schema["required"] = .array(required.map { .string($0) })
    }
    return .object(schema)
}

public func propertySchema(type: String, description: String) -> AnyCodableValue {
    .object([
        "type": .string(type),
        "description": .string(description)
    ])
}

public func propertySchemaWithDefault(
    type: String,
    description: String,
    defaultValue: AnyCodableValue
) -> AnyCodableValue {
    .object([
        "type": .string(type),
        "description": .string(description),
        "default": defaultValue
    ])
}

public func enumSchema(description: String, values: [String]) -> AnyCodableValue {
    .object([
        "type": .string("string"),
        "description": .string(description),
        "enum": .array(values.map { .string($0) })
    ])
}
