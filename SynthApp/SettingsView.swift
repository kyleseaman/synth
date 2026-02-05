import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: DocumentStore
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.headline)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            List {
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
                
                Section("Custom Agents") {
                    if store.customAgents.isEmpty {
                        Text("No custom agents found")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.customAgents, id: \.name) { agent in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(agent.name)
                                if let desc = agent.description {
                                    Text(desc)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(width: 400, height: 500)
        .onAppear { store.loadKiroConfig() }
    }
}

struct AgentInfo: Identifiable {
    let id = UUID()
    let name: String
    let description: String?
}
