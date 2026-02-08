import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: DocumentStore
    @EnvironmentObject var templateStore: TemplateStore
    @AppStorage("kiroCliPath") private var kiroCliPath = ""
    @State private var detectedPath = ""
    @State private var selectedTemplateIdentifier: UUID?
    @State private var draftTemplateName = ""
    @State private var draftTemplateContent = ""
    @State private var draftShortcutSlot = 0

    var body: some View {
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gear") }
            contextTab.tabItem { Label("Context", systemImage: "doc.text.magnifyingglass") }
            agentsTab.tabItem { Label("Agents", systemImage: "cpu") }
            templatesTab.tabItem { Label("Templates", systemImage: "text.badge.plus") }
        }
        .frame(width: 480, height: 400)
        .onAppear {
            store.loadKiroConfig()
            detectedPath = KiroCliResolver.resolve() ?? "Not found"
            if selectedTemplateIdentifier == nil {
                selectedTemplateIdentifier = templateStore.templates.first?.identifier
            }
            loadTemplateDraft()
        }
        .onChange(of: selectedTemplateIdentifier) {
            loadTemplateDraft()
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

    // MARK: - Templates

    private var templatesTab: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Use `/` in the editor to insert templates.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("New Template") {
                    selectedTemplateIdentifier = nil
                    draftTemplateName = ""
                    draftTemplateContent = ""
                    draftShortcutSlot = 0
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 6)

            Divider()

            HStack(spacing: 0) {
                List(selection: $selectedTemplateIdentifier) {
                    ForEach(templateStore.templates) { template in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.name)
                                .lineLimit(1)
                            if let shortcutSlot = template.shortcutSlot {
                                Text("⌥⌘\(shortcutSlot)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(Optional(template.identifier))
                    }
                }
                .frame(width: 170)

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    TextField("Template name", text: $draftTemplateName)
                        .textFieldStyle(.roundedBorder)

                    Picker("Shortcut", selection: $draftShortcutSlot) {
                        Text("None").tag(0)
                        ForEach(1...9, id: \.self) { slotNumber in
                            Text("⌥⌘\(slotNumber)").tag(slotNumber)
                        }
                    }
                    .pickerStyle(.menu)

                    Text("Content")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $draftTemplateContent)
                        .font(.system(size: 13, design: .monospaced))
                        .frame(minHeight: 180)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.2))
                        }

                    HStack {
                        if selectedTemplateIdentifier != nil {
                            Button("Delete", role: .destructive) {
                                deleteSelectedTemplate()
                            }
                        }
                        Spacer()
                        Button(selectedTemplateIdentifier == nil ? "Add Template" : "Save Changes") {
                            saveTemplateDraft()
                        }
                        .disabled(isTemplateDraftInvalid)
                    }
                }
                .padding(12)
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

    private var isTemplateDraftInvalid: Bool {
        draftTemplateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || draftTemplateContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func loadTemplateDraft() {
        guard let selectedTemplateIdentifier,
              let template = templateStore.templates.first(
                  where: { $0.identifier == selectedTemplateIdentifier }
              ) else {
            if selectedTemplateIdentifier == nil {
                draftTemplateName = ""
                draftTemplateContent = ""
                draftShortcutSlot = 0
            }
            return
        }
        draftTemplateName = template.name
        draftTemplateContent = template.content
        draftShortcutSlot = template.shortcutSlot ?? 0
    }

    private func saveTemplateDraft() {
        let shortcutSlot = draftShortcutSlot == 0 ? nil : draftShortcutSlot
        if let selectedTemplateIdentifier {
            let didUpdate = templateStore.updateTemplate(
                identifier: selectedTemplateIdentifier,
                name: draftTemplateName,
                content: draftTemplateContent,
                shortcutSlot: shortcutSlot
            )
            if !didUpdate { return }
        } else if let created = templateStore.addTemplate(
            name: draftTemplateName,
            content: draftTemplateContent,
            shortcutSlot: shortcutSlot
        ) {
            selectedTemplateIdentifier = created.identifier
        }
    }

    private func deleteSelectedTemplate() {
        guard let selectedTemplateIdentifier else { return }
        templateStore.removeTemplate(identifier: selectedTemplateIdentifier)
        self.selectedTemplateIdentifier = templateStore.templates.first?.identifier
        if self.selectedTemplateIdentifier == nil {
            draftTemplateName = ""
            draftTemplateContent = ""
            draftShortcutSlot = 0
        }
    }
}

struct AgentInfo: Identifiable {
    let id = UUID()
    let name: String
    let description: String?
}
