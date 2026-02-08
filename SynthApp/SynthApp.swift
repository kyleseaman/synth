import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var store: DocumentStore?
    var hotkeyMonitor: GlobalHotkeyMonitor?

    func applicationWillResignActive(_ notification: Notification) {
        store?.saveAll()
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

    init() {
        // Ignore SIGPIPE so broken pipes from kiro-cli don't kill the app
        signal(SIGPIPE, SIG_IGN)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(linkStore)
                .onAppear { appDelegate.store = store }
        }
        .defaultSize(width: 1200, height: 800)
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Draft") { store.newDraft() }
                    .keyboardShortcut("n")
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
            }
        }

        Settings {
            SettingsView()
                .environment(store)
        }
    }
}
