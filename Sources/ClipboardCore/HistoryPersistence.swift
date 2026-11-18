import Foundation

public protocol HistoryPersistence {
    /// Returns [] when nothing is stored or the stored file is unreadable.
    func load() -> [ClipItem]
    func save(_ items: [ClipItem])
    /// Returns [] when nothing is stored or the stored file is unreadable.
    func loadTags() -> [Tag]
    func saveTags(_ tags: [Tag])
    func writeImage(_ data: Data, named name: String) throws
    func readImage(named name: String) -> Data?
    /// Removes every stored image whose name is not in `keep`.
    func deleteImages(notIn keep: Set<String>)
}
