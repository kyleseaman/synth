import Foundation

/// Resolves the path to the `qmd` binary.
/// Checks common install locations and falls back to `which`.
enum QmdResolver {
    nonisolated(unsafe) private static var _cached: String?
    nonisolated(unsafe) private static var _hasChecked = false
    private static let lock = NSLock()

    static func resolve() -> String? {
        lock.lock()
        defer { lock.unlock() }
        if _hasChecked { return _cached }
        _hasChecked = true
        _cached = findQmd()
        return _cached
    }

    /// Force re-detection (e.g. after user installs QMD).
    static func invalidateCache() {
        lock.lock()
        defer { lock.unlock() }
        _hasChecked = false
        _cached = nil
    }

    private static func findQmd() -> String? {
        let home = NSHomeDirectory()
        let candidates = [
            "/usr/local/bin/qmd",
            "/opt/homebrew/bin/qmd",
            "\(home)/.local/bin/qmd",
            "\(home)/.bun/bin/qmd",
            "\(home)/.npm-global/bin/qmd"
        ]
        if let found = candidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0)
        }) {
            return found
        }
        return executableFromWhich("qmd")
    }

    private static func executableFromWhich(_ name: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = [name]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty,
              FileManager.default.isExecutableFile(atPath: path) else {
            return nil
        }
        return path
    }
}
