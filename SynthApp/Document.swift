import Cocoa

struct Document {
    let url: URL
    var content: NSAttributedString

    static func load(from url: URL) -> Document? {
        let ext = url.pathExtension.lowercased()
        let content: NSAttributedString

        switch ext {
        case "docx":
            guard let attrStr = try? NSAttributedString(url: url, options: [.documentType: NSAttributedString.DocumentType.officeOpenXML], documentAttributes: nil) else { return nil }
            content = attrStr
        case "md":
            let raw = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            content = MarkdownRenderer.render(raw)
        default:
            let raw = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            content = NSAttributedString(string: raw, attributes: [.font: Theme.editorFont, .foregroundColor: NSColor.black])
        }

        return Document(url: url, content: content)
    }

    func save(_ content: NSAttributedString) throws {
        let ext = url.pathExtension.lowercased()
        if ext == "docx" {
            let data = try content.data(from: NSRange(location: 0, length: content.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML])
            try data.write(to: url)
        } else {
            try content.string.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
