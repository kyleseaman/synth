import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: DocumentStore
    @AppStorage("kiroCliPath") private var kiroCliPath = ""
    @State private var detectedPath = ""

    var body: some View {
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gear") }
            contextTab.tabItem { Label("Context", systemImage: "doc.text.magnifyingglass") }
            agentsTab.tabItem { Label("Agents", systemImage: "cpu") }
        }
        .frame(width: 480, height: 400)
        .onAppear {
            store.loadKiroConfig()
            detectedPath = KiroCliResolver.resolve() ?? "Not found"
        }
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            Section("Kiro CLI") {
                TextField("Path to kiro-cli", text: $kiroCliPath, prompt: Text("Auto-detect"))
                    .textFieldStyle(.roundedBorder)

                HStack {
                    if kiroCliPath.isEmpty {
                        Label("Auto-detected: \(detectedPath)", systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if FileManager.default.isExecutableFile(atPath: kiroCliPath) {
                        Label("Valid executable", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Label("Not found at this path", systemImage: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    Spacer()
                    Button("Browse...") { browseForKiroCli() }
                        .controlSize(.small)
                }
            }
        }
        .padding()
    }

    // MARK: - Context

    private var contextTab: some View {
        List {
            Section {
                if let workspace = store.workspace {
                    Label(workspace.lastPathComponent, systemImage: "folder.fill")
                        .font(.headline)
                } else {
                    Text("No workspace open")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Workspace")
            } footer: {
                Text("Steering files in .kiro/steering/ provide context to the AI for this workspace.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Steering Files") {
                if store.steeringFiles.isEmpty {
                    Text("No steering files found")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.steeringFiles, id: \.self) { file in
                        Label(file, systemImage: "doc.text")
                    }
                }
            }
        }
    }

    // MARK: - Agents

    private var agentsTab: some View {
        List {
            Section {
                if store.customAgents.isEmpty {
                    Text("No custom agents found").foregroundStyle(.secondary)
                } else {
                    ForEach(store.customAgents, id: \.name) { agent in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(agent.name)
                            if let desc = agent.description {
                                Text(desc).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("Custom Agents")
            } footer: {
                Text("Agents defined in .kiro/agents/ for this workspace.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func browseForKiroCli() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Select kiro-cli"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                kiroCliPath = url.path
            }
        }
    }
}

struct AgentInfo: Identifiable {
    let id = UUID()
    let name: String
    let description: String?
}
