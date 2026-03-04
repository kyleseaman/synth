import XCTest
@testable import Synth

final class KiroConfigManagerTests: XCTestCase {
    func testLoadConfigReadsSteeringAndAgents() throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let steeringDir = workspace.appendingPathComponent(".kiro/steering", isDirectory: true)
        let agentsDir = workspace.appendingPathComponent(".kiro/agents", isDirectory: true)
        try FileManager.default.createDirectory(at: steeringDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: agentsDir, withIntermediateDirectories: true)

        try "# Voice".write(
            to: steeringDir.appendingPathComponent("voice.md"),
            atomically: true, encoding: .utf8
        )
        let agentJSON: [String: Any] = ["name": "test-agent", "description": "A test agent"]
        let agentData = try JSONSerialization.data(withJSONObject: agentJSON)
        try agentData.write(to: agentsDir.appendingPathComponent("test-agent.json"))

        let config = KiroConfigManager.loadConfig(workspace: workspace)

        XCTAssertEqual(config.steeringFiles, ["voice.md"])
        XCTAssertEqual(config.agents.count, 1)
        XCTAssertEqual(config.agents.first?.name, "test-agent")
        XCTAssertEqual(config.agents.first?.description, "A test agent")
    }

    func testNeedsSetupReturnsTrueWhenKiroMissing() {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        XCTAssertTrue(KiroConfigManager.needsSetup(workspace: workspace))
    }

    func testNeedsSetupReturnsFalseWhenKiroExists() throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let kiroDir = workspace.appendingPathComponent(".kiro", isDirectory: true)
        try FileManager.default.createDirectory(at: kiroDir, withIntermediateDirectories: true)

        XCTAssertFalse(KiroConfigManager.needsSetup(workspace: workspace))
    }

    func testBootstrapCreatesDirectoryStructure() throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)

        KiroConfigManager.bootstrap(workspace: workspace)

        let steeringDir = workspace.appendingPathComponent(".kiro/steering")
        let agentsDir = workspace.appendingPathComponent(".kiro/agents")
        let productFile = steeringDir.appendingPathComponent("product.md")
        let writerFile = agentsDir.appendingPathComponent("doc-writer.json")

        XCTAssertTrue(FileManager.default.fileExists(atPath: steeringDir.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: agentsDir.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: productFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: writerFile.path))
    }

    func testBootstrapDoesNotOverwriteExistingFiles() throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let steeringDir = workspace.appendingPathComponent(".kiro/steering", isDirectory: true)
        try FileManager.default.createDirectory(at: steeringDir, withIntermediateDirectories: true)
        let productFile = steeringDir.appendingPathComponent("product.md")
        try "Custom content".write(to: productFile, atomically: true, encoding: .utf8)

        KiroConfigManager.bootstrap(workspace: workspace)

        let content = try String(contentsOf: productFile, encoding: .utf8)
        XCTAssertEqual(content, "Custom content")
    }
}
