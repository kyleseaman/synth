import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var store: DocumentStore?
    
    func applicationWillResignActive(_ notification: Notification) {
        store?.saveAll()
    }
}

@main
struct SynthApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = DocumentStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
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
            CommandGroup(replacing: .textFormatting) {
                Button("Go to File") {
                    NotificationCenter.default.post(name: .showFileLauncher, object: nil)
                }
                .keyboardShortcut("p")
            }
        }
    }
}
