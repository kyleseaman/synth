import Foundation

/// Resolves the path to the synth-mcp-server binary.
/// Checks app bundle, development build paths, and standard install locations.
enum SynthMcpResolver {
    static func resolve() -> String? {
        // Check app bundle first
        if let bundled = Bundle.main.path(forResource: "synth-mcp-server", ofType: nil) {
            if FileManager.default.isExecutableFile(atPath: bundled) {
                return bundled
            }
        }

        // Check relative to the app's location (development mode)
        if let appURL = Bundle.main.bundleURL.deletingLastPathComponent() as URL? {
            let devPaths = [
                appURL.appendingPathComponent(
                    "synth-mcp-server/.build/release/synth-mcp-server"
                ).path,
                appURL.appendingPathComponent(
                    "synth-mcp-server/.build/debug/synth-mcp-server"
                ).path
            ]
            if let found = devPaths.first(where: {
                FileManager.default.isExecutableFile(atPath: $0)
            }) {
                return found
            }
        }

        // Check standard install locations
        let home = NSHomeDirectory()
        let candidates = [
            "/usr/local/bin/synth-mcp-server",
            "/opt/homebrew/bin/synth-mcp-server",
            "\(home)/.local/bin/synth-mcp-server"
        ]
        if let found = candidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0)
        }) {
            return found
        }

        // Fall back to `which`
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = ["synth-mcp-server"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
        } catch {
            print("[SynthMcpResolver] Failed to run 'which': \(error)")
            return nil
        }
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        return nil
    }
}
