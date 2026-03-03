import SwiftUI
import UniformTypeIdentifiers

struct DocxExportDocument: FileDocument {
    // swiftlint:disable:next force_unwrapping
    static var readableContentTypes: [UTType] { [UTType(filenameExtension: "docx")!] }
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
