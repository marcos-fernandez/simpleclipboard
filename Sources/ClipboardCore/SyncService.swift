import Foundation
import os

public enum SyncError: Error, Equatable {
    case iCloudUnavailable
}

/// Where sync stands, for the menu.
public enum SyncStatus: Equatable, Sendable {
    case off
    case iCloudUnavailable
    case synced(Date)
    /// Another Mac publishes a newer format; its file is skipped until this Mac is updated.
    case newerVersionElsewhere
    /// This Mac's file or images could not be written; retried next round.
    case writeFailed
    /// First sync on this Mac and a file of another Mac cannot be read yet (not downloaded, or corrupt): nothing is
    /// merged or published until every file reads, or this Mac would publish its tags with IDs the other Mac does not
    /// know and both would end up with the same tag twice. Retried next round.
    case waitingForOtherMacs
}

/// This Mac's sync settings, in sync.json next to history.json. Not part of the backup (`BackupService` copies
/// history.json, tags.json and images/ only), so restoring on another Mac never copies the device ID.
struct SyncSettings: Codable, Equatable {
    var isEnabled = false
    var deviceID: String?
    /// Set after the first round that read every other Mac: tags are adopted by name only before it.
    var hasJoined = false
    var deletions: [SyncDeletion] = []
    /// The Mac that wrote this file (`MachineID`). Migration Assistant and Time Machine do copy sync.json: a
    /// different value means the device ID belongs to another Mac. Nil in files written before it existed.
    var machineID: String?
}

/// Keeps this Mac in sync with the others through iCloud Drive/SimpleClipboard/Sync/: each Mac writes only its own
/// devices/<id>.json and adds the images it has to images/, then merges what the others published (`SyncMerge`).
/// No file has two writers, so iCloud Drive never makes conflict copies.
/// Synchronous by design, like `BackupService`: it runs on the main actor so the store cannot change mid-round.
@MainActor
public final class SyncService {
    private static let logger = Logger(subsystem: Config.bundleID, category: "SyncService")

    private struct RemoteRead {
        var states: [SyncState] = []
        /// False when some file could not be read this round: then no image can be judged unused.
        var allRead = true
        var newerVersion = false
    }

    private struct VersionOnly: Decodable {
        let version: Int
    }

    private let iCloudDriveRoot: URL
    private let devicesDirectory: URL
    private let imagesDirectory: URL
    private let localImagesDirectory: URL
    private let settingsURL: URL
    private let now: () -> Date
    private let fileManager = FileManager.default
    private var settings: SyncSettings
    /// Decoded files of other Macs with the modification date they had: an unchanged file is not decoded again.
    private var cache: [String: (modified: Date, state: SyncState)] = [:]
    /// What this Mac last published and when, to skip rewriting an unchanged file.
    private var lastPublished: (state: SyncState, at: Date)?

    public init(
        localDirectory: URL, iCloudDriveRoot: URL, now: @escaping () -> Date = Date.init,
        machineID: String? = MachineID.current
    ) {
        self.iCloudDriveRoot = iCloudDriveRoot
        self.now = now
        let syncDirectory = iCloudDriveRoot
            .appendingPathComponent(Config.appName, isDirectory: true)
            .appendingPathComponent("Sync", isDirectory: true)
        devicesDirectory = syncDirectory.appendingPathComponent("devices", isDirectory: true)
        imagesDirectory = syncDirectory.appendingPathComponent("images", isDirectory: true)
        localImagesDirectory = localDirectory.appendingPathComponent("images", isDirectory: true)
        settingsURL = localDirectory.appendingPathComponent("sync.json")
        settings = (try? Data(contentsOf: settingsURL))
            .flatMap { try? JSONDecoder().decode(SyncSettings.self, from: $0) }
            ?? SyncSettings()
        adopt(machineID: machineID)
    }

    public var isAvailable: Bool {
        fileManager.fileExists(atPath: iCloudDriveRoot.path)
    }

    public var isEnabled: Bool {
        settings.isEnabled
    }

    /// Turns sync on. The device ID is created the first time and kept from then on.
    public func enable() throws {
        guard isAvailable else {
            throw SyncError.iCloudUnavailable
        }
        settings.isEnabled = true
        if settings.deviceID == nil {
            settings.deviceID = UUID().uuidString
        }
        saveSettings()
    }

