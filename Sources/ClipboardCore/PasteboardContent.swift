import Foundation

public enum PasteboardContent {
    /// Text wins over image (office apps put both on the pasteboard). Blank text does not: the store rejects it, so
    /// the image would never be recorded. `image` is only read when needed.
    public static func choose(text: String?, image: () -> Data?) -> ClipContent? {
        // Same blank test as `HistoryStore.add`.
        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .text(text)
        }
        return image().map(ClipContent.image)
    }
}
