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
}
