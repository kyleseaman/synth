import Foundation

/// Manages the lifecycle of the synth-mcp-server process.
/// Starts the server when a workspace opens and stops it on workspace change/close.
class MCPServerManager: ObservableObject {
    @Published var isRunning = false
    @Published var httpPort: UInt16 = 9712

    private var process: Process?
    private var serverPath: String?

    // MARK: - Lifecycle

    func start(workspace: URL) {
        stop()

        guard let path = SynthMcpResolver.resolve() else {
            print("[MCP] synth-mcp-server binary not found")
            return
        }
        serverPath = path

        writeMcpConfig(workspace: workspace, serverPath: path)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = [
            "--workspace", workspace.path,
            "--http-port", String(httpPort)
        ]
        proc.standardOutput = FileHandle.nullDevice

        proc.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                self?.isRunning = false
                print("[MCP] Server exited with code \(process.terminationStatus)")
            }
        }

        do {
            try proc.run()
            process = proc
            DispatchQueue.main.async {
                self.isRunning = true
            }
            print("[MCP] Server started on localhost:\(httpPort) for \(workspace.path)")
        } catch {
            print("[MCP] Failed to start server: \(error)")
        }
    }

    // MARK: - Kiro CLI MCP Config

    /// Writes .kiro/settings/mcp.json so kiro-cli discovers the MCP server.
    private func writeMcpConfig(workspace: URL, serverPath: String) {
        let settingsDir = workspace
            .appendingPathComponent(".kiro")
            .appendingPathComponent("settings")
        let mcpJson = settingsDir.appendingPathComponent("mcp.json")

        let fileManager = FileManager.default
        try? fileManager.createDirectory(
            at: settingsDir,
            withIntermediateDirectories: true
        )

        // Merge with existing config to preserve user-added servers
        var existing: [String: Any] = [:]
        if let data = try? Data(contentsOf: mcpJson),
           let parsed = try? JSONSerialization.jsonObject(
               with: data
           ) as? [String: Any] {
            existing = parsed
        }

        var servers = (existing["mcpServers"] as? [String: Any]) ?? [:]
        servers["synth-mcp"] = [
            "command": serverPath,
            "args": [
                "--workspace", workspace.path,
                "--stdio"
            ],
            "disabled": false
        ] as [String: Any]

        existing["mcpServers"] = servers

        if let data = try? JSONSerialization.data(
            withJSONObject: existing,
            options: [.prettyPrinted, .sortedKeys]
        ) {
            try? data.write(to: mcpJson)
            print("[MCP] Wrote config to \(mcpJson.path)")
        }
    }

    func stop() {
        guard let proc = process, proc.isRunning else { return }
        proc.terminate()
        process = nil
        DispatchQueue.main.async {
            self.isRunning = false
        }
        print("[MCP] Server stopped")
    }

    // MARK: - MCP Config for Kiro CLI

    /// Returns the MCP server configuration to pass to kiro-cli in session/new.
    func mcpServerConfig(workspace: String) -> [[String: AnyCodable]]? {
        guard let path = serverPath ?? SynthMcpResolver.resolve() else {
            return nil
        }
        return [[
            "name": AnyCodable("synth-mcp"),
            "command": AnyCodable(path),
            "args": AnyCodable([
                AnyCodable("--workspace"),
                AnyCodable(workspace),
                AnyCodable("--stdio")
            ]),
            "transport": AnyCodable("stdio")
        ]]
    }

    deinit {
        stop()
    }
}
