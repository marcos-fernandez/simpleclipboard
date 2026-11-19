import AppKit
import ClipboardCore
import ImageIO

/// Decoded thumbnails by content hash, so moving through the strip does not re-read PNGs from disk.
/// Concealed images are never decoded: their cards show a lock, never the image.
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
    /// Hashes whose file was missing or unreadable, so body passes do not hit the disk again for them.
    private static var misses: Set<String> = []

    /// Called when the panel opens: a missing file may since have arrived (a re-copy, or sync).
    static func forgetMisses() {
        misses.removeAll()
    }

    static func image(for item: ClipItem, store: HistoryStore) -> NSImage? {
        guard !item.isConcealed, !misses.contains(item.contentHash) else {
            return nil
        }
        let key = item.contentHash as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let image = store.imageData(for: item).flatMap(thumbnail(from:)) else {
            misses.insert(item.contentHash)
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
