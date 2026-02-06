import Cocoa

struct Theme {
    static let uiFont = NSFont(name: "Inter", size: 13) ?? NSFont.systemFont(ofSize: 13)
    static let editorFont = NSFont(name: "Newsreader", size: 18)
        ?? NSFont(name: "Georgia", size: 18)
        ?? NSFont.systemFont(ofSize: 18)
    static let monoFont = NSFont(name: "JetBrainsMono-Regular", size: 12)
        ?? NSFont(name: "JetBrains Mono", size: 12)
        ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    static let offWhite = NSColor.textBackgroundColor
    static let offBlack = NSColor.textColor
}
