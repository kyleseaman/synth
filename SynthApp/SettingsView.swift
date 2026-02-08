import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(DocumentStore.self) var store
    @AppStorage("kiroCliPath") private var kiroCliPath = ""
    @State private var detectedPath = ""
    @State private var showKiroPicker = false

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
                    Button("Browse...") { showKiroPicker = true }
                        .controlSize(.small)
                }
            }
        }
        .padding()
        .fileImporter(
            isPresented: $showKiroPicker,
            allowedContentTypes: [.item]
        ) { result in
            if case .success(let url) = result {
                kiroCliPath = url.path
            }
        }
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

            if store.needsKiroSetup && store.workspace != nil {
                Section {
                    Button("Initialize .kiro") {
                        store.bootstrapKiroConfig()
                    }
                } footer: {
                    Text("Creates .kiro/ folder with steering context and a doc-writer agent.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
}

struct AgentInfo: Identifiable {
    let id = UUID()
    let name: String
    let description: String?
}
