import Foundation
import AppKit

struct StoredMediaAsset {
    let fileURL: URL
    let relativePath: String
}

enum MediaManagerError: Error {
    case imageEncodingFailed
}

enum MediaManager {
    private static let supportedExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "gif", "webp"
    ]

    private static let filenameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    static func saveScreenshotImage(
        _ image: NSImage,
        workspaceURL: URL,
        noteURL: URL,
        now: Date = Date()
    ) throws -> StoredMediaAsset {
        let fileManager = FileManager.default
        let mediaDirectory = workspaceURL.appendingPathComponent("media", isDirectory: true)
        try fileManager.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)

        guard let imageData = image.pngDataRepresentation else {
            throw MediaManagerError.imageEncodingFailed
        }

        let timestamp = filenameFormatter.string(from: now)
        let baseName = "screenshot-\(timestamp)"
        var suffixNumber = 1
        var fileName = "\(baseName).png"
        var fileURL = mediaDirectory.appendingPathComponent(fileName)

        while fileManager.fileExists(atPath: fileURL.path) {
            suffixNumber += 1
            fileName = "\(baseName)-\(suffixNumber).png"
            fileURL = mediaDirectory.appendingPathComponent(fileName)
        }

        try imageData.write(to: fileURL, options: [.atomic])

        let noteDirectory = noteURL.deletingLastPathComponent()
        let relativePath = relativePath(from: noteDirectory, to: fileURL)
        return StoredMediaAsset(fileURL: fileURL, relativePath: relativePath)
    }

    static func screenshotURLs(in workspaceURL: URL) -> [URL] {
        let mediaDirectory = workspaceURL.appendingPathComponent("media", isDirectory: true)
        let properties: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey]

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: mediaDirectory,
            includingPropertiesForKeys: properties
        ) else { return [] }

        return contents
            .filter { mediaURL in
                guard isSupportedImageFile(mediaURL) else { return false }
                return mediaURL.deletingPathExtension()
                    .lastPathComponent
                    .lowercased()
                    .contains("screenshot")
            }
            .sorted { firstURL, secondURL in
                let firstValues = try? firstURL.resourceValues(forKeys: [.contentModificationDateKey])
                let secondValues = try? secondURL.resourceValues(forKeys: [.contentModificationDateKey])
                let firstDate = firstValues?.contentModificationDate ?? .distantPast
                let secondDate = secondValues?.contentModificationDate ?? .distantPast
                return firstDate > secondDate
            }
    }

    static func relativePath(from baseDirectoryURL: URL, to destinationURL: URL) -> String {
        let baseParts = baseDirectoryURL.standardizedFileURL.pathComponents
        let destinationParts = destinationURL.standardizedFileURL.pathComponents
        let sharedCount = sharedPathPrefixCount(first: baseParts, second: destinationParts)

        let parentSegments = Array(repeating: "..", count: baseParts.count - sharedCount)
        let destinationSegments = Array(destinationParts.dropFirst(sharedCount))
        let fullSegments = parentSegments + destinationSegments
        return fullSegments.isEmpty ? "." : fullSegments.joined(separator: "/")
    }

    static func resolvedImageURL(from path: String, baseDirectoryURL: URL?) -> URL? {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return nil }

        if let absoluteURL = URL(string: trimmedPath), absoluteURL.scheme != nil {
            return absoluteURL
        }

        guard let baseDirectoryURL else { return nil }
        return URL(fileURLWithPath: trimmedPath, relativeTo: baseDirectoryURL).standardizedFileURL
    }

    static func isSupportedImageFile(_ mediaURL: URL) -> Bool {
        let ext = mediaURL.pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else { return false }
        let isDirectory = (try? mediaURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        return !isDirectory
    }

    private static func sharedPathPrefixCount(first: [String], second: [String]) -> Int {
        let countLimit = min(first.count, second.count)
        var sharedCount = 0
        while sharedCount < countLimit && first[sharedCount] == second[sharedCount] {
            sharedCount += 1
        }
        return sharedCount
    }
}

extension NSImage {
    var pngDataRepresentation: Data? {
        guard let tiffData = tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData) else { return nil }
        return bitmapRep.representation(using: .png, properties: [:])
    }
}
