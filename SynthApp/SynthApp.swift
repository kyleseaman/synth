import SwiftUI
import AppKit

@main
struct SynthApp: App {
    @StateObject private var store = DocumentStore()
    
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
        }
    }
}
