// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "synth-mcp-server",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "synth-mcp-server",
            path: "Sources"
        )
    ]
)
