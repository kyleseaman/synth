import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(DocumentStore.self) var store
    @Environment(TemplateStore.self) var templateStore
    @AppStorage("kiroCliPath") private var kiroCliPath = ""
    @AppStorage("mcpHttpBridgeEnabled") private var mcpHttpBridgeEnabled = false
    @AppStorage("hideSyntax") private var hideSyntax = true
    @AppStorage(Theme.editorFontCandidatesKey) private var editorFontCandidates = ""
    @AppStorage(Theme.terminalFontCandidatesKey) private var terminalFontCandidates = ""
    @AppStorage(Theme.sidebarFontCandidatesKey) private var sidebarFontCandidates = ""
    @State private var detectedPath = ""
    @State private var showKiroPicker = false
    @State private var selectedTemplateIdentifier: UUID?
    @State private var draftTemplateName = ""
    @State private var draftTemplateContent = ""
    @State private var draftShortcutSlot = 0
    @State private var draftCategory = ""
    @State private var draftDescription = ""
    @State private var showVariablesHelp = false
    @State private var selectedCategoryFilter: String?

    var body: some View {
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gear") }
            fontsTab.tabItem { Label("Fonts", systemImage: "textformat") }
            contextTab.tabItem { Label("Context", systemImage: "doc.text.magnifyingglass") }
            agentsTab.tabItem { Label("Agents", systemImage: "cpu") }
            templatesTab.tabItem { Label("Templates", systemImage: "text.badge.plus") }
        }
        .frame(width: 720, height: 560)
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
            Section("Editor") {
                Toggle("Hide syntax markers", isOn: $hideSyntax)
                Text(
                    "When enabled, markdown markers like **, *, [[, ]], and ` are hidden. "
                    + "The formatted text remains visible."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

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

                Toggle("Enable HTTP MCP bridge", isOn: $mcpHttpBridgeEnabled)
                Text(
                    "Keeps a background synth-mcp-server for localhost clients. "
                    + "Kiro chat uses stdio MCP per session."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
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

    // MARK: - Fonts

    private var fontsTab: some View {
        List {
            Section("Editor") {
                HStack {
                    Button("System (Default)") {
                        editorFontCandidates = ""
                    }
                    Button("MesloLGS (Mono)") {
                        editorFontCandidates = Theme.mesloPresetValue
                    }
                    Button("Source Serif 4 (Serif)") {
                        editorFontCandidates = Theme.sourceSerifPresetValue
                    }
                    Button("Public Sans (Sans)") {
                        editorFontCandidates = Theme.publicSansPresetValue
                    }
                }
                .controlSize(.small)

                if !editorFontCandidates.isEmpty {
                    TextField(
                        "Font (Editor)",
                        text: $editorFontCandidates,
                        prompt: Text("MesloLGS-Regular, FiraCode-Regular")
                    )
                    .textFieldStyle(.roundedBorder)
                }
            }

            Section("Terminal") {
                TextField(
                    "Font (Terminal)",
                    text: $terminalFontCandidates,
                    prompt: Text("MesloLGS-Regular, JetBrainsMono-Regular")
                )
                .textFieldStyle(.roundedBorder)
            }

            Section("Sidebar") {
                TextField(
                    "Font (Sidebar)",
                    text: $sidebarFontCandidates,
                    prompt: Text("SF Pro Text Regular, Inter-Regular")
                )
                .textFieldStyle(.roundedBorder)
            }

            Section {
                Text(
                    "Use comma-separated PostScript font names. "
                    + "Blank value falls back to built-in defaults."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Button("Reset Font Overrides") {
                    editorFontCandidates = ""
                    terminalFontCandidates = ""
                    sidebarFontCandidates = ""
                }
                .disabled(
                    editorFontCandidates.isEmpty
                        && terminalFontCandidates.isEmpty
                        && sidebarFontCandidates.isEmpty
                )
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

            Section {
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
            } header: {
                Text("Custom Agents")
            } footer: {
                Text("Workspace AI context is stored in .kiro/, hidden from the sidebar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                Text("Use `/` in the editor to insert templates. Variables like {{date}} are expanded automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showVariablesHelp.toggle()
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .buttonStyle(.borderless)
                .help("Show supported variables")
                .popover(isPresented: $showVariablesHelp) {
                    variablesHelpPopover
                }

                Button("New Template") {
                    selectedTemplateIdentifier = nil
                    draftTemplateName = ""
                    draftTemplateContent = ""
                    draftShortcutSlot = 0
                    draftCategory = ""
                    draftDescription = ""
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 6)

            Divider()

            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    // Category filter picker
                    if !templateStore.categories.isEmpty {
                        Picker("Filter", selection: $selectedCategoryFilter) {
                            Text("All Templates").tag(nil as String?)
                            Text("Uncategorized").tag("__uncategorized__" as String?)
                            Divider()
                            ForEach(templateStore.categories, id: \.self) { category in
                                Text(category).tag(category as String?)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)

                        Divider()
                    }

                    List(selection: $selectedTemplateIdentifier) {
                        ForEach(filteredTemplates) { template in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(template.name)
                                    .lineLimit(1)
                                HStack(spacing: 4) {
                                    if let shortcutSlot = template.shortcutSlot {
                                        Text("⌥⌘\(shortcutSlot)")
                                            .font(.caption2)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Color.accentColor.opacity(0.2))
                                            .cornerRadius(3)
                                    }
                                    if let category = template.category {
                                        Text(category)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    if template.usageCount > 0 {
                                        Text("×\(template.usageCount)")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            .tag(Optional(template.identifier))
                        }
                    }
                }
                .frame(width: 180)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        // Name field
                        TextField("Template name", text: $draftTemplateName)
                            .textFieldStyle(.roundedBorder)

                        // Category and shortcut row
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Category")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                categoryPicker
                            }

                            Spacer()

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Shortcut")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Picker("Shortcut", selection: $draftShortcutSlot) {
                                    Text("None").tag(0)
                                    ForEach(1...9, id: \.self) { slotNumber in
                                        Text("⌥⌘\(slotNumber)").tag(slotNumber)
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                            }
                        }

                        // Description field
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Description (optional)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("Brief description of this template", text: $draftDescription)
                                .textFieldStyle(.roundedBorder)
                        }

                        // Content editor
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Content")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("Use {{variable}} for dynamic content")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            TextEditor(text: $draftTemplateContent)
                                .font(Theme.terminalSwiftUIFont(size: 13))
                                .frame(minHeight: 120)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.secondary.opacity(0.2))
                                }
                        }

                        // Preview section
                        if !draftTemplateContent.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Preview")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(TemplateStore.previewExpansion(draftTemplateContent))
                                    .font(Theme.terminalSwiftUIFont(size: 12))
                                    .foregroundStyle(.secondary)
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.secondary.opacity(0.05))
                                    .cornerRadius(6)
                            }
                        }

                        // Action buttons
                        HStack {
                            if selectedTemplateIdentifier != nil {
                                Button("Delete", role: .destructive) {
                                    deleteSelectedTemplate()
                                }

                                Button("Duplicate") {
                                    duplicateSelectedTemplate()
                                }
                                .disabled(selectedTemplateIdentifier == nil)
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
    }

    private var filteredTemplates: [SavedTemplate] {
        switch selectedCategoryFilter {
        case nil:
            return templateStore.templates
        case "__uncategorized__":
            return templateStore.templatesInCategory(nil)
        case let category:
            return templateStore.templatesInCategory(category)
        }
    }

    private var categoryPicker: some View {
        HStack(spacing: 4) {
            TextField("Category", text: $draftCategory)
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)

            if !templateStore.categories.isEmpty {
                Menu {
                    Button("None") {
                        draftCategory = ""
                    }
                    Divider()
                    ForEach(templateStore.categories, id: \.self) { category in
                        Button(category) {
                            draftCategory = category
                        }
                    }
                } label: {
                    Image(systemName: "chevron.down.circle")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 20)
            }
        }
    }

    private var variablesHelpPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Supported Variables")
                .font(.headline)

            Divider()

            ForEach(TemplateExpander.supportedVariables, id: \.variable) { item in
                HStack(alignment: .top) {
                    Text(item.variable)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 140, alignment: .leading)
                    Text(item.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            Text("Date format codes: yyyy (year), MM (month), dd (day), HH (24h), hh (12h), mm (min), ss (sec)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .frame(width: 400)
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
            draftTemplateName = ""
            draftTemplateContent = ""
            draftShortcutSlot = 0
            draftCategory = ""
            draftDescription = ""
            return
        }
        draftTemplateName = template.name
        draftTemplateContent = template.content
        draftShortcutSlot = template.shortcutSlot ?? 0
        draftCategory = template.category ?? ""
        draftDescription = template.description ?? ""
    }

    private func saveTemplateDraft() {
        let shortcutSlot = draftShortcutSlot == 0 ? nil : draftShortcutSlot
        let category = draftCategory.isEmpty ? nil : draftCategory
        let description = draftDescription.isEmpty ? nil : draftDescription

        if let selectedTemplateIdentifier {
            let didUpdate = templateStore.updateTemplate(
                identifier: selectedTemplateIdentifier,
                name: draftTemplateName,
                content: draftTemplateContent,
                shortcutSlot: shortcutSlot,
                category: category,
                description: description
            )
            if !didUpdate { return }
        } else if let created = templateStore.addTemplate(
            name: draftTemplateName,
            content: draftTemplateContent,
            shortcutSlot: shortcutSlot,
            category: category,
            description: description
        ) {
            selectedTemplateIdentifier = created.identifier
        }
    }

    private func deleteSelectedTemplate() {
        guard let selectedTemplateIdentifier else { return }
        templateStore.removeTemplate(identifier: selectedTemplateIdentifier)
        self.selectedTemplateIdentifier = templateStore.templates.first?.identifier
    }

    private func duplicateSelectedTemplate() {
        guard let selectedTemplateIdentifier else { return }
        if let duplicated = templateStore.duplicateTemplate(identifier: selectedTemplateIdentifier) {
            self.selectedTemplateIdentifier = duplicated.identifier
            loadTemplateDraft()
        }
    }
}

struct AgentInfo: Identifiable {
    let id = UUID()
    let name: String
    let description: String?
}
