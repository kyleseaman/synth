import SwiftUI
import UniformTypeIdentifiers

struct DocxExportDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        if let docx = UTType(filenameExtension: "docx") {
            return [docx]
        }
        return [.data]
    }
    static var writableContentTypes: [UTType] { readableContentTypes }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
