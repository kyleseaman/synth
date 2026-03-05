import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(DocumentStore.self) var store
    @Environment(TemplateStore.self) var templateStore
    @AppStorage("kiroCliPath") private var kiroCliPath = ""
    @AppStorage("mcpHttpBridgeEnabled") private var mcpHttpBridgeEnabled = false
    @AppStorage("hideSyntax") private var hideSyntax = true
    @AppStorage("qmdEnabled") private var qmdEnabled = true
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
    @State private var qmdDetectedPath = ""
    @State private var qmdSetupInProgress = false
    @State private var qmdSetupResult: String?

    var body: some View {
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gear") }
            fontsTab.tabItem { Label("Fonts", systemImage: "textformat") }
            searchTab.tabItem { Label("Search", systemImage: "magnifyingglass") }
            contextTab.tabItem { Label("Context", systemImage: "doc.text.magnifyingglass") }
            mcpTab.tabItem { Label("MCP", systemImage: "server.rack") }
            agentsTab.tabItem { Label("Agents", systemImage: "cpu") }
            templatesTab.tabItem { Label("Templates", systemImage: "text.badge.plus") }
        }
        .frame(width: 720, height: 560)
        .onAppear {
            store.loadKiroConfig()
            detectedPath = KiroCliResolver.resolve() ?? "Not found"
            qmdDetectedPath = QmdResolver.resolve() ?? "Not found"
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
        .onChange(of: editorFontCandidates) { Theme.invalidateFontCache() }
        .onChange(of: terminalFontCandidates) { Theme.invalidateFontCache() }
        .onChange(of: sidebarFontCandidates) { Theme.invalidateFontCache() }
    }

    // MARK: - Search (QMD)

    private var searchTab: some View {
        List {
            Section {
                HStack {
                    if qmdDetectedPath != "Not found" {
                        Label("Installed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Spacer()
                        Text(qmdDetectedPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Label("Not found", systemImage: "xmark.circle")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Refresh") {
                            QmdResolver.invalidateCache()
                            qmdDetectedPath = QmdResolver.resolve() ?? "Not found"
                        }
                        .controlSize(.small)
                    }
                }
                if qmdDetectedPath == "Not found" {
                    Text(
                        "Install QMD to enable enhanced search with BM25 "
                        + "full-text indexing:\n\n"
                        + "  npm install -g @tobilu/qmd\n\n"
                        + "Or with Bun:\n\n"
                        + "  bun install -g @tobilu/qmd\n\n"
                        + "Requires Node.js ≥ 22 or Bun ≥ 1.0. "
                        + "More info: github.com/tobi/qmd"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                }
            } header: {
                Text("QMD Status")
            }

            if qmdDetectedPath != "Not found" {
                Section {
                    Toggle("Enable QMD enhanced search", isOn: $qmdEnabled)
                        .onChange(of: qmdEnabled) {
                            if let workspace = store.workspace {
                                if qmdEnabled {
                                    store.enableQmd(workspace: workspace)
                                } else {
                                    store.disableQmd()
                                }
                            }
                        }
                } header: {
                    Text("Preferences")
                }
            }

            if let qmdClient = store.qmdClient, qmdClient.isAvailable {
                Section {
                    HStack {
                        Label(
                            qmdClient.isWorkspaceIndexed ? "Workspace indexed" : "Not indexed",
                            systemImage: qmdClient.isWorkspaceIndexed
                                ? "checkmark.circle.fill" : "circle"
                        )
                        .foregroundStyle(
                            qmdClient.isWorkspaceIndexed ? .green : .secondary
                        )
                        Spacer()
                        if qmdSetupInProgress {
                            ProgressView()
                                .controlSize(.small)
                            Text("Setting up…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Button(qmdClient.isWorkspaceIndexed ? "Re-index" : "Set up QMD") {
                                setupQmd()
                            }
                            .controlSize(.small)
                        }
                    }
                    if let result = qmdSetupResult {
                        Text(result)
                            .font(.caption)
                            .foregroundStyle(
                                result.contains("✓") ? .green : .red
                            )
                    }
                    if !qmdClient.isWorkspaceIndexed && !qmdSetupInProgress {
                        Text(
                            "Click \"Set up QMD\" to index this workspace. "
                            + "This runs `qmd collection add` and `qmd embed` "
                            + "to build a full-text and vector search index. "
                            + "The file launcher (⌘P) will then use QMD for "
                            + "higher-quality results on Enter, and AI chat "
                            + "gets better workspace context."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Workspace")
                }
            }

            Section {
                Text(
                    "QMD is an optional add-on that enhances search with BM25 full-text "
                    + "indexing and semantic vector search. When set up, the file launcher "
                    + "(⌘P) uses QMD for higher-quality results, and the AI chat gets "
                    + "better workspace context.\n\n"
                    + "Synth works perfectly without QMD — the built-in search remains "
                    + "available as a fast fallback."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                Text("About QMD")
            }
        }
    }

    private func setupQmd() {
        guard let workspace = store.workspace,
              let qmdClient = store.qmdClient else { return }
        qmdSetupInProgress = true
        qmdSetupResult = nil
        Task {
            let name = workspace.lastPathComponent
                .lowercased()
                .replacingOccurrences(
                    of: "[^a-z0-9-]",
                    with: "-",
                    options: .regularExpression
                )
            let added = await qmdClient.collectionAdd(
                path: workspace.path, name: name
            )
            guard added else {
                await MainActor.run {
                    qmdSetupResult = "✗ Failed to add collection"
                    qmdSetupInProgress = false
                }
                return
            }
            let embedded = await qmdClient.embed()
            await qmdClient.refreshWorkspaceStatus(workspace: workspace)
            await MainActor.run {
                qmdSetupResult = embedded
                    ? "✓ Workspace indexed successfully"
                    : "✓ Collection added (embeddings skipped)"
                qmdSetupInProgress = false
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

    // MARK: - MCP

    private var mcpTab: some View {
        List {
            Section {
                HStack {
                    Label(
                        store.mcpServer.isRunning ? "Running" : "Stopped",
                        systemImage: store.mcpServer.isRunning
                            ? "circle.fill" : "circle"
                    )
                    .foregroundStyle(store.mcpServer.isRunning ? .green : .secondary)
                    Spacer()
                    if store.mcpServer.isRunning {
                        Text("Port \(store.mcpServer.httpPort)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle("Enable HTTP bridge", isOn: $mcpHttpBridgeEnabled)
                Text(
                    "When enabled, synth-mcp-server runs on localhost:\(store.mcpServer.httpPort) "
                    + "for external MCP clients. The AI chat always uses a per-session stdio connection."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                Text("Server Status")
            }

            Section {
                ForEach(mcpToolDescriptions, id: \.name) { tool in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tool.name)
                            .font(.system(.body, design: .monospaced))
                        Text(tool.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Available Tools (\(mcpToolDescriptions.count))")
            } footer: {
                Text("These tools give the AI full read/write access to your workspace notes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Usage") {
                Text(
                    "The MCP server exposes workspace tools over JSON-RPC 2.0. "
                    + "Synth's AI chat connects automatically via stdio.\n\n"
                    + "To use with external clients (Claude Desktop, etc.):\n"
                    + "1. Enable the HTTP bridge above\n"
                    + "2. Point your client to http://localhost:\(store.mcpServer.httpPort)/sse\n"
                    + "3. The server auto-starts when a workspace is open"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("CLI") {
                Text(
                    "You can also run the server directly:\n"
                    + "synth-mcp-server --workspace /path/to/notes --mode stdio\n"
                    + "synth-mcp-server --workspace /path/to/notes --mode http --port 9712"
                )
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            }
        }
    }

    private var mcpToolDescriptions: [(name: String, description: String)] {
        [
            ("read_note", "Read the contents of a note by path"),
            ("create_note", "Create a new note with content"),
            ("update_note", "Append or prepend content to a note"),
            ("list_notes", "List all notes in the workspace"),
            ("global_search", "Full-text search across all notes"),
            ("get_backlinks", "Find notes that link to a given note"),
            ("manage_tags", "List, add, or remove tags"),
            ("get_people", "List @mentioned people across notes")
        ]
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
