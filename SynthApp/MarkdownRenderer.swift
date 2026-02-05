import Cocoa

enum MarkdownRenderer {
    static func render(_ text: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let defaultAttrs: [NSAttributedString.Key: Any] = [.font: Theme.editorFont, .foregroundColor: NSColor.black]

        let lines = text.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            var attrs = defaultAttrs
            var content = line

            if line.hasPrefix("# ") {
                content = String(line.dropFirst(2))
                attrs[.font] = NSFont.systemFont(ofSize: 28, weight: .bold)
            } else if line.hasPrefix("## ") {
                content = String(line.dropFirst(3))
                attrs[.font] = NSFont.systemFont(ofSize: 22, weight: .bold)
            } else if line.hasPrefix("### ") {
                content = String(line.dropFirst(4))
                attrs[.font] = NSFont.systemFont(ofSize: 18, weight: .bold)
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                content = "• " + String(line.dropFirst(2))
            }

            let suffix = index < lines.count - 1 ? "\n" : ""
            result.append(NSAttributedString(string: content + suffix, attributes: attrs))
        }
        return result
    }
}