    /// Stops reading and writing. This Mac's file stays in iCloud Drive; enabling again reuses the same ID.
    public func disable() {
        settings.isEnabled = false
        saveSettings()
    }

    /// The deletions of one store operation that other Macs must apply (`HistoryStore.deletionRecorder`). Kept
    /// `Config.syncRetention`, across relaunches. Saved once however many there are: clearing a full history would
    /// otherwise rewrite sync.json (which holds up to 90 days of deletions) once per item, on the main thread.
    public func record(_ deletions: [SyncDeletion]) {
        settings.deletions = liveDeletions() + deletions
        saveSettings()
    }

    /// One round: read the other Macs, merge into the store, publish this Mac. A file that cannot be read never
    /// counts as empty, so it never deletes local data.
    @discardableResult
    public func sync(_ store: HistoryStore) -> SyncStatus {
        guard settings.isEnabled, let deviceID = settings.deviceID else {
            return .off
        }
        guard isAvailable else {
            return .iCloudUnavailable
        }
        let remote = readRemoteStates(excluding: deviceID)
        // Tags are adopted by name only from files that were read, and publishing before that would give the other
        // Mac tags it can never remove (absence is not a deletion). `readRemoteStates` already asked for the downloads.
        if !settings.hasJoined, !remote.allRead {
            return remote.newerVersion
                ? .newerVersionElsewhere
                : .waitingForOtherMacs
        }
        let snapshot = store.syncSnapshot()
        var local = SyncState(
            deviceID: deviceID, publishedAt: now(), items: snapshot.items, tags: snapshot.tags, deletions: liveDeletions()
        )
        if !settings.hasJoined {
            local = SyncMerge.adoptingRemoteTags(local, remotes: remote.states, now: now())
        }
        var result = SyncMerge.merge(local: local, remotes: remote.states, concealedHashes: store.concealedHashes, now: now())
        result.items = result.items.filter { Self.hasAcceptableContent($0) && ensureLocalImage($0) }
        store.applySync(result)
        do {
            try publish(deviceID: deviceID, store: store)
        } catch {
            let code = error as NSError
            Self.logger.error("Sync publish failed: \(code.domain, privacy: .public) \(code.code, privacy: .public)")
            return .writeFailed
        }
        if remote.allRead {
            if !settings.hasJoined {
                settings.hasJoined = true
                saveSettings()
            }
            let used = (remote.states.flatMap(\.items) + store.syncSnapshot().items).compactMap(\.imageFileName)
            removeUnusedImages(used: Set(used))
        }
        guard !remote.newerVersion else {
            return .newerVersionElsewhere
        }
        return .synced(now())
    }

    // MARK: private

    /// Two Macs with the same device ID each skip the other's file as their own and both write it, so they never
    /// sync. A sync.json copied from another Mac gets a new device ID and joins again like a new Mac; its deletions
    /// are dropped, since the Mac that made them already publishes them. Sync stays on: a Mac that has not joined
    /// publishes nothing until it has read every other file, so it cannot overwrite or duplicate anything.
    /// A file without a machine ID predates it and cannot be judged: it is taken as this Mac's. Without a device ID
    /// there is nothing to protect yet and nothing is written: `enable()` saves the machine ID with the new ID.
    private func adopt(machineID: String?) {
        guard let machineID, settings.machineID != machineID else {
            return
        }
        let copiedFromAnotherMac = settings.machineID != nil
        settings.machineID = machineID
        if copiedFromAnotherMac {
            if settings.deviceID != nil {
                settings.deviceID = UUID().uuidString
            }
            settings.hasJoined = false
            settings.deletions = []
        }
        guard copiedFromAnotherMac || settings.deviceID != nil else {
            return
        }
        saveSettings()
    }

    private func liveDeletions() -> [SyncDeletion] {
        let current = now()
        return settings.deletions.filter { current.timeIntervalSince($0.deletedAt) <= Config.syncRetention }
    }

    private func saveSettings() {
        do {
            try JSONEncoder().encode(settings).write(to: settingsURL, options: .atomic)
        } catch {
            let code = error as NSError
            Self.logger.error("Cannot save sync.json: \(code.domain, privacy: .public) \(code.code, privacy: .public)")
        }
    }

