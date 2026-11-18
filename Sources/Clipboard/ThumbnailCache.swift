import AppKit
import ClipboardCore
import ImageIO

/// Decoded thumbnails by content hash, so moving through the strip does not re-read PNGs from disk.
/// Concealed images are never cached: they must disappear when they expire.
/// Display only: pasting reads the full-size data from the store, never this cache.
@MainActor
enum ThumbnailCache {
    /// Cards are 220×220 pt; twice that covers Retina screens.
    private static let maxPixelSize = 440
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        // About 0.8 MB per decoded thumbnail at most, so roughly 40 MB in the worst case.
        cache.countLimit = 50
        return cache
    }()

    static func image(for item: ClipItem, store: HistoryStore) -> NSImage? {
        guard !item.isConcealed else {
            return store.imageData(for: item).flatMap(thumbnail(from:))
        }
        let key = item.contentHash as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let image = store.imageData(for: item).flatMap(thumbnail(from:)) else {
            return nil
        }
        cache.setObject(image, forKey: key)
        return image
    }

    /// Decodes straight to the thumbnail size, without ever holding the full-size bitmap.
    private static func thumbnail(from data: Data) -> NSImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: .zero)
    }
}
