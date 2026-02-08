import Foundation
import Observation
import Darwin

struct MCPRuntimeLease: Codable, Equatable {
    let pid: Int32
    let port: UInt16
    let workspacePath: String
    let commandPath: String
    let startedAt: Date
}

/// Manages the lifecycle of the synth-mcp-server process.
/// Starts the server when a workspace opens and stops it on workspace change/close.
@Observable final class MCPServerManager: @unchecked Sendable {
    var isRunning = false
    var httpPort: UInt16 = 9712
    var enableHTTPBridge: Bool {
        get { UserDefaults.standard.bool(forKey: Self.httpBridgeKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.httpBridgeKey) }
    }

    @ObservationIgnored var healthProbe: ((UInt16) -> Bool)?
    @ObservationIgnored var portAvailabilityProbe: ((UInt16) -> Bool)?
    @ObservationIgnored var processAliveProbe: ((Int32) -> Bool)?
    @ObservationIgnored var signalProbe: ((Int32, Int32) -> Int32)?

    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var serverPath: String?
    @ObservationIgnored private var activeWorkspace: URL?
    @ObservationIgnored private var runningProcessId: Int32?
    @ObservationIgnored private var runningPort: UInt16?
    @ObservationIgnored private var shouldAutoRestart = false
    @ObservationIgnored private var healthFailureCount = 0
    @ObservationIgnored private var restartAttempt = 0
    @ObservationIgnored private var heartbeatTimer: DispatchSourceTimer?
    @ObservationIgnored private var restartWorkItem: DispatchWorkItem?

    private static let httpBridgeKey = "mcpHttpBridgeEnabled"
    private static let runtimeLeaseName = "mcp-runtime.json"
    private static let healthPath = "/health"
    private static let heartbeatInterval: TimeInterval = 5
    private static let healthFailureThreshold = 2
    private static let startupBackoffSeconds: [TimeInterval] = [0.0, 0.4, 0.8, 1.6]

    // MARK: - Lifecycle

    func start(workspace: URL) {
        stop()
        activeWorkspace = workspace

        guard let path = SynthMcpResolver.resolve() else {
            print("[MCP] synth-mcp-server binary not found")
            return
        }
        serverPath = path

        writeMcpConfig(workspace: workspace, serverPath: path)

        if let lease = readRuntimeLease(workspace: workspace) {
            if enableHTTPBridge,
               isProcessAlive(pid: lease.pid),
               isHealthy(port: lease.port) {
                runningProcessId = lease.pid
                runningPort = lease.port
                httpPort = lease.port
                isRunning = true
                shouldAutoRestart = true
                startHeartbeat()
                print("[MCP] Reusing existing server on localhost:\(lease.port) for \(workspace.path)")
                return
            }

            terminateProcess(pid: lease.pid)
            removeRuntimeLease(workspace: workspace)
        }

        guard enableHTTPBridge else {
            print("[MCP] HTTP bridge disabled; stdio MCP will run per Kiro session")
            return
        }

        let launched = launchWithRetries(workspace: workspace, serverPath: path)
        if !launched {
            print("[MCP] Failed to start durable HTTP bridge for \(workspace.path)")
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
        shouldAutoRestart = false
        stopHeartbeat()
        cancelRestart()
        healthFailureCount = 0

        if let proc = process, proc.isRunning {
            proc.terminate()
        } else if let processId = runningProcessId {
            terminateProcess(pid: processId)
        }

        process = nil
        runningProcessId = nil
        runningPort = nil
        isRunning = false

        if let workspace = activeWorkspace {
            removeRuntimeLease(workspace: workspace)
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
            "env": AnyCodable([AnyCodable]())
        ]]
    }

    // MARK: - Runtime Lease

    func runtimeLeaseURL(workspace: URL) -> URL {
        workspace
            .appendingPathComponent(".kiro")
            .appendingPathComponent("settings")
            .appendingPathComponent(Self.runtimeLeaseName)
    }

