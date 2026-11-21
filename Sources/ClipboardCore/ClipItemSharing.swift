extension ClipItem {
    /// Whether the item can be given to the system's share menu. Never what was copied from a secured app: it is
    /// hidden on its card, and sharing it would show it. An image needs its file, and a text something in it.
    /// `imageIsReadable`: whether the image of an image item could be read; it says nothing about a text one.
    public func canBeShared(imageIsReadable: Bool) -> Bool {
        guard !isConcealed else {
            return false
        }
        return kind == .image
            ? imageIsReadable
            : !(text ?? "").isEmpty
    }
}
