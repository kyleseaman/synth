import Foundation

// MARK: - Logging (stderr so it doesn't interfere with stdio transport)

func log(_ message: String) {
    FileHandle.standardError.write(Data("[synth-mcp] \(message)\n".utf8))
}

// MARK: - CLI Argument Parsing

struct CLIArgs {
    var workspace: String?
    var httpPort: UInt16?
    var useStdio: Bool = false

    static func parse(_ arguments: [String]) -> CLIArgs {
        var args = CLIArgs()
        var idx = 1 // skip executable name
        while idx < arguments.count {
            switch arguments[idx] {
            case "--workspace":
                idx += 1
                if idx < arguments.count { args.workspace = arguments[idx] }
            case "--http-port":
                idx += 1
                if idx < arguments.count { args.httpPort = UInt16(arguments[idx]) }
            case "--stdio":
                args.useStdio = true
            case "--help", "-h":
                printUsage()
                exit(0)
            default:
                // Treat first positional arg as workspace for backwards compat
                if args.workspace == nil, !arguments[idx].hasPrefix("-") {
                    args.workspace = arguments[idx]
                }
            }
            idx += 1
        }
        return args
    }

    static func printUsage() {
        let usage = """
            synth-mcp-server - MCP server for Synth workspaces

            Usage:
              synth-mcp-server --workspace <path> [--stdio] [--http-port <port>]

            Options:
              --workspace <path>   Path to the workspace root (required)
              --stdio              Enable stdio transport (JSON-RPC over stdin/stdout)
              --http-port <port>   Enable HTTP+SSE transport on localhost:<port>
              --help, -h           Show this help message

            At least one transport (--stdio or --http-port) must be specified.
            Both can be used simultaneously.
            """
        log(usage)
    }
}

// MARK: - Main

let cliArgs = CLIArgs.parse(CommandLine.arguments)

guard let workspace = cliArgs.workspace else {
    log("Error: --workspace is required")
    CLIArgs.printUsage()
    exit(1)
}

guard cliArgs.useStdio || cliArgs.httpPort != nil else {
    log("Error: at least one transport (--stdio or --http-port) is required")
    CLIArgs.printUsage()
    exit(1)
}

// Resolve workspace to absolute path
let resolvedWorkspace: String = {
    let cwd = FileManager.default.currentDirectoryPath
    let base = URL(fileURLWithPath: cwd)
    let url = URL(fileURLWithPath: workspace, relativeTo: base)
    return url.standardizedFileURL.path
}()
guard FileManager.default.fileExists(atPath: resolvedWorkspace) else {
    log("Error: workspace path does not exist: \(resolvedWorkspace)")
    exit(1)
}

log("Starting with workspace: \(resolvedWorkspace)")

// Create tool router and protocol handler
let toolRouter = ToolRouter(workspacePath: resolvedWorkspace)
let protocolHandler = MCPProtocolHandler(toolRouter: toolRouter)

// Start HTTP transport if requested
if let port = cliArgs.httpPort {
    let httpTransport = HTTPTransport(handler: protocolHandler, port: port)
    do {
        try httpTransport.start()
    } catch {
        log("Failed to start HTTP transport: \(error)")
        exit(1)
    }
}

// Start stdio transport if requested (this blocks)
if cliArgs.useStdio {
    log("Stdio transport active")
    let stdioTransport = StdioTransport(handler: protocolHandler)
    stdioTransport.run()
} else {
    // If only HTTP, keep the process alive
    log("HTTP-only mode, waiting for connections...")
    dispatchMain()
}
