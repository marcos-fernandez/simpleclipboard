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

    /// A corrupt file is moved to `backup` so the app starts empty instead of failing.
    private func loadArray<Element: Decodable>(from url: URL, movingCorruptTo backup: URL) -> [Element] {
        guard let data = try? Data(contentsOf: url) else {
            return []
        }
        do {
            return try JSONDecoder().decode([Element].self, from: data)
        } catch {
            Self.logger.error("\(url.lastPathComponent, privacy: .public) is corrupt, moving it to .bak: \(error.localizedDescription, privacy: .public)")
            try? fileManager.removeItem(at: backup)
            try? fileManager.moveItem(at: url, to: backup)
            return []
        }
    }

    private func saveArray<Element: Encodable>(_ elements: [Element], to url: URL) {
        do {
            let data = try JSONEncoder().encode(elements)
            try data.write(to: url, options: .atomic)
        } catch {
            Self.logger.error("Cannot save \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
