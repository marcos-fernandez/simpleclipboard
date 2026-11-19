import Foundation

public protocol HistoryPersistence {
    /// Returns [] when nothing is stored or the stored file is unreadable.
    func load() -> [ClipItem]
    /// Returns whether the history was written.
    @discardableResult
    func save(_ items: [ClipItem]) -> Bool
    /// Returns [] when nothing is stored or the stored file is unreadable.
    func loadTags() -> [Tag]
    /// True when the last `loadTags()` found a tags file it could neither read nor recover. The items still point
    /// to those tags, which may come back (a repaired file, another Mac), so they must not be untagged.
    var tagsWereLost: Bool { get }
    func saveTags(_ tags: [Tag])
    func writeImage(_ data: Data, named name: String) throws
    func readImage(named name: String) -> Data?
    /// Removes every stored image whose name is not in `keep`.
    func deleteImages(notIn keep: Set<String>)
    /// One save of the store: the history, the tags, then the images the history no longer lists. A single call, so
    /// a persistence that writes later (`BackgroundPersistence`) keeps the three together.
    func saveHistory(_ items: [ClipItem], tags: [Tag])
}

extension HistoryPersistence {
    public func saveHistory(_ items: [ClipItem], tags: [Tag]) {
        let saved = save(items)
        saveTags(tags)
        // A history that failed to save still lists the items of the last save, images included.
        if saved {
            deleteImages(notIn: Set(items.compactMap(\.imageFileName)))
        }
    }
}
