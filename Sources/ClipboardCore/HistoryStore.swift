import CryptoKit
import Foundation
import Observation
import os

@MainActor
@Observable
public final class HistoryStore {
    /// A panel tab: the whole history or one tag.
    public enum Scope: Hashable, Sendable {
        case history
        case tag(UUID)
    }

    private static let logger = Logger(subsystem: Config.bundleID, category: "HistoryStore")
    /// How far after the last known stamp a change is dated when this clock is behind it (`stamp(after:)`).
    private static let stampStep: TimeInterval = 0.001

    /// Newest first.
    public private(set) var items: [ClipItem] = []
    /// Creation order (the order of the panel tabs).
    public private(set) var tags: [Tag] = []
    /// Connected to `SyncService.record`, which decides what to keep: the deletions other Macs must apply. One call
    /// per store operation with all its deletions, and none when there are none: `SyncService` saves its file once
    /// per call, so a call per item would rewrite it once per item on the main thread.
    public var deletionRecorder: (@MainActor ([SyncDeletion]) -> Void)?
    /// The latest deletion of a content hash this Mac knows of, its own or another Mac's
    /// (`SyncService.latestDeletion(ofItem:)`): a new copy of that content is dated after it (`stamp(after:)`).
    public var knownDeletion: (@MainActor (String) -> Date?)?
    /// Called after every save; the app uses it to publish to other Macs shortly after a local change.
    public var onPersist: (@MainActor () -> Void)?

    private let persistence: HistoryPersistence
    private let now: () -> Date

    public init(persistence: HistoryPersistence, now: @escaping () -> Date = Date.init) {
        self.persistence = persistence
        self.now = now
        items = persistence.load()
        tags = persistence.loadTags()
        let recreatedTags = persistence.tagsWereLost && recreateLostTags()
        let untaggedOrphans = untagOrphans()
        if prune() || untaggedOrphans || recreatedTags {
            persist()
        }
    }

    // MARK: capture

    @discardableResult
    public func add(_ content: ClipContent, source: SourceApp, concealed: Bool) -> ClipItem? {
        // Checked before hashing, so a huge copy costs nothing; only the size is logged, never the content.
        switch content {
        case .text(let text):
            guard text.utf8.count <= Config.maxTextBytes else {
                Self.logger.notice("Dropping text of \(text.utf8.count, privacy: .public) bytes, over the limit")
                return nil
            }
        case .image(let data):
            guard data.count <= Config.maxImageBytes else {
                Self.logger.notice("Dropping image of \(data.count, privacy: .public) bytes, over the limit")
                return nil
            }
        }
        let hash = Self.hash(of: content)
        let previous = items.first { $0.contentHash == hash }
        // A plain copy is dated after the previous copy and after any deletion of the same content this Mac knows of,
        // so it survives them in the merge. A concealed one keeps this clock's time: it never leaves the Mac and
        // `expiresAt` counts from it.
        let createdAt = concealed
            ? now()
            : stamp(after: [previous?.createdAt, knownDeletion?(hash)].compactMap { $0 }.max())
        let expiresAt: Date? = concealed
            ? createdAt.addingTimeInterval(Config.concealedLifetime)
            : nil
        var item: ClipItem

        switch content {
        case .text(let text):
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            item = ClipItem(
                createdAt: createdAt, kind: .text, text: text, imageFileName: nil,
                contentHash: hash, source: source, isConcealed: concealed, expiresAt: expiresAt
            )
        case .image(let data) where concealed:
            item = ClipItem(
                createdAt: createdAt, kind: .image, text: nil, imageFileName: nil, inMemoryImage: data,
                contentHash: hash, source: source, isConcealed: true, expiresAt: expiresAt
            )
        case .image(let data):
            let fileName = "\(hash).png"
            do {
                try persistence.writeImage(data, named: fileName)
            } catch {
                Self.logger.error("Dropping image, cannot write it: \(error.localizedDescription, privacy: .public)")
                return nil
            }
            item = ClipItem(
                createdAt: createdAt, kind: .image, text: nil, imageFileName: fileName,
                contentHash: hash, source: source, isConcealed: false, expiresAt: nil
            )
        }

        // A re-copy keeps the tag, and when it was set, so other Macs do not take it for a newer tag change.
        // A concealed re-copy drops it (concealed items are never tagged); for a saved value it is also a deletion
        // other Macs must apply, so the value does not stay there as plain text.
        if !item.isConcealed {
            item.tagID = previous?.tagID
            item.tagChangedAt = previous?.tagChangedAt
        } else if let previous, !previous.isConcealed {
            recordDeletions([.item(hash, at: stamp(after: SyncItem(previous).lastChange))])
        }
        items.removeAll { $0.contentHash == hash }
        items.insert(item, at: 0)
        prune()
        persist()
        return item
    }

