import Foundation
import os

public enum BackupError: Error, Equatable {
    case iCloudUnavailable
    case noBackup
    /// Backup/history.json or tags.json missing, any of its files not downloaded from iCloud yet, or an image its
    /// history lists missing from Backup/images (not downloaded yet, or already missing when it was backed up).
    case incompleteBackup
    /// No local history.json yet (fresh install).
    case nothingToBackUp
    /// Backup/history.json or tags.json cannot be decoded, or Backup/images is not a folder of files.
    case corruptBackup
    /// Local history.json or tags.json cannot be decoded, or local images/ is not a folder of files: backing them
    /// up would replace a good backup with one restore() refuses.
    case unreadableLocalData
}

/// Copies the on-disk data (history.json, tags.json, images/) to and from an iCloud Drive
/// folder. Only on-disk data is copied, so concealed items never leave the Mac.
/// Synchronous by design: call it on the main actor so the store cannot write mid-copy.
public final class BackupService {
    private static let logger = Logger(subsystem: Config.bundleID, category: "BackupService")

    private static let dataFiles = ["history.json", "tags.json"]
    private static let imagesName = "images"
    private static let backedUpNames = dataFiles + [imagesName]

    private let localDirectory: URL
    private let iCloudDriveRoot: URL
    private let backupDirectory: URL
    private let previousBackupDirectory: URL
    private let fileManager: FileManager

    public init(localDirectory: URL, iCloudDriveRoot: URL, fileManager: FileManager = .default) {
        self.localDirectory = localDirectory
        self.iCloudDriveRoot = iCloudDriveRoot
        self.fileManager = fileManager
        backupDirectory = iCloudDriveRoot
            .appendingPathComponent(Config.appName, isDirectory: true)
            .appendingPathComponent("Backup", isDirectory: true)
        previousBackupDirectory = backupDirectory.deletingLastPathComponent()
            .appendingPathComponent("Backup.old", isDirectory: true)
    }

    public var isAvailable: Bool {
        fileManager.fileExists(atPath: iCloudDriveRoot.path)
    }

    public var hasBackup: Bool {
        fileManager.fileExists(atPath: backupDirectory.path)
            || fileManager.fileExists(atPath: previousBackupDirectory.path)
    }

    /// Copies to Backup.tmp/, then swaps it in: Backup/ is renamed to Backup.old/, Backup.tmp/
    /// becomes Backup/, and Backup.old/ is deleted last. A failure at any point leaves the
    /// previous backup in place (or restorable from Backup.old/).
    public func backUp() throws {
        guard isAvailable else {
            throw BackupError.iCloudUnavailable
        }
        guard fileManager.fileExists(atPath: localDirectory.appendingPathComponent("history.json").path) else {
            throw BackupError.nothingToBackUp
        }
        recoverInterruptedBackupSwap()
        let staging = backupDirectory.deletingLastPathComponent()
            .appendingPathComponent("Backup.tmp", isDirectory: true)
        try copyData(from: localDirectory, to: staging)
        // No tags file == no tags (a v1 install has none); restore() requires both files.
        let stagedTags = staging.appendingPathComponent("tags.json")
        if !fileManager.fileExists(atPath: stagedTags.path) {
            do {
                try Data("[]".utf8).write(to: stagedTags)
            } catch {
                try? fileManager.removeItem(at: staging)
                throw error
            }
        }
        // A damaged file left in place, or a linked images folder, would replace a good backup with one restore()
        // refuses.
        guard isDecodable(staging), hasOnlyImageFiles(staging) else {
            try? fileManager.removeItem(at: staging)
            throw BackupError.unreadableLocalData
        }
        logMissingImages(staging)
        let hadBackup = fileManager.fileExists(atPath: backupDirectory.path)
        do {
            if hadBackup {
                try fileManager.moveItem(at: backupDirectory, to: previousBackupDirectory)
            }
            try fileManager.moveItem(at: staging, to: backupDirectory)
        } catch {
            if hadBackup, !fileManager.fileExists(atPath: backupDirectory.path) {
                try? fileManager.moveItem(at: previousBackupDirectory, to: backupDirectory)
            }
            try? fileManager.removeItem(at: staging)
            throw error
        }
        try? fileManager.removeItem(at: previousBackupDirectory)
    }

