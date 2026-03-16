import SwiftUI
import AppKit
import Sparkle

class AppDelegate: NSObject, NSApplicationDelegate {
    var store: DocumentStore?
    var hotkeyMonitor: GlobalHotkeyMonitor?

    func applicationWillResignActive(_ notification: Notification) {
        store?.saveAll()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store?.shutdownForTermination()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        hotkeyMonitor = GlobalHotkeyMonitor(key: "l", modifiers: [.command, .shift]) {
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                self.store?.showLinkCaptureModal()
            }
        }
    }
}

@main
struct SynthApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var store = DocumentStore()
    @State private var linkStore = LinkStore()
    @State private var templateStore = TemplateStore()
    private let updaterDelegate = UpdaterDelegate()
    private let updaterController: SPUStandardUpdaterController

    init() {
        // Ignore SIGPIPE so broken pipes from kiro-cli don't kill the app
        signal(SIGPIPE, SIG_IGN)
        Theme.registerBundledFonts()
        UserDefaults.standard.register(defaults: ["hideSyntax": true])
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: updaterDelegate,
            userDriverDelegate: nil
        )
    }

    private var templatesSortedForMenu: [SavedTemplate] {
        templateStore.templates.sorted { firstTemplate, secondTemplate in
            switch (firstTemplate.shortcutSlot, secondTemplate.shortcutSlot) {
            case let (firstSlot?, secondSlot?):
                if firstSlot != secondSlot { return firstSlot < secondSlot }
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                break
            }
            return firstTemplate.name.localizedCaseInsensitiveCompare(
                secondTemplate.name
            ) == .orderedAscending
        }
    }

    private func postTemplateInsertion(for template: SavedTemplate) {
        NotificationCenter.default.post(
            name: .insertTemplate,
            object: nil,
            userInfo: ["templateIdentifier": template.identifier.uuidString]
        )
    }

    private func templateInsertButton(for template: SavedTemplate) -> some View {
        Button("Insert \(template.name)") {
            postTemplateInsertion(for: template)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(linkStore)
                .environment(templateStore)
                .onAppear { appDelegate.store = store }
        }
        .defaultSize(width: 1200, height: 800)
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .appSettings) {
                SettingsLink()
            }
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
            CommandGroup(replacing: .newItem) {
                Button("New Draft") { store.newDraft() }
                    .keyboardShortcut("n")
                Button("New Tab") { store.newDraft() }
                    .keyboardShortcut("t")
            }
            CommandGroup(after: .newItem) {
                Button("New Meeting Note") {
                    store.showMeetingNoteModal()
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                Divider()
                Button("Open Workspace...") { store.pickWorkspace() }
                    .keyboardShortcut("o")
                Button("Save") { store.save() }
                    .keyboardShortcut("s")
                Button("Export as Word Document...") { store.exportAsDocx() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(store.openFiles.isEmpty)
                Divider()
                Button("Close Tab") { store.closeCurrentTab() }
                    .keyboardShortcut("w")
            }
            CommandGroup(after: .sidebar) {
                Button("Toggle Sidebar") {
                    store.toggleSidebar()
                }
                .keyboardShortcut("\\", modifiers: .command)

                Button("Toggle Chat") {
                    store.toggleChatForCurrentTab()
                }
                .keyboardShortcut("j")

                Button("Toggle Chat (Terminal)") {
                    store.toggleChatForCurrentTab()
                }
                .keyboardShortcut("`", modifiers: .control)
            }
            CommandGroup(after: .toolbar) {
                ForEach(1...9, id: \.self) { tabNum in
                    Button("Tab \(tabNum)") { store.switchTo(tabNum - 1) }
                        .keyboardShortcut(KeyEquivalent(Character("\(tabNum)")), modifiers: .command)
                }
            }
            CommandGroup(after: .textFormatting) {
                Button("Go to File") {
                    store.showFileLauncherModal()
                }
                .keyboardShortcut("p")

                Button("Tag Browser") {
                    store.showTagBrowserModal()
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])

                Button("People Browser") {
                    store.showPeopleBrowserModal()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])

                Button("Toggle Backlinks") {
                    store.toggleBacklinks()
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])

                Button("Daily Notes") {
                    store.activateDailyNotes()
                }
                .keyboardShortcut("d")

                Button("Kanban Board") {
                    store.showKanbanModal()
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            }

            CommandMenu("Templates") {
                if templatesSortedForMenu.isEmpty {
                    Button("Add templates in Settings") {}
                        .disabled(true)
                } else {
                    ForEach(templatesSortedForMenu) { template in
                        if let shortcutSlot = template.shortcutSlot {
                            templateInsertButton(for: template)
                            .keyboardShortcut(
                                KeyEquivalent(Character("\(shortcutSlot)")),
                                modifiers: [.command, .option]
                            )
                        } else {
                            templateInsertButton(for: template)
                        }
                    }
                }
            }
        }

        Settings {
            SettingsView()
                .environment(store)
                .environment(templateStore)
        }

        Window("Settings", id: "synth-settings-window") {
            SettingsView()
                .environment(store)
                .environment(templateStore)
        }
        .defaultSize(width: 720, height: 560)
    }
}
