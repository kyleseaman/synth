import Cocoa

struct Document {
    let url: URL
    var content: NSAttributedString
    var isDirty: Bool = false

    static func load(from url: URL) -> Document? {
        // Guard against very large files
        let maxFileSize: UInt64 = 50 * 1024 * 1024 // 50MB
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let fileSize = attrs[.size] as? UInt64,
           fileSize > maxFileSize {
            print("File too large to open: \(url.lastPathComponent) (\(fileSize / 1024 / 1024)MB)")
            return nil
        }

        let ext = url.pathExtension.lowercased()
        let content: NSAttributedString

        switch ext {
        case "docx":
            let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
                .documentType: NSAttributedString.DocumentType.officeOpenXML
            ]
            guard let attrStr = try? NSAttributedString(url: url, options: options, documentAttributes: nil)
            else { return nil }
            content = attrStr
        case "md":
            let raw = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            content = MarkdownFormat().render(raw)
        default:
            let raw = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            content = NSAttributedString(
                string: raw,
                attributes: [.font: Theme.editorFont, .foregroundColor: NSColor.textColor]
            )
        }

        return Document(url: url, content: content)
    }

    func save(_ content: NSAttributedString) throws {
        let ext = url.pathExtension.lowercased()
        if ext == "docx" {
            let range = NSRange(location: 0, length: content.length)
            let attrs: [NSAttributedString.DocumentAttributeKey: Any] = [
                .documentType: NSAttributedString.DocumentType.officeOpenXML
            ]
            let data = try content.data(from: range, documentAttributes: attrs)
            try data.write(to: url)
        } else {
            try content.string.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
