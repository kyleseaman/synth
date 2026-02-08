import Foundation

/// Resolves the path to the synth-mcp-server binary.
/// Checks app bundle, development build paths, and standard install locations.
enum SynthMcpResolver {
    static func resolve() -> String? {
        let fileManager = FileManager.default

        // Check app bundle first
        if let bundled = Bundle.main.path(forResource: "synth-mcp-server", ofType: nil) {
            if fileManager.isExecutableFile(atPath: bundled) {
                return bundled
            }
        }

        let developmentCandidates = developmentBuildCandidatePaths(
            bundleURL: Bundle.main.bundleURL,
            sourceFilePath: #filePath,
            currentDirectoryPath: fileManager.currentDirectoryPath
        )
        if let found = firstExecutablePath(in: developmentCandidates, fileManager: fileManager) {
            return found
        }

        let installCandidates = standardInstallCandidatePaths(homeDirectoryPath: NSHomeDirectory())
        if let found = firstExecutablePath(in: installCandidates, fileManager: fileManager) {
            return found
        }

        return executableFromWhich()
    }

    static func developmentBuildCandidatePaths(
        bundleURL: URL?,
        sourceFilePath: String,
        currentDirectoryPath: String
    ) -> [String] {
        var candidatePaths: [String] = []

        if let bundleURL {
            let bundleParentURL = bundleURL.deletingLastPathComponent()
            appendBuildCandidates(baseDirectory: bundleParentURL, candidatePaths: &candidatePaths)
        }

        let sourceFileURL = URL(fileURLWithPath: sourceFilePath)
        let sourceDirectoryURL = sourceFileURL.deletingLastPathComponent()
        let sourceRootURL = sourceDirectoryURL.deletingLastPathComponent()
        appendBuildCandidates(baseDirectory: sourceRootURL, candidatePaths: &candidatePaths)

        let currentDirectoryURL = URL(fileURLWithPath: currentDirectoryPath, isDirectory: true)
        appendBuildCandidates(baseDirectory: currentDirectoryURL, candidatePaths: &candidatePaths)
        appendBuildCandidates(
            baseDirectory: currentDirectoryURL.deletingLastPathComponent(),
            candidatePaths: &candidatePaths
        )

        return candidatePaths
    }

    static func standardInstallCandidatePaths(homeDirectoryPath: String) -> [String] {
        [
            "/usr/local/bin/synth-mcp-server",
            "/opt/homebrew/bin/synth-mcp-server",
            "\(homeDirectoryPath)/.local/bin/synth-mcp-server"
        ]
    }

    static func firstExecutablePath(
        in candidatePaths: [String],
        fileManager: FileManager = .default
    ) -> String? {
        candidatePaths.first(where: { fileManager.isExecutableFile(atPath: $0) })
    }

    private static func appendBuildCandidates(baseDirectory: URL, candidatePaths: inout [String]) {
        let releaseBinaryPath = baseDirectory
            .appendingPathComponent("synth-mcp-server")
            .appendingPathComponent(".build")
            .appendingPathComponent("release")
            .appendingPathComponent("synth-mcp-server")
            .path
        appendUnique(path: releaseBinaryPath, candidatePaths: &candidatePaths)

        let debugBinaryPath = baseDirectory
            .appendingPathComponent("synth-mcp-server")
            .appendingPathComponent(".build")
            .appendingPathComponent("debug")
            .appendingPathComponent("synth-mcp-server")
            .path
        appendUnique(path: debugBinaryPath, candidatePaths: &candidatePaths)
    }

    private static func appendUnique(path: String, candidatePaths: inout [String]) {
        guard !candidatePaths.contains(path) else { return }
        candidatePaths.append(path)
    }

    private static func executableFromWhich() -> String? {
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
