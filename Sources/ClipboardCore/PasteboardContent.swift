import Foundation

/// An image as read from the pasteboard. A TIFF is converted to PNG later, off the main thread (`CaptureQueue`).
public enum PasteboardImage: Equatable, Sendable {
    case png(Data)
    case tiff(Data)
}

/// A copy as read from the pasteboard, before any conversion.
public enum PasteboardCapture: Equatable, Sendable {
    case text(String)
    case image(PasteboardImage)
}

public enum PasteboardContent {
    /// Text wins over image (office apps put both on the pasteboard). Blank text does not: the store rejects it, so
    /// the image would never be recorded. `image` is only read when needed.
    public static func choose(text: String?, image: () -> PasteboardImage?) -> PasteboardCapture? {
        // Same blank test as `HistoryStore.add`.
        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .text(text)
        }
        return image().map(PasteboardCapture.image)
    }
}
