import Foundation

// MARK: - JSON-RPC Types

struct JsonRpcRequest: Codable {
    let jsonrpc: String
    let id: Int
    let method: String
    let params: [String: AnyCodable]?

    init(id: Int, method: String, params: [String: AnyCodable]? = nil) {
        self.jsonrpc = "2.0"
        self.id = id
        self.method = method
        self.params = params
    }
}

struct JsonRpcNotification: Codable {
    let jsonrpc: String
    let method: String
    let params: [String: AnyCodable]?
}

struct JsonRpcResponse: Codable {
    let jsonrpc: String
    let id: Int?
    let result: AnyCodable?
    let error: JsonRpcError?
}

struct JsonRpcError: Codable {
    let code: Int
    let message: String
}

// MARK: - AnyCodable Helper

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            value = str
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let dbl = try? container.decode(Double.self) {
            value = dbl
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict
        } else if let arr = try? container.decode([AnyCodable].self) {
            value = arr
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let str as String: try container.encode(str)
        case let int as Int: try container.encode(int)
        case let dbl as Double: try container.encode(dbl)
        case let bool as Bool: try container.encode(bool)
        case let dict as [String: AnyCodable]: try container.encode(dict)
        case let arr as [AnyCodable]: try container.encode(arr)
        default: try container.encodeNil()
        }
    }

    var stringValue: String? { value as? String }
    var intValue: Int? { value as? Int }
    var dictValue: [String: AnyCodable]? { value as? [String: AnyCodable] }
    var arrayValue: [AnyCodable]? { value as? [AnyCodable] }
}

// MARK: - ACP Tool Call Model

struct ACPToolCall: Identifiable {
    let id: String
    var title: String
    var kind: String
    var status: String

    init(id: String, title: String, kind: String = "other", status: String = "pending") {
        self.id = id
        self.title = title
        self.kind = kind
        self.status = status
    }
}

// MARK: - ACP Permission Request

struct PermissionOption {
    let id: String
    let label: String
    let kind: String
}

struct DiffContent {
    let oldText: String
    let newText: String
    let path: String
}

struct ACPPermissionRequest: Identifiable {
    let id: String  // JSON-RPC request ID (UUID string)
    let toolCallId: String
    let title: String
    let options: [PermissionOption]
    var diffContent: DiffContent?
}

// MARK: - Kiro CLI Path Resolution

enum KiroCliResolver {
    static func resolve() -> String? {
        let userPath = UserDefaults.standard.string(forKey: "kiroCliPath") ?? ""
        if !userPath.isEmpty && FileManager.default.isExecutableFile(atPath: userPath) {
            return userPath
        }
        let home = NSHomeDirectory()
        let candidates = [
            "/usr/local/bin/kiro-cli",
            "/opt/homebrew/bin/kiro-cli",
            "\(home)/.local/bin/kiro-cli",
            "\(home)/.toolbox/bin/kiro-cli"
        ]
        if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return found
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = ["kiro-cli"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }
}