    /// Copies Backup/ to a temporary sibling of the local directory first; local files are
    /// only replaced once that copy succeeded. The swap moves the current local files to a
    /// `.restore.old` sibling and rolls them back if any move fails; that folder is deleted
    /// only after the whole swap succeeded. A `.restore.old` left by a crash may hold the only
    /// copy of the original data, so it is never deleted: missing local items are moved back
    /// from it and what remains is renamed to a unique `.restore.old-<date>` sibling.
    public func restore() throws {
        guard hasBackup else {
            throw BackupError.noBackup
        }
        recoverInterruptedBackupSwap()
        let parent = localDirectory.deletingLastPathComponent()
        let staging = parent
            .appendingPathComponent("\(localDirectory.lastPathComponent).restore.tmp", isDirectory: true)
        let old = leftoverRestoreDirectory
        try preserveLeftoverRestoreFolder(old)
        guard isComplete(backupDirectory) else {
            throw BackupError.incompleteBackup
        }
        try copyData(from: backupDirectory, to: staging)
        // Loading an undecodable file would start empty and delete the local images, so a
        // corrupt backup is refused before anything local is touched.
        guard isDecodable(staging) else {
            try? fileManager.removeItem(at: staging)
            throw BackupError.corruptBackup
        }
        do {
            try checkImages(staging)
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
        var movedAside: [String] = []
        var movedIn: [String] = []
        do {
            try fileManager.createDirectory(at: old, withIntermediateDirectories: true)
            for name in Self.backedUpNames {
                let target = localDirectory.appendingPathComponent(name)
                if fileManager.fileExists(atPath: target.path) {
                    try fileManager.moveItem(at: target, to: old.appendingPathComponent(name))
                    movedAside.append(name)
                }
            }
            for name in Self.backedUpNames {
                let source = staging.appendingPathComponent(name)
                if fileManager.fileExists(atPath: source.path) {
                    try fileManager.moveItem(at: source, to: localDirectory.appendingPathComponent(name))
                    movedIn.append(name)
                }
            }
        } catch {
            for name in movedIn {
                try? fileManager.removeItem(at: localDirectory.appendingPathComponent(name))
            }
            for name in movedAside {
                try? fileManager.moveItem(
                    at: old.appendingPathComponent(name), to: localDirectory.appendingPathComponent(name)
                )
            }
            try? fileManager.removeItem(at: staging)
            throw error
        }
        try? fileManager.removeItem(at: old)
        try? fileManager.removeItem(at: staging)
    }

    /// Call at launch before the store loads: a restore interrupted by a crash leaves the local data in a
    /// `.restore.old` folder (see `restore()`), and the store would start empty and delete the images.
    public func recoverInterruptedRestore() throws {
        try preserveLeftoverRestoreFolder(leftoverRestoreDirectory)
    }

    private var leftoverRestoreDirectory: URL {
        localDirectory.deletingLastPathComponent()
            .appendingPathComponent("\(localDirectory.lastPathComponent).restore.old", isDirectory: true)
    }

    /// True when local data was modified after `date` (always true when `date` is nil),
    /// false when there is nothing to back up.
    public func hasChanges(since date: Date?) -> Bool {
        let history = localDirectory.appendingPathComponent("history.json")
        guard fileManager.fileExists(atPath: history.path) else {
            return false
        }
        guard let date else {
            return true
        }
        let paths = Self.backedUpNames.map { localDirectory.appendingPathComponent($0).path }
        return paths.contains { path in
            let modified = (try? fileManager.attributesOfItem(atPath: path))?[.modificationDate] as? Date
            return modified.map { $0 > date } ?? false
        }
    }

    /// Recovers a `.restore.old` folder left by an interrupted restore without deleting anything:
    /// local items that are missing are moved back, the rest is kept under a unique name.
    private func preserveLeftoverRestoreFolder(_ old: URL) throws {
        guard fileManager.fileExists(atPath: old.path) else {
            return
        }
        for name in Self.backedUpNames {
            let target = localDirectory.appendingPathComponent(name)
            let leftover = old.appendingPathComponent(name)
            if !fileManager.fileExists(atPath: target.path), fileManager.fileExists(atPath: leftover.path) {
                try fileManager.moveItem(at: leftover, to: target)
            }
        }
        let remaining = try fileManager.contentsOfDirectory(atPath: old.path)
        if remaining.isEmpty {
            try fileManager.removeItem(at: old)
            return
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        var kept = old.deletingLastPathComponent()
            .appendingPathComponent("\(old.lastPathComponent)-\(formatter.string(from: Date()))", isDirectory: true)
        if fileManager.fileExists(atPath: kept.path) {
            kept = kept.deletingLastPathComponent()
                .appendingPathComponent(
                    "\(kept.lastPathComponent)-\(UUID().uuidString.prefix(8))", isDirectory: true
                )
        }
        try fileManager.moveItem(at: old, to: kept)
        Self.logger.notice("Kept leftover \(old.lastPathComponent, privacy: .public) as \(kept.lastPathComponent, privacy: .public)")
    }

    /// A backup is complete when both JSON files exist and every file is downloaded. Before
    /// macOS 14 an undownloaded image is a ".name.icloud" placeholder; from macOS 14 on it keeps
    /// its name, so the iCloud downloading status is checked too (nil outside iCloud Drive).
    /// Undownloaded files are requested here, so copying them later does not block on the download.
    /// backUp() always writes both files, so a real backup has both.
    private func isComplete(_ backup: URL) -> Bool {
        for name in Self.dataFiles {
            guard fileManager.fileExists(atPath: backup.appendingPathComponent(name).path) else {
                return false
            }
        }
        let images = backup.appendingPathComponent(Self.imagesName, isDirectory: true)
        let names = (try? fileManager.contentsOfDirectory(atPath: images.path)) ?? []
        if names.contains(where: { $0.hasPrefix(".") && $0.hasSuffix(".icloud") }) {
            return false
        }
        let files = Self.dataFiles.map { backup.appendingPathComponent($0) }
            + names.map { images.appendingPathComponent($0) }
        var isDownloaded = true
        for file in files where !isCurrent(file) {
            try? fileManager.startDownloadingUbiquitousItem(at: file)
            isDownloaded = false
        }
        return isDownloaded
    }

    /// False only for an iCloud item whose local copy is missing or outdated.
    private func isCurrent(_ file: URL) -> Bool {
        // A fresh URL: URL caches resource values.
        let fresh = URL(fileURLWithPath: file.path)
        let values = try? fresh.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
        guard let status = values?.ubiquitousItemDownloadingStatus else {
            return true
        }
        return status == .current
    }

    /// The staged JSON files decode as the store will load them.
    private func isDecodable(_ staging: URL) -> Bool {
        let decoder = JSONDecoder()
        guard let history = try? Data(contentsOf: staging.appendingPathComponent("history.json")),
              let tags = try? Data(contentsOf: staging.appendingPathComponent("tags.json")) else {
            return false
        }
        return (try? decoder.decode([ClipItem].self, from: history)) != nil
            && (try? decoder.decode([Tag].self, from: tags)) != nil
    }

    /// The local images folder is replaced by the staged one, and every save deletes from it what the history does
    /// not name: a link there would point that at another folder, and a missing image would be lost for good.
    /// So images/ must be a real folder holding only files (all backUp() ever copies), with every image the
    /// history lists (`incompleteBackup`: iCloud may not have listed it yet, or the backup was made from a history
    /// whose image file was already missing, which `logMissingImages` reports).
    private func checkImages(_ staging: URL) throws {
        guard hasOnlyImageFiles(staging) else {
            throw BackupError.corruptBackup
        }
        let names = try fileManager.contentsOfDirectory(
            atPath: staging.appendingPathComponent(Self.imagesName, isDirectory: true).path
        )
        let history = try Data(contentsOf: staging.appendingPathComponent("history.json"))
        let listed = try JSONDecoder().decode([ClipItem].self, from: history).compactMap(\.imageFileName)
        guard Set(listed).isSubset(of: names) else {
            throw BackupError.incompleteBackup
        }
    }

    /// A history that lists an image missing from images/ is still backed up (refusing would leave no newer backup
    /// at all), but `restore()` will refuse that backup as incomplete: logged so the cause can be found.
    private func logMissingImages(_ staging: URL) {
        let images = staging.appendingPathComponent(Self.imagesName, isDirectory: true)
        guard let names = try? fileManager.contentsOfDirectory(atPath: images.path),
              let history = try? Data(contentsOf: staging.appendingPathComponent("history.json")),
              let items = try? JSONDecoder().decode([ClipItem].self, from: history) else {
            return
        }
        let missing = Set(items.compactMap(\.imageFileName)).subtracting(names)
        if !missing.isEmpty {
            Self.logger.error("Backing up a history that lists \(missing.count, privacy: .public) missing images; this backup cannot be restored")
        }
    }

    /// images/ is a real folder (not a link) holding only files.
    private func hasOnlyImageFiles(_ data: URL) -> Bool {
        let images = data.appendingPathComponent(Self.imagesName, isDirectory: true)
        guard fileType(images) == .typeDirectory,
              let names = try? fileManager.contentsOfDirectory(atPath: images.path) else {
            return false
        }
        return names.allSatisfy { fileType(images.appendingPathComponent($0)) == .typeRegular }
    }

    /// Not following a symbolic link.
    private func fileType(_ url: URL) -> FileAttributeType? {
        (try? fileManager.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType
    }

    /// A crash between the two renames of backUp() leaves only Backup.old/: put it back.
    /// If Backup/ exists, a leftover Backup.old/ is just garbage from a finished swap.
    private func recoverInterruptedBackupSwap() {
        guard fileManager.fileExists(atPath: previousBackupDirectory.path) else {
            return
        }
        if fileManager.fileExists(atPath: backupDirectory.path) {
            try? fileManager.removeItem(at: previousBackupDirectory)
        } else {
            try? fileManager.moveItem(at: previousBackupDirectory, to: backupDirectory)
        }
    }

    /// Replaces `destination` with a copy of the data files of `source`; always creates images/.
    /// Removes `destination` again if anything fails.
    private func copyData(from source: URL, to destination: URL) throws {
        do {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            for name in Self.backedUpNames {
                let from = source.appendingPathComponent(name)
                if fileManager.fileExists(atPath: from.path) {
                    try fileManager.copyItem(at: from, to: destination.appendingPathComponent(name))
                }
            }
            let images = destination.appendingPathComponent(Self.imagesName, isDirectory: true)
            if !fileManager.fileExists(atPath: images.path) {
                try fileManager.createDirectory(at: images, withIntermediateDirectories: true)
            }
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
    }
}
