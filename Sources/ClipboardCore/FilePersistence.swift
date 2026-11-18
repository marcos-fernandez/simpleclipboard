import Foundation
import os

public final class FilePersistence: HistoryPersistence {
    private static let logger = Logger(subsystem: Config.bundleID, category: "FilePersistence")

    private let historyURL: URL
    private let backupURL: URL
    private let tagsURL: URL
    private let tagsBackupURL: URL
    private let imagesDirectory: URL
    private let fileManager = FileManager.default
    /// Files that exist but could not be read nor moved aside (see `moveAside`).
    private var unsafeToSave: Set<URL> = []

    public init(directory: URL) {
        historyURL = directory.appendingPathComponent("history.json")
        backupURL = directory.appendingPathComponent("history.json.bak")
        tagsURL = directory.appendingPathComponent("tags.json")
        tagsBackupURL = directory.appendingPathComponent("tags.json.bak")
        imagesDirectory = directory.appendingPathComponent("images", isDirectory: true)
        do {
            try fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        } catch {
            Self.logger.error("Cannot create storage directory: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func load() -> [ClipItem] {
        loadArray(from: historyURL, movingCorruptTo: backupURL)
    }

    public func save(_ items: [ClipItem]) {
        saveArray(items, to: historyURL)
    }

    public func loadTags() -> [Tag] {
        loadArray(from: tagsURL, movingCorruptTo: tagsBackupURL)
    }

    public func saveTags(_ tags: [Tag]) {
        saveArray(tags, to: tagsURL)
    }

    public func writeImage(_ data: Data, named name: String) throws {
        try data.write(to: imagesDirectory.appendingPathComponent(name), options: .atomic)
    }

    public func readImage(named name: String) -> Data? {
        try? Data(contentsOf: imagesDirectory.appendingPathComponent(name))
    }

    public func deleteImages(notIn keep: Set<String>) {
        let names = (try? fileManager.contentsOfDirectory(atPath: imagesDirectory.path)) ?? []
        for name in names where !keep.contains(name) {
            try? fileManager.removeItem(at: imagesDirectory.appendingPathComponent(name))
        }
    }

    /// A missing file means nothing is stored yet. A file that exists but cannot be read or decoded is moved aside
    /// (`movingCorruptTo` or a unique sibling, never over an earlier one) so the app starts empty instead of failing,
    /// and the next save does not overwrite the user's data.
    private func loadArray<Element: Decodable>(from url: URL, movingCorruptTo backup: URL) -> [Element] {
        guard fileManager.fileExists(atPath: url.path) else {
            unsafeToSave.remove(url)
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            let elements = try JSONDecoder().decode([Element].self, from: data)
            unsafeToSave.remove(url)
            return elements
        } catch {
            let nsError = error as NSError
            Self.logger.error("\(url.lastPathComponent, privacy: .public) is unreadable (\(nsError.domain, privacy: .public) \(nsError.code, privacy: .public)), moving it aside")
            moveAside(url, preferring: backup)
            return []
        }
    }

    /// If the file cannot be moved, saving to its path is refused until a later load succeeds: an empty history
    /// written over it would destroy what the user had.
    private func moveAside(_ url: URL, preferring backup: URL) {
        let target = fileManager.fileExists(atPath: backup.path)
            ? uniqueSibling(of: backup)
            : backup
        do {
            try fileManager.moveItem(at: url, to: target)
            Self.logger.notice("Moved \(url.lastPathComponent, privacy: .public) to \(target.lastPathComponent, privacy: .public)")
        } catch {
            let nsError = error as NSError
            Self.logger.fault("Cannot move \(url.lastPathComponent, privacy: .public) aside (\(nsError.domain, privacy: .public) \(nsError.code, privacy: .public)), not saving over it")
            unsafeToSave.insert(url)
        }
    }

    /// `<name>-yyyyMMdd-HHmmss`, plus a random suffix when that is taken too, so an earlier backup is never deleted.
    private func uniqueSibling(of url: URL) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamped = url.deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent)-\(formatter.string(from: Date()))")
        guard fileManager.fileExists(atPath: stamped.path) else {
            return stamped
        }
        return stamped.deletingLastPathComponent()
            .appendingPathComponent("\(stamped.lastPathComponent)-\(UUID().uuidString.prefix(8))")
    }

    private func saveArray<Element: Encodable>(_ elements: [Element], to url: URL) {
        guard !unsafeToSave.contains(url) else {
            Self.logger.error("Not saving \(url.lastPathComponent, privacy: .public): the unreadable file is still there")
            return
        }
        do {
            let data = try JSONEncoder().encode(elements)
            try data.write(to: url, options: .atomic)
        } catch {
            Self.logger.error("Cannot save \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
