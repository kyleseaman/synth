import Foundation
import AppKit
import ImageIO

final class WorkspaceImageLoader: @unchecked Sendable {
    static let shared = WorkspaceImageLoader()

    private let decodeQueue = DispatchQueue(
        label: "synth.workspace-image-loader.decode",
        qos: .userInitiated,
        attributes: .concurrent
    )
    private let stateQueue = DispatchQueue(label: "synth.workspace-image-loader.state")
    private let imageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 100  // Max 100 images
        cache.totalCostLimit = 100 * 1024 * 1024  // ~100MB
        return cache
    }()
    private var inFlight: [String: [(NSImage?) -> Void]] = [:]

    private init() {}

    func cachedImage(at imageURL: URL, maxSize: NSSize) -> NSImage? {
        let cacheKey = key(for: imageURL, maxSize: maxSize)
        return stateQueue.sync {
            imageCache.object(forKey: cacheKey as NSString)
        }
    }

    func loadImage(at imageURL: URL, maxSize: NSSize, completion: @escaping (NSImage?) -> Void) {
        let cacheKey = key(for: imageURL, maxSize: maxSize)

        if let cached = cachedImage(at: imageURL, maxSize: maxSize) {
            completion(cached)
            return
        }

        var shouldStartDecode = false
        stateQueue.sync {
            if var callbacks = inFlight[cacheKey] {
                callbacks.append(completion)
                inFlight[cacheKey] = callbacks
            } else {
                inFlight[cacheKey] = [completion]
                shouldStartDecode = true
            }
        }

        guard shouldStartDecode else { return }

        decodeQueue.async {
            let decoded = Self.decodeImage(at: imageURL, maxSize: maxSize)

            let callbacks: [(NSImage?) -> Void] = self.stateQueue.sync {
                if let decoded {
                    self.imageCache.setObject(decoded, forKey: cacheKey as NSString)
                }
                return self.inFlight.removeValue(forKey: cacheKey) ?? []
            }

            DispatchQueue.main.async {
                callbacks.forEach { callback in
                    callback(decoded)
                }
            }
        }
    }

    private func key(for imageURL: URL, maxSize: NSSize) -> String {
        let width = Int(maxSize.width.rounded())
        let height = Int(maxSize.height.rounded())
        return "\(imageURL.path)#\(width)x\(height)"
    }

    private static func decodeImage(at imageURL: URL, maxSize: NSSize) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil) else { return nil }

        let maxPixelSize = max(Int(maxSize.width), Int(maxSize.height))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(maxPixelSize, 1),
            kCGImageSourceShouldCacheImmediately: true
        ]

        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else { return nil }

        let imageSize = NSSize(width: thumbnail.width, height: thumbnail.height)
        return NSImage(cgImage: thumbnail, size: imageSize)
    }
}
