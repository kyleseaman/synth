import SwiftUI
import AppKit

@main
struct SynthApp: App {
    @StateObject private var store = DocumentStore()

    init() {
        // Ignore SIGPIPE so broken pipes from kiro-cli don't kill the app
        signal(SIGPIPE, SIG_IGN)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Draft") { store.newDraft() }
                    .keyboardShortcut("n")
            }
            CommandGroup(after: .newItem) {
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
                    NotificationCenter.default.post(name: .toggleSidebar, object: nil)
                }
                .keyboardShortcut("\\", modifiers: .command)

                Button("Toggle Chat") {
                    NotificationCenter.default.post(name: .toggleChat, object: nil)
                }
                .keyboardShortcut("j")
            }
            CommandGroup(after: .toolbar) {
                ForEach(1...9, id: \.self) { tabNum in
                    Button("Tab \(tabNum)") { store.switchTo(tabNum - 1) }
                        .keyboardShortcut(KeyEquivalent(Character("\(tabNum)")), modifiers: .command)
                }
            }
            CommandGroup(after: .textFormatting) {
                Button("Go to File") {
                    NotificationCenter.default.post(name: .showFileLauncher, object: nil)
                }
                .keyboardShortcut("p")
            }
        }
    }
}
