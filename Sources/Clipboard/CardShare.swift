import AppKit
import ClipboardCore

/// What a card gives to the system's share menu.
@MainActor
enum CardShare {
    /// Whether the card can be shared, without reading its image from the disk: asked on every pass of the view
    /// and every time the menu of a card opens. An image counts as readable while the card has it to draw.
    static func canShare(_ item: ClipItem, store: HistoryStore) -> Bool {
        item.canBeShared(imageIsReadable: ThumbnailCache.image(for: item, store: store) != nil)
    }

    /// The text of the card, or its image at full size and not the thumbnail the card draws. Nothing for a card
    /// that cannot be shared, nor for an image whose file is gone since the card was drawn.
    static func items(for item: ClipItem, store: HistoryStore) -> [Any] {
        guard canShare(item, store: store) else {
            return []
        }
        if item.kind == .image {
            return store.imageData(for: item).flatMap(NSImage.init(data:)).map { [$0] } ?? []
        }
        return item.text.map { [$0] } ?? []
    }
}