    func readRuntimeLease(workspace: URL) -> MCPRuntimeLease? {
        let url = runtimeLeaseURL(workspace: workspace)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(MCPRuntimeLease.self, from: data)
    }

    func writeRuntimeLease(workspace: URL, pid: Int32, port: UInt16, commandPath: String) {
        let lease = MCPRuntimeLease(
            pid: pid,
            port: port,
            workspacePath: workspace.path,
            commandPath: commandPath,
            startedAt: Date()
        )
        let url = runtimeLeaseURL(workspace: workspace)
        let settingsDirectory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: settingsDirectory,
            withIntermediateDirectories: true
        )
        if let data = try? JSONEncoder().encode(lease) {
            try? data.write(to: url, options: [.atomic])
        }
    }

    func removeRuntimeLease(workspace: URL) {
        let url = runtimeLeaseURL(workspace: workspace)
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Port Selection

    func selectAvailablePort(preferredPort: UInt16, searchWindow: Int = 12) -> UInt16? {
        if isPortAvailable(preferredPort) {
            return preferredPort
        }

        for offset in 1...searchWindow {
            let next = Int(preferredPort) + offset
            guard next <= Int(UInt16.max) else { break }
            let candidate = UInt16(next)
            if isPortAvailable(candidate) {
                return candidate
            }
        }

        return nil
    }

    // MARK: - Launch + Monitoring

    private func launchWithRetries(workspace: URL, serverPath: String) -> Bool {
        for attemptIndex in Self.startupBackoffSeconds.indices {
            let retryDelay = Self.startupBackoffSeconds[attemptIndex]
            if retryDelay > 0 {
                Thread.sleep(forTimeInterval: retryDelay)
            }

            let preferred = UInt16(clamping: Int(httpPort) + attemptIndex)
            guard let selectedPort = selectAvailablePort(preferredPort: preferred) else {
                continue
            }

            guard let proc = launchProcess(
                executablePath: serverPath,
                workspacePath: workspace.path,
                port: selectedPort
            ) else {
                continue
            }

            guard waitForHealthyServer(process: proc, port: selectedPort) else {
                proc.terminate()
                continue
            }

            process = proc
            runningProcessId = proc.processIdentifier
            runningPort = selectedPort
            httpPort = selectedPort
            shouldAutoRestart = true
            restartAttempt = 0
            healthFailureCount = 0
            isRunning = true
            writeRuntimeLease(
                workspace: workspace,
                pid: proc.processIdentifier,
                port: selectedPort,
                commandPath: serverPath
            )
            startHeartbeat()
            print("[MCP] Server started on localhost:\(selectedPort) for \(workspace.path)")
            return true
        }

        return false
    }

    private func launchProcess(
        executablePath: String,
        workspacePath: String,
        port: UInt16
    ) -> Process? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executablePath)
        proc.arguments = [
            "--workspace", workspacePath,
            "--http-port", String(port)
        ]
        proc.standardOutput = FileHandle.nullDevice
        proc.terminationHandler = { [weak self] endedProcess in
            DispatchQueue.main.async {
                self?.handleProcessTermination(endedProcess)
            }
        }

        do {
            try proc.run()
            return proc
        } catch {
            print("[MCP] Failed to launch server process: \(error)")
            return nil
        }
    }

    private func handleProcessTermination(_ endedProcess: Process) {
        let processId = endedProcess.processIdentifier
        let terminationStatus = endedProcess.terminationStatus

        if runningProcessId == processId {
            isRunning = false
            runningProcessId = nil
            runningPort = nil
            process = nil
            if let workspace = activeWorkspace {
                removeRuntimeLease(workspace: workspace)
            }
        }

        print("[MCP] Server exited with code \(terminationStatus)")

        guard shouldAutoRestart, enableHTTPBridge else { return }
        scheduleRestart(reason: "process exit \(terminationStatus)")
    }

    private func waitForHealthyServer(process: Process, port: UInt16) -> Bool {
        let timeoutSeconds: TimeInterval = 2
        let pollInterval: TimeInterval = 0.2
        let deadline = Date().addingTimeInterval(timeoutSeconds)

        while Date() < deadline {
            guard process.isRunning else { return false }
            if isHealthy(port: port) {
                return true
            }
            Thread.sleep(forTimeInterval: pollInterval)
        }

        return process.isRunning && isHealthy(port: port)
    }

    private func startHeartbeat() {
        stopHeartbeat()
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(
            deadline: .now() + Self.heartbeatInterval,
            repeating: Self.heartbeatInterval
        )
        timer.setEventHandler { [weak self] in
            self?.heartbeatTick()
        }
        timer.resume()
        heartbeatTimer = timer
    }

    private func stopHeartbeat() {
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
    }

    private func heartbeatTick() {
        guard shouldAutoRestart,
              enableHTTPBridge,
              isRunning,
              let activePort = runningPort else { return }

        if isHealthy(port: activePort) {
            healthFailureCount = 0
            return
        }

        healthFailureCount += 1
        print("[MCP] Health check failed on port \(activePort) (\(healthFailureCount))")

        guard healthFailureCount >= Self.healthFailureThreshold else { return }
        healthFailureCount = 0
        scheduleRestart(reason: "health check failures")
    }

    private func scheduleRestart(reason: String) {
        guard restartWorkItem == nil,
              let workspace = activeWorkspace else { return }

        let backoff = [0.5, 1.0, 2.0, 4.0]
        let delay = backoff[min(restartAttempt, backoff.count - 1)]
        restartAttempt += 1
        print("[MCP] Scheduling restart in \(delay)s (\(reason))")

        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.restartWorkItem = nil
            self.start(workspace: workspace)
        }
        restartWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func cancelRestart() {
        restartWorkItem?.cancel()
        restartWorkItem = nil
        restartAttempt = 0
    }

    // MARK: - Health + Process Helpers

    private func isHealthy(port: UInt16) -> Bool {
        if let probe = healthProbe {
            return probe(port)
        }

        guard let url = URL(
            string: "http://127.0.0.1:\(port)\(Self.healthPath)"
        ) else { return false }

        let semaphore = DispatchSemaphore(value: 0)
        let healthResult = HealthResult()

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 1

        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            defer { semaphore.signal() }
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let data else { return }
            let body = String(data: data, encoding: .utf8) ?? ""
            healthResult.value = body.contains("\"ok\"")
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 2)
        task.cancel()
        return healthResult.value
    }

    private func isPortAvailable(_ port: UInt16) -> Bool {
        if let probe = portAvailabilityProbe {
            return probe(port)
        }

        let socketDescriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard socketDescriptor >= 0 else { return false }
        defer { close(socketDescriptor) }

        var reuseAddress: Int32 = 1
        setsockopt(
            socketDescriptor,
            SOL_SOCKET,
            SO_REUSEADDR,
            &reuseAddress,
            socklen_t(MemoryLayout<Int32>.size)
        )

        var socketAddress = sockaddr_in()
        socketAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        socketAddress.sin_family = sa_family_t(AF_INET)
        socketAddress.sin_port = port.bigEndian
        socketAddress.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        return withUnsafePointer(to: &socketAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { reboundPointer in
                bind(
                    socketDescriptor,
                    reboundPointer,
                    socklen_t(MemoryLayout<sockaddr_in>.size)
                ) == 0
            }
        }
    }

    private func isProcessAlive(pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        if let probe = processAliveProbe {
            return probe(pid)
        }
        let signalResult = signalProbe?(pid, 0) ?? Darwin.kill(pid, 0)
        if signalResult == 0 {
            return true
        }
        return errno == EPERM
    }

    private func terminateProcess(pid: Int32) {
        guard pid > 0 else { return }
        _ = signalProbe?(pid, SIGTERM) ?? Darwin.kill(pid, SIGTERM)
    }

}

private final class HealthResult: @unchecked Sendable {
    var value = false
}
