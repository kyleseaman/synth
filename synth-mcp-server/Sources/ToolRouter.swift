import Foundation

// MARK: - Tool Definition

struct ToolDefinition {
    let name: String
    let description: String
    let inputSchema: AnyCodableValue
    let handler: ([String: AnyCodableValue]) -> AnyCodableValue
}

// MARK: - Tool Router

class ToolRouter {
    private var tools: [String: ToolDefinition] = [:]
    let workspacePath: String

    init(workspacePath: String) {
        self.workspacePath = workspacePath
        registerAllTools()
    }

    func register(_ tool: ToolDefinition) {
        tools[tool.name] = tool
    }

    func listTools() -> [AnyCodableValue] {
        tools.values.sorted(by: { $0.name < $1.name }).map { tool in
            .object([
                "name": .string(tool.name),
                "description": .string(tool.description),
                "inputSchema": tool.inputSchema
            ])
        }
    }

    func callTool(name: String, arguments: [String: AnyCodableValue]) -> AnyCodableValue {
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

func toolResult(_ text: String) -> AnyCodableValue {
    .object([
        "content": .array([
            .object([
                "type": .string("text"),
                "text": .string(text)
            ])
        ])
    ])
}

func toolError(_ message: String) -> AnyCodableValue {
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

func resolvePath(_ relativePath: String, workspace: String) -> String? {
    let fullPath: String
    if relativePath.hasPrefix("/") {
        fullPath = relativePath
    } else {
        fullPath = (workspace as NSString).appendingPathComponent(relativePath)
    }

    // Prevent path traversal outside workspace
    let resolved = (fullPath as NSString).standardizingPath
    guard resolved.hasPrefix((workspace as NSString).standardizingPath) else {
        return nil
    }
    return resolved
}

func jsonSchema(
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

func propertySchema(type: String, description: String) -> AnyCodableValue {
    .object([
        "type": .string(type),
        "description": .string(description)
    ])
}

func propertySchemaWithDefault(type: String, description: String, defaultValue: AnyCodableValue) -> AnyCodableValue {
    .object([
        "type": .string(type),
        "description": .string(description),
        "default": defaultValue
    ])
}

func enumSchema(description: String, values: [String]) -> AnyCodableValue {
    .object([
        "type": .string("string"),
        "description": .string(description),
        "enum": .array(values.map { .string($0) })
    ])
}
