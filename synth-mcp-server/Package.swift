// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "synth-mcp-server",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "SynthMCPLib",
            path: "Sources/SynthMCPLib"
        ),
        .executableTarget(
            name: "synth-mcp-server",
            dependencies: ["SynthMCPLib"],
            path: "Sources/SynthMCPServer"
        ),
        .testTarget(
            name: "SynthMCPTests",
            dependencies: ["SynthMCPLib"],
            path: "Tests"
        )
    ]
)
