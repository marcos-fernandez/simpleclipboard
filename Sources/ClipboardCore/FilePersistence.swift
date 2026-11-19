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
    /// Files found unreadable at their last load with no usable copy of the last save (see `recoverCopy`).
    private var unrecovered: Set<URL> = []

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

    @discardableResult
    public func save(_ items: [ClipItem]) -> Bool {
        saveArray(items, to: historyURL)
    }

    public func loadTags() -> [Tag] {
        loadArray(from: tagsURL, movingCorruptTo: tagsBackupURL)
    }

    public var tagsWereLost: Bool {
        unrecovered.contains(tagsURL)
    }

    public func saveTags(_ tags: [Tag]) {
        saveArray(tags, to: tagsURL)
    }

    public func writeImage(_ data: Data, named name: String) throws {
        guard let url = imageURL(named: name) else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        try data.write(to: url, options: .atomic)
    }

    public func readImage(named name: String) -> Data? {
        imageURL(named: name).flatMap { try? Data(contentsOf: $0) }
    }

    /// Names come from history.json, which may come from a backup: only a plain file name stays inside images/.
    private func imageURL(named name: String) -> URL? {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/") else {
            return nil
        }
        return imagesDirectory.appendingPathComponent(name)
    }

    public func deleteImages(notIn keep: Set<String>) {
        // The history that could not be read is still in place and may point to these images.
        guard !unsafeToSave.contains(historyURL) else {
            return
        }
        // A linked images folder points somewhere else (a restore may bring one): nothing there is ours.
        let imagesType = (try? fileManager.attributesOfItem(atPath: imagesDirectory.path))?[.type] as? FileAttributeType
        guard imagesType == .typeDirectory else {
            Self.logger.error("Not deleting unused images: the images folder is not a plain folder")
            return
        }
        let names = (try? fileManager.contentsOfDirectory(atPath: imagesDirectory.path)) ?? []
        for name in names where !keep.contains(name) {
            let url = imagesDirectory.appendingPathComponent(name)
            // Only ever a file the app wrote: a folder or a link inside is not an image.
            if isRegularFile(url) {
                try? fileManager.removeItem(at: url)
            }
        }
    }

    /// A missing file means nothing is stored yet. A file that exists but cannot be decoded (or is not a regular
    /// file) is moved aside (`movingCorruptTo` or a unique sibling, never over an earlier one) so the app starts
    /// instead of failing and the next save does not overwrite the user's data. A regular file that cannot be read
    /// stays in place and is not saved over. Either way the copy of the last save is loaded in its place
    /// (`keepCopy`), or nothing when there is no such copy.
    private func loadArray<Element: Decodable>(from url: URL, movingCorruptTo backup: URL) -> [Element] {
        guard fileManager.fileExists(atPath: url.path) else {
            unsafeToSave.remove(url)
            unrecovered.remove(url)
            return []
        }
        do {
            let data: Data
            do {
                data = try Data(contentsOf: url)
            } catch where isRegularFile(url) {
                // A read error says nothing about the contents: the file stays, and is not saved over.
                let nsError = error as NSError
                Self.logger.error("Cannot read \(url.lastPathComponent, privacy: .public) (\(nsError.domain, privacy: .public) \(nsError.code, privacy: .public)), leaving it in place")
                unsafeToSave.insert(url)
                return recoverCopy(of: url)
            }
            let elements = try JSONDecoder().decode([Element].self, from: data)
            unsafeToSave.remove(url)
            unrecovered.remove(url)
            return elements
        } catch {
            let nsError = error as NSError
            Self.logger.error("\(url.lastPathComponent, privacy: .public) is unreadable (\(nsError.domain, privacy: .public) \(nsError.code, privacy: .public)), moving it aside")
            moveAside(url, preferring: backup)
            return recoverCopy(of: url)
        }
    }

    /// The copy is also put back in the file's place: the store may not save before the app quits, and a missing
    /// file would then be read as "nothing stored" on the next launch.
    private func recoverCopy<Element: Decodable>(of url: URL) -> [Element] {
        let previous = previousURL(of: url)
        guard let data = try? Data(contentsOf: previous),
              let elements = try? JSONDecoder().decode([Element].self, from: data) else {
            unrecovered.insert(url)
            return []
        }
        unrecovered.remove(url)
        Self.logger.notice("Recovered \(url.lastPathComponent, privacy: .public) from \(previous.lastPathComponent, privacy: .public)")
        if !unsafeToSave.contains(url) {
            do {
                try fileManager.copyItem(at: previous, to: url)
            } catch {
                Self.logger.error("Cannot put \(previous.lastPathComponent, privacy: .public) back: \(error.localizedDescription, privacy: .public)")
            }
        }
        return elements
    }

    /// Every save leaves a second copy of the file as `<name>.prev`, so a file found damaged later is recovered
    /// instead of starting empty. Copied after the write, not before: a copy of the earlier contents would keep on
    /// disk what the save has just removed (a deleted item, a value turned concealed), and recovering it would bring
    /// that back.
    private func keepCopy(of url: URL) {
        let previous = previousURL(of: url)
        do {
            if fileManager.fileExists(atPath: previous.path) {
                try fileManager.removeItem(at: previous)
            }
            try fileManager.copyItem(at: url, to: previous)
        } catch {
            Self.logger.error("Cannot keep a copy of \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Not following a symbolic link: a link is not one of our files.
    private func isRegularFile(_ url: URL) -> Bool {
        (try? fileManager.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType == .typeRegular
    }

    private func previousURL(of url: URL) -> URL {
        url.appendingPathExtension("prev")
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

    @discardableResult
    private func saveArray<Element: Encodable>(_ elements: [Element], to url: URL) -> Bool {
        guard !unsafeToSave.contains(url) else {
            Self.logger.error("Not saving \(url.lastPathComponent, privacy: .public): the unreadable file is still there")
            return false
        }
        do {
            let data = try JSONEncoder().encode(elements)
            try data.write(to: url, options: .atomic)
            keepCopy(of: url)
            return true
        } catch {
            Self.logger.error("Cannot save \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
