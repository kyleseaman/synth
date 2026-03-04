import Foundation

public func log(_ message: String) {
    FileHandle.standardError.write(
        Data("[synth-mcp] \(message)\n".utf8)
    )
}
