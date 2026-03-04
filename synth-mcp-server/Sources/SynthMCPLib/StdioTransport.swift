import Foundation

public class StdioTransport {
    public let handler: MCPProtocolHandler

    public init(handler: MCPProtocolHandler) {
        self.handler = handler
    }

    public func run() {
        let stdinHandle = FileHandle.standardInput
        var buffer = Data()

        while true {
            let chunk = stdinHandle.availableData
            if chunk.isEmpty {
                // EOF — stdin closed
                break
            }
            buffer.append(chunk)

            // Process complete lines (newline-delimited JSON)
            while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let lineData = Data(buffer[..<newlineIndex])
                buffer = Data(buffer[(newlineIndex + 1)...])

                guard !lineData.isEmpty else { continue }

                if let responseData = handler.handleMessage(lineData) {
                    var output = responseData
                    output.append(UInt8(ascii: "\n"))
                    FileHandle.standardOutput.write(output)
                }
            }
        }
    }
}
