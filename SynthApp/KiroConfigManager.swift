import Foundation

/// Manages loading and bootstrapping `.kiro` configuration for a workspace.
enum KiroConfigManager {
    static func loadConfig(
        workspace: URL
    ) -> (steeringFiles: [String], agents: [AgentInfo]) {
        let kiroDir = workspace.appendingPathComponent(".kiro")
        var steeringFiles: [String] = []
        var agents: [AgentInfo] = []

        let steeringDir = kiroDir.appendingPathComponent("steering")
        if let files = try? FileManager.default.contentsOfDirectory(atPath: steeringDir.path) {
            steeringFiles = files.filter { $0.hasSuffix(".md") }
        }

        let agentsDir = kiroDir.appendingPathComponent("agents")
        if let files = try? FileManager.default.contentsOfDirectory(
            at: agentsDir, includingPropertiesForKeys: nil
        ) {
            for file in files where file.pathExtension == "json" {
                if let data = try? Data(contentsOf: file),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let name = (json["name"] as? String)
                        ?? file.deletingPathExtension().lastPathComponent
                    let desc = json["description"] as? String
                    agents.append(AgentInfo(name: name, description: desc))
                }
            }
        }

        return (steeringFiles, agents)
    }

    static func needsSetup(workspace: URL) -> Bool {
        let kiroDir = workspace.appendingPathComponent(".kiro")
        return !FileManager.default.fileExists(atPath: kiroDir.path)
    }

    static func bootstrap(workspace: URL) {
        let kiroDir = workspace.appendingPathComponent(".kiro")
        let steeringDir = kiroDir.appendingPathComponent("steering")
        let agentsDir = kiroDir.appendingPathComponent("agents")
        let fileManager = FileManager.default

        try? fileManager.createDirectory(at: steeringDir, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: agentsDir, withIntermediateDirectories: true)

        let productMd = """
        # Product Overview

        Describe your project here. This file provides context to the AI.

        ## Purpose
        What does this project do?

        ## Target Users
        Who is this for?
        """
        let productPath = steeringDir.appendingPathComponent("product.md")
        if !fileManager.fileExists(atPath: productPath.path) {
            try? productMd.write(to: productPath, atomically: true, encoding: .utf8)
        }

        let writerAgent: [String: Any] = [
            "name": "doc-writer",
            "description": "Document writer — drafts and generates content",
            "prompt": """
                You are a document writer integrated into Synth. \
                Draft new documents, expand outlines into prose, \
                write in various styles (technical, creative, business). \
                Start with structure, then fill in content. \
                Use markdown formatting. Be concise and direct.
                """,
            "tools": ["fs_read", "fs_write"],
            "allowedTools": ["fs_read", "fs_write"]
        ]
        let writerPath = agentsDir.appendingPathComponent("doc-writer.json")
        if !fileManager.fileExists(atPath: writerPath.path),
           let data = try? JSONSerialization.data(
               withJSONObject: writerAgent, options: [.prettyPrinted, .sortedKeys]
           ) {
            try? data.write(to: writerPath)
        }
    }
}
