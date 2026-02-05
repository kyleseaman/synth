import Cocoa

struct Theme {
    static let uiFont = NSFont(name: "Inter", size: 13) ?? NSFont.systemFont(ofSize: 13)
    static let editorFont = NSFont(name: "Newsreader", size: 18)
        ?? NSFont(name: "Georgia", size: 18)
        ?? NSFont.systemFont(ofSize: 18)
    static let monoFont = NSFont(name: "JetBrainsMono-Regular", size: 12)
        ?? NSFont(name: "JetBrains Mono", size: 12)
        ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    static let offWhite = NSColor(red: 0.98, green: 0.98, blue: 0.97, alpha: 1.0)
    static let offBlack = NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
}