    /// Files of other Macs. One not downloaded yet is requested and its last decoded version used meanwhile; a
    /// corrupt one or one with a newer format is skipped this round.
    /// A Mac silent for longer than `Config.syncRetention` is taken for gone, as in `SyncMerge`: judged by
    /// `publishedAt` when its file reads, by the file's modification date when it does not. Its file is then left out
    /// (it neither blocks joining, nor keeps images, nor reports a newer version) but never deleted: deleting another
    /// Mac's file cannot be undone, and that Mac may still come back, after which it publishes again and counts again.
    private func readRemoteStates(excluding deviceID: String) -> RemoteRead {
        var read = RemoteRead()
        let names = (try? fileManager.contentsOfDirectory(atPath: devicesDirectory.path)) ?? []
        for name in names where name.hasSuffix(".json") && !name.hasPrefix(".") && name != "\(deviceID).json" {
            let file = devicesDirectory.appendingPathComponent(name)
            let remoteID = String(name.dropLast(".json".count))
            let modified = (try? fileManager.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date ?? .distantPast
            let isGone = now().timeIntervalSince(modified) > Config.syncRetention
            guard isDownloaded(file) else {
                guard !isGone else {
                    continue
                }
                try? fileManager.startDownloadingUbiquitousItem(at: file)
                read.allRead = false
                if let cached = cache[remoteID], isLive(cached.state) {
                    read.states.append(cached.state)
                }
                continue
            }
            if let cached = cache[remoteID], cached.modified == modified {
                if isLive(cached.state) {
                    read.states.append(cached.state)
                }
                continue
            }
            do {
                // Decoded once: the version alone is read only when the whole file does not decode, since a newer
                // format usually fails here. A newer file that does decode is still caught by its version.
                let data = try Data(contentsOf: file)
                let state: SyncState
                do {
                    state = try JSONDecoder().decode(SyncState.self, from: data)
                } catch {
                    guard let version = try? JSONDecoder().decode(VersionOnly.self, from: data).version,
                          version > SyncState.currentVersion else {
                        throw error
                    }
                    if !isGone {
                        read.newerVersion = true
                        read.allRead = false
                    }
                    continue
                }
                guard state.version <= SyncState.currentVersion else {
                    if isLive(state) {
                        read.newerVersion = true
                        read.allRead = false
                    }
                    continue
                }
                // Each Mac writes only <its device ID>.json: any other content is a copy or a forgery.
                guard state.deviceID == remoteID else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                cache[remoteID] = (modified, state)
                if isLive(state) {
                    read.states.append(state)
                }
            } catch {
                guard !isGone else {
                    continue
                }
                let code = error as NSError
                Self.logger.error("Skipping unreadable sync file \(name, privacy: .public): \(code.domain, privacy: .public) \(code.code, privacy: .public)")
                read.allRead = false
            }
        }
        return read
    }

    private func isLive(_ state: SyncState) -> Bool {
        now().timeIntervalSince(state.publishedAt) <= Config.syncRetention
    }

    /// What `HistoryStore.add` would never save from a copy must not get in through another Mac's file either: an
    /// item without its content, or a text over `Config.maxTextBytes` (the image's size is checked when it is copied).
    private static func hasAcceptableContent(_ item: SyncItem) -> Bool {
        switch item.kind {
        case .text:
            guard let text = item.text else {
                return false
            }
            return text.utf8.count <= Config.maxTextBytes
        case .image:
            return item.imageFileName != nil
        }
    }

    /// The image name of an item comes from a file: another Mac's in iCloud Drive, or this Mac's history.json.
    /// "../history.json" would make a copy read or write, or the store read, outside the images folder.
    private static func isPlainFileName(_ name: String) -> Bool {
        !name.isEmpty && !name.hasPrefix(".") && !name.contains("/")
    }

    /// A text item needs nothing. An image item enters only once its PNG is in the local images folder: copied from
    /// Sync/images/ when it is there and downloaded, otherwise requested from iCloud and retried next round, so the
    /// panel never shows an empty card.
    private func ensureLocalImage(_ item: SyncItem) -> Bool {
        guard let name = item.imageFileName else {
            return true
        }
        // Anything but a plain file name is treated like a missing image.
        guard Self.isPlainFileName(name) else {
            return false
        }
        let local = localImagesDirectory.appendingPathComponent(name)
        if fileManager.fileExists(atPath: local.path) {
            return true
        }
        let shared = imagesDirectory.appendingPathComponent(name)
        guard fileManager.fileExists(atPath: shared.path) else {
            return false
        }
        guard isDownloaded(shared) else {
            try? fileManager.startDownloadingUbiquitousItem(at: shared)
            return false
        }
        // Only a regular file within `Config.maxImageBytes`: a symlink would be copied as a link to anywhere on disk.
        let attributes = try? fileManager.attributesOfItem(atPath: shared.path)
        guard attributes?[.type] as? FileAttributeType == .typeRegular,
              let size = attributes?[.size] as? Int, size <= Config.maxImageBytes else {
            return false
        }
        do {
            try copyImage(from: shared, to: local)
            return true
        } catch {
            let code = error as NSError
            Self.logger.error("Cannot copy synced image \(name, privacy: .public): \(code.domain, privacy: .public) \(code.code, privacy: .public)")
            return false
        }
    }

    /// Images first, then the state file, so another Mac rarely waits on an image. An image already in Sync/images/
    /// is never rewritten: the same name is always the same content. The state file is rewritten only when it
    /// changed, or once a day (`Config.syncRefreshInterval`) so a quiet Mac is not taken for gone.
    private func publish(deviceID: String, store: HistoryStore) throws {
        let snapshot = store.syncSnapshot()
        let state = SyncState(
            deviceID: deviceID, publishedAt: now(), items: snapshot.items, tags: snapshot.tags, deletions: liveDeletions()
        )
        let file = devicesDirectory.appendingPathComponent("\(deviceID).json")
        if isUnchanged(state), fileManager.fileExists(atPath: file.path) {
            return
        }
        try fileManager.createDirectory(at: devicesDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        for name in Set(snapshot.items.compactMap(\.imageFileName)) where Self.isPlainFileName(name) {
            let shared = imagesDirectory.appendingPathComponent(name)
            if !fileManager.fileExists(atPath: shared.path) {
                try copyImage(from: localImagesDirectory.appendingPathComponent(name), to: shared)
            }
        }
        try JSONEncoder().encode(state).write(to: file, options: .atomic)
        lastPublished = (state, now())
    }

    /// Copies through a dot-prefixed temporary name, stamps it with the current time and moves it into place. Two
    /// reasons. The grace period (`Config.syncImageGrace`) counts from when the image reached iCloud, not from its
    /// age: `copyItem` keeps the source's modification date, so a backlog image would arrive already older than the
    /// grace and another Mac that sees the PNG before this Mac's file lists it would delete it at once. And images
    /// are write-once: a half-written file under its final name would never be replaced. Listing and cleanup skip
    /// names starting with a dot.
    private func copyImage(from source: URL, to destination: URL) throws {
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString)", isDirectory: false)
        do {
            try fileManager.copyItem(at: source, to: temporary)
            try fileManager.setAttributes([.modificationDate: now()], ofItemAtPath: temporary.path)
            try fileManager.moveItem(at: temporary, to: destination)
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }

    private func isUnchanged(_ state: SyncState) -> Bool {
        guard let lastPublished, now().timeIntervalSince(lastPublished.at) < Config.syncRefreshInterval else {
            return false
        }
        return lastPublished.state.items == state.items
            && lastPublished.state.tags == state.tags
            && lastPublished.state.deletions == state.deletions
    }

    /// Deletes images no Mac uses, once older than `Config.syncImageGrace`: a new image can arrive before the file
    /// of the Mac that uses it.
    private func removeUnusedImages(used: Set<String>) {
        let current = now()
        let names = (try? fileManager.contentsOfDirectory(atPath: imagesDirectory.path)) ?? []
        for name in names where !name.hasPrefix(".") && !used.contains(name) {
            let file = imagesDirectory.appendingPathComponent(name)
            let modified = (try? fileManager.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date ?? current
            if current.timeIntervalSince(modified) > Config.syncImageGrace {
                try? fileManager.removeItem(at: file)
            }
        }
    }

    /// False only for an iCloud item whose local copy is missing or outdated. From macOS 14 (the minimum) an item that
    /// is not downloaded keeps its name, so only the downloading status tells; it is nil outside iCloud Drive.
    /// Same check as `BackupService.isCurrent`.
    private func isDownloaded(_ file: URL) -> Bool {
        // A fresh URL: URL caches resource values.
        let fresh = URL(fileURLWithPath: file.path)
        let values = try? fresh.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
        guard let status = values?.ubiquitousItemDownloadingStatus else {
            return true
        }
        return status == .current
    }
}