    public func promote(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return
        }
        var item = items.remove(at: index)
        item.createdAt = stamp(after: item.createdAt)
        items.insert(item, at: 0)
        persist()
    }

    public func remove(id: UUID) {
        if let item = items.first(where: { $0.id == id }), !item.isConcealed {
            recordDeletions([.item(item.contentHash, at: stamp(after: SyncItem(item).lastChange))])
        }
        items.removeAll { $0.id == id }
        persist()
    }

    /// Clears the untagged items; tagged ones are kept.
    public func removeUntagged() {
        recordDeletions(items.filter { $0.tagID == nil && !$0.isConcealed }.map { item in
            .item(item.contentHash, at: stamp(after: SyncItem(item).lastChange))
        })
        items.removeAll { $0.tagID == nil }
        persist()
    }

    public func purgeExpired() {
        if prune() {
            persist()
        }
    }

    // MARK: tags

    @discardableResult
    public func createTag(name: String, colorIndex: Int) -> Tag? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, Self.isValidColor(colorIndex) else {
            return nil
        }
        let tag = Tag(name: trimmed, colorIndex: colorIndex, changedAt: now())
        tags.append(tag)
        persist()
        return tag
    }

    /// `tagID == nil` removes the tag; the item is then treated as just copied.
    /// Returns false for an unknown item, a concealed item or an unknown tag.
    @discardableResult
    public func setTag(itemID: UUID, tagID: UUID?) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == itemID }), !items[index].isConcealed else {
            return false
        }
        if let tagID {
            guard tags.contains(where: { $0.id == tagID }) else {
                return false
            }
            items[index].tagID = tagID
            items[index].tagChangedAt = stamp(after: items[index].tagChangedAt)
        } else if items[index].tagID != nil {
            untag { $0.id == itemID }
            prune()
        }
        persist()
        return true
    }

    @discardableResult
    public func renameTag(id: UUID, name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = tags.firstIndex(where: { $0.id == id }) else {
            return false
        }
        tags[index].name = trimmed
        tags[index].changedAt = stamp(after: tags[index].changedAt)
        persist()
        return true
    }

    @discardableResult
    public func recolorTag(id: UUID, colorIndex: Int) -> Bool {
        guard Self.isValidColor(colorIndex), let index = tags.firstIndex(where: { $0.id == id }) else {
            return false
        }
        tags[index].colorIndex = colorIndex
        tags[index].changedAt = stamp(after: tags[index].changedAt)
        persist()
        return true
    }

    /// Its items go back to the history as if just copied; none is deleted.
    public func deleteTag(id: UUID) {
        if let tag = tags.first(where: { $0.id == id }) {
            recordDeletions([.tag(id, at: stamp(after: tag.changedAt))])
        }
        tags.removeAll { $0.id == id }
        untag { $0.tagID == id }
        prune()
        persist()
    }

    /// Replaces memory with what is on disk (after a restore). In-memory concealed items are dropped. The caller says
    /// which kind of restore this is, because sync reads the stamps differently:
    /// - `markingChanges: true`, a restore the user asked for. What came back counts as changed now, so it wins over
    ///   an older deletion on another Mac, even when sync is turned on only later; what is gone counts as deleted.
    ///   `createdAt` is kept, so the order does not change.
    /// - `markingChanges: false`, the first-launch restore that fills an empty new Mac. Items and tags keep the stamps
    ///   the backup carries and nothing is recorded as deleted, so the normal merge rules decide against the other
    ///   Macs: stamping it as changed now would undo, once sync is on, everything they did since that backup.
    /// There is no default: forgetting the choice would silently pick one of the two.
    public func reloadFromDisk(markingChanges: Bool) {
        let previousItems = Dictionary(
            items.filter { !$0.isConcealed }.map { ($0.contentHash, SyncItem($0).lastChange) }, uniquingKeysWith: max
        )
        let previousTags = Dictionary(tags.map { ($0.id, $0.changedAt) }, uniquingKeysWith: { first, _ in first })
        items = persistence.load()
        tags = persistence.loadTags()
        if markingChanges {
            // Each stamp is later than the restored version, the one it replaces and a known deletion (`stamp(after:)`).
            for index in items.indices {
                let hash = items[index].contentHash
                let known = [SyncItem(items[index]).lastChange, previousItems[hash], knownDeletion?(hash)]
                items[index].tagChangedAt = stamp(after: known.compactMap { $0 }.max())
            }
            for index in tags.indices {
                let replaced = previousTags[tags[index].id] ?? nil
                tags[index].changedAt = stamp(after: [tags[index].changedAt, replaced].compactMap { $0 }.max())
            }
            let restoredHashes = Set(items.map(\.contentHash))
            let restoredTagIDs = Set(tags.map(\.id))
            let goneItems = previousItems.filter { !restoredHashes.contains($0.key) }
                .map { SyncDeletion.item($0.key, at: stamp(after: $0.value)) }
            let goneTags = previousTags.filter { !restoredTagIDs.contains($0.key) }
                .map { SyncDeletion.tag($0.key, at: stamp(after: $0.value)) }
            recordDeletions(goneItems + goneTags)
        }
        untagOrphans()
        prune()
        persist()
    }

    // MARK: sync

    /// What this Mac publishes: everything but concealed items, which never leave the Mac.
    public func syncSnapshot() -> (items: [SyncItem], tags: [SyncTag]) {
        (items.filter { !$0.isConcealed }.map(SyncItem.init), tags.map(SyncTag.init))
    }

    /// Content hashes of the concealed items, which win over a synced copy (`SyncMerge.merge`).
    public var concealedHashes: Set<String> {
        Set(items.filter(\.isConcealed).map(\.contentHash))
    }

    /// Replaces the synced part of the store with a merge result. Local concealed items and the local ID of each item
    /// are kept (the panel tracks items by ID). Images of new image items must already be in the local images folder:
    /// `SyncService` copies them first. Saves only when something changed, so a quiet round writes nothing (and does
    /// not make the hourly backup think there are changes). Returns whether anything changed. The result is cut to the
    /// local limits before comparing: concealed items count toward them but not toward the merge's, so the local
    /// prune can drop an item another Mac still lists, and a prune after the comparison would save again every round.
    @discardableResult
    public func applySync(_ result: SyncMerge.Result) -> Bool {
        let localIDs = Dictionary(items.map { ($0.contentHash, $0.id) }, uniquingKeysWith: { first, _ in first })
        let synced = result.items.map { item in
            ClipItem(
                id: localIDs[item.contentHash] ?? UUID(),
                createdAt: item.createdAt, kind: item.kind, text: item.text, imageFileName: item.imageFileName,
                contentHash: item.contentHash,
                source: SourceApp(bundleID: item.sourceAppBundleID, name: item.sourceAppName),
                isConcealed: false, expiresAt: nil, tagID: item.tagID, tagChangedAt: Self.localStamp(item.tagChangedAt)
            )
        }
        let newTags = result.tags.map { Tag(id: $0.id, name: $0.name, colorIndex: $0.colorIndex, changedAt: Self.localStamp($0.changedAt)) }
        let newItems = Self.pruned((items.filter(\.isConcealed) + synced).sorted(by: Self.isNewer), now: now())
        guard newItems != items || newTags != tags else {
            return false
        }
        items = newItems
        tags = newTags
        persist()
        return true
    }

    // MARK: search and images

    public func search(_ query: String, in scope: Scope = .history) -> [ClipItem] {
        let pool: [ClipItem]
        switch scope {
        case .history:
            pool = items
        case .tag(let tagID):
            pool = items.filter { $0.tagID == tagID }
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return pool
        }
        return pool.filter { item in
            !item.isConcealed && (item.text?.localizedStandardContains(trimmed) ?? false)
        }
    }

    public func imageData(for item: ClipItem) -> Data? {
        if let data = item.inMemoryImage {
            return data
        }
        return item.imageFileName.flatMap(persistence.readImage(named:))
    }

    // MARK: private

    private static func isValidColor(_ colorIndex: Int) -> Bool {
        (0..<Config.tagColorCount).contains(colorIndex)
    }

    /// Newest first; equal dates by content hash, so the same items always come out in the same order and a quiet
    /// sync round compares equal.
    private static func isNewer(_ lhs: ClipItem, _ rhs: ClipItem) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }
        return lhs.contentHash < rhs.contentHash
    }

    /// Local data has one way to say "never stamped": nil. A merge result carries `SyncState.unstamped` instead, and
    /// writing that back would make every round look like a change.
    private static func localStamp(_ date: Date) -> Date? {
        guard date != SyncState.unstamped else {
            return nil
        }
        return date
    }

    /// The stamp of a change made here to something last changed at `last` (a hybrid logical clock): this clock's
    /// time, but always after `last`, which may come from another Mac whose clock is ahead. The merge keeps the later
    /// stamp, so dated by this clock alone the change would lose to the one it replaces (a deletion would not stick,
    /// a rename would be undone) until real time caught up. Only this Mac's own stamps change, never the merge, so
    /// every Mac still ends with the same data. A `last` more than `Config.maxClockSkew` ahead is not followed.
    private func stamp(after last: Date?) -> Date {
        let current = now()
        guard let last, last.timeIntervalSince(current) <= Config.maxClockSkew else {
            return current
        }
        return max(current, last.addingTimeInterval(Self.stampStep))
    }

    /// One call per store operation, and none for an empty list (see `deletionRecorder`).
    private func recordDeletions(_ deletions: [SyncDeletion]) {
        guard !deletions.isEmpty else {
            return
        }
        deletionRecorder?(deletions)
    }

    /// Clears the tag of every matching item; they become "just copied" and move to the front. A user action stamps
    /// the change, so it wins over older versions on other Macs; `stampingTagChange: false` leaves the stamp as it was.
    private func untag(stampingTagChange: Bool = true, where shouldUntag: (ClipItem) -> Bool) {
        let current = now()
        let moved = items.filter(shouldUntag).map { item in
            var untagged = item
            untagged.tagID = nil
            untagged.createdAt = current
            if stampingTagChange {
                untagged.createdAt = stamp(after: SyncItem(item).lastChange)
                untagged.tagChangedAt = untagged.createdAt
            }
            return untagged
        }
        items.removeAll(where: shouldUntag)
        items.insert(contentsOf: moved, at: 0)
    }

    /// After a tags file that could not be read nor recovered, a stand-in tag for each tag the items point to, so
    /// they stay tagged (on disk too) until a repaired file or another Mac brings the real one back. Each name is
    /// unique, so the merge never fuses two of them (`SyncMerge.fusingSameNames`), and the stamp is older than
    /// `SyncState.unstamped`, so any real version of the tag, even one never stamped, wins over it.
    private func recreateLostTags() -> Bool {
        let known = Set(tags.map(\.id))
        var lostIDs: [UUID] = []
        for tagID in items.compactMap(\.tagID) where !known.contains(tagID) && !lostIDs.contains(tagID) {
            lostIDs.append(tagID)
        }
        let stamp = SyncState.unstamped.addingTimeInterval(-1)
        tags += lostIDs.map { Tag(id: $0, name: "Recovered \($0.uuidString.prefix(8))", colorIndex: 0, changedAt: stamp) }
        return !lostIDs.isEmpty
    }

    /// Items whose tag no longer exists (e.g. the tags file is gone; an unreadable one goes to `recreateLostTags`)
    /// are treated as just copied, so they are not purged by the 30-day rule at launch. Their `tagChangedAt` is kept: a missing tag file is not a
    /// user decision, so it must not win over the other Macs' tagged version, and on a tie the merge ("having a tag
    /// wins") gives the tag back from them.
    @discardableResult
    private func untagOrphans() -> Bool {
        let known = Set(tags.map(\.id))
        let isOrphan: (ClipItem) -> Bool = { item in
            item.tagID.map { !known.contains($0) } ?? false
        }
        guard items.contains(where: isOrphan) else {
            return false
        }
        untag(stampingTagChange: false, where: isOrphan)
        return true
    }

    /// Drops expired concealed items, untagged items older than `maxAge` and the untagged overflow
    /// beyond `maxItems`. Tagged items are exempt from both age and cap.
    /// Returns whether anything was removed.
    @discardableResult
    private func prune() -> Bool {
        let kept = Self.pruned(items, now: now())
        guard kept != items else {
            return false
        }
        items = kept
        return true
    }

    /// The rules of `prune()` on a list, so `applySync` can apply them before comparing with the current items.
    private static func pruned(_ items: [ClipItem], now current: Date) -> [ClipItem] {
        var kept = items
        kept.removeAll { item in
            if let expiresAt = item.expiresAt {
                return expiresAt <= current
            }
            guard item.tagID == nil else {
                return false
            }
            return current.timeIntervalSince(item.createdAt) > Config.maxAge
        }
        let overflow = kept.filter { $0.tagID == nil }.dropFirst(Config.maxItems).map(\.id)
        if !overflow.isEmpty {
            let dropped = Set(overflow)
            kept.removeAll { dropped.contains($0.id) }
        }
        return kept
    }

    private func persist() {
        let persistable = items.filter { !$0.isConcealed }
        let saved = persistence.save(persistable)
        persistence.saveTags(tags)
        // A history that failed to save still lists the items of the last save, images included.
        if saved {
            persistence.deleteImages(notIn: Set(persistable.compactMap(\.imageFileName)))
        }
        onPersist?()
    }

    private static func hash(of content: ClipContent) -> String {
        var hasher = SHA256()
        switch content {
        case .text(let text):
            hasher.update(data: Data("text:".utf8))
            hasher.update(data: Data(text.utf8))
        case .image(let data):
            hasher.update(data: Data("image:".utf8))
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
