import AppKit
import ClipboardCore

/// Decoded images by content hash, so moving through the strip does not re-read PNGs from disk.
/// Concealed images are never cached: they must disappear when they expire.
@MainActor
enum ThumbnailCache {
    private static let cache = NSCache<NSString, NSImage>()

    static func image(for item: ClipItem, store: HistoryStore) -> NSImage? {
        guard !item.isConcealed else {
            return store.imageData(for: item).flatMap(NSImage.init(data:))
        }
        let key = item.contentHash as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let image = store.imageData(for: item).flatMap(NSImage.init(data:)) else {
            return nil
        }
        cache.setObject(image, forKey: key)
        return image
    }
}
