import Foundation

/// Merges this Mac's state with the states other Macs published. Pure: the same inputs give the same result in any
/// order, and merging a result again changes nothing, so every Mac ends up with the same data.
public enum SyncMerge {
    public struct Result: Equatable, Sendable {
        /// Newest first, within the limits (`Config.maxAge`, `Config.maxItems` untagged); tagged items are exempt.
        public var items: [SyncItem]
        /// This Mac's order first (the panel tabs), then new tags in the order other Macs list them.
        public var tags: [SyncTag]

        public init(items: [SyncItem], tags: [SyncTag]) {
            self.items = items
            self.tags = tags
        }
    }

    private struct DeletionKey: Hashable {
        let kind: SyncDeletion.Kind
        let key: String
    }

    private typealias Candidate = (item: SyncItem, deviceID: String)

    /// `concealedHashes`: this Mac's concealed items. They win over a synced copy of the same content, as in `add()`.
    public static func merge(local: SyncState, remotes: [SyncState], concealedHashes: Set<String>, now: Date) -> Result {
        let others = liveRemotes(remotes, local: local, now: now)
        let states = ([local] + others).sorted { $0.deviceID < $1.deviceID }
        let deletions = latestDeletions(in: states, now: now)
        let fused = fusingSameNames(mergedTags(local: local, states: states, deletions: deletions))
        let items = mergedItems(
            states: states, tagIDs: Set(fused.tags.map(\.id)), tagRemap: fused.remap, deletions: deletions,
            concealedHashes: concealedHashes
        )
        return Result(items: withinLimits(items, now: now), tags: fused.tags)
    }

    /// First sync on a Mac: a local tag named like a remote one (trimmed, case-insensitive) is replaced by the
    /// remote one and its items move to it, so joining never shows the same tag twice. Only tags that survive
    /// `merge`'s per-id rules are adopted, under the name `merge` would show: a tag of a silent Mac or a deleted one
    /// would be dropped right after, and the local tag with its items would be lost with it. The adopted tag may
    /// still be fused into a same-named one afterwards (`fusingSameNames`); its items follow.
    public static func adoptingRemoteTags(_ local: SyncState, remotes: [SyncState], now: Date) -> SyncState {
        let others = liveRemotes(remotes, local: local, now: now)
        let states = [local] + others
        let kept = mergedTags(local: local, states: states, deletions: latestDeletions(in: states, now: now))
        var remoteIDs: [String: UUID] = [:]
        for remote in others.sorted(by: { $0.deviceID < $1.deviceID }) {
            for tag in remote.tags {
                guard let winner = kept.first(where: { $0.id == tag.id }), remoteIDs[nameKey(winner.name)] == nil else {
                    continue
                }
                remoteIDs[nameKey(winner.name)] = tag.id
            }
        }
        var replaced: [UUID: UUID] = [:]
        for tag in local.tags {
            if let remoteID = remoteIDs[nameKey(tag.name)], remoteID != tag.id {
                replaced[tag.id] = remoteID
            }
        }
        var adopted = local
        adopted.tags.removeAll { replaced[$0.id] != nil }
        adopted.items = local.items.map { item in
            var moved = item
            if let tagID = item.tagID, let remoteID = replaced[tagID] {
                moved.tagID = remoteID
            }
            return moved
        }
        return adopted
    }

    /// A Mac silent for longer than the retention is taken for gone: once the deletions it missed are forgotten,
    /// its old items would otherwise come back.
    private static func liveRemotes(_ remotes: [SyncState], local: SyncState, now: Date) -> [SyncState] {
        remotes.filter { remote in
            remote.deviceID != local.deviceID && now.timeIntervalSince(remote.publishedAt) <= Config.syncRetention
        }
    }

    private static func latestDeletions(in states: [SyncState], now: Date) -> [DeletionKey: Date] {
        var latest: [DeletionKey: Date] = [:]
        for deletion in states.flatMap(\.deletions) where now.timeIntervalSince(deletion.deletedAt) <= Config.syncRetention {
            let key = DeletionKey(kind: deletion.kind, key: deletion.key)
            latest[key] = max(latest[key] ?? deletion.deletedAt, deletion.deletedAt)
        }
        return latest
    }

    /// Per tag the newest change wins (ties: the higher device ID); a later deletion removes it.
    private static func mergedTags(local: SyncState, states: [SyncState], deletions: [DeletionKey: Date]) -> [SyncTag] {
        var winners: [UUID: (tag: SyncTag, deviceID: String)] = [:]
        var order = local.tags.map(\.id)
        for state in states {
            for tag in state.tags {
                guard let current = winners[tag.id] else {
                    winners[tag.id] = (tag, state.deviceID)
                    if !order.contains(tag.id) {
                        order.append(tag.id)
                    }
                    continue
                }
                if (tag.changedAt, state.deviceID) > (current.tag.changedAt, current.deviceID) {
                    winners[tag.id] = (tag, state.deviceID)
                }
            }
        }
        return order.compactMap { id in
            guard let winner = winners[id]?.tag else {
                return nil
            }
            if let deletedAt = deletions[DeletionKey(kind: .tag, key: id.uuidString)], deletedAt > winner.changedAt {
                return nil
            }
            return winner
        }
    }

    /// Tags with the same name (`nameKey`: trimmed, case-insensitive) become one, in every merge: the smallest id wins,
    /// keeping its own name, color and position, and the others go into `remap` so their items follow it. Two Macs
    /// that join before seeing each other's file each publish their own "Work", and absence is not a deletion, so
    /// without this both would keep both tags for ever, with the items split between them. The user chose this
    /// knowing it also fuses two tags created on purpose with the same name, and that it cannot be undone. It runs on
    /// the tags that survived their deletions, so a deleted tag is never fused into a namesake (its items become
    /// orphans), and it picks by id, so the result does not depend on the order of the states.
    private static func fusingSameNames(_ tags: [SyncTag]) -> (tags: [SyncTag], remap: [UUID: UUID]) {
        var winners: [String: UUID] = [:]
        for tag in tags {
            let key = nameKey(tag.name)
            if let current = winners[key], current.uuidString <= tag.id.uuidString {
                continue
            }
            winners[key] = tag.id
        }
        var remap: [UUID: UUID] = [:]
        for tag in tags {
            if let winner = winners[nameKey(tag.name)], winner != tag.id {
                remap[tag.id] = winner
            }
        }
        return (tags.filter { remap[$0.id] == nil }, remap)
    }

    /// Per content: the newest `createdAt` (it only grows) with the source app of that copy, and the tag of the
    /// newest tag change, so a re-copy on one Mac and a tag set on another both survive. A later deletion removes
    /// the item. An item whose tag is gone goes back to the history, dated no earlier than the tag's deletion so it
    /// does not expire at once.
    private static func mergedItems(
        states: [SyncState], tagIDs: Set<UUID>, tagRemap: [UUID: UUID], deletions: [DeletionKey: Date],
        concealedHashes: Set<String>
    ) -> [SyncItem] {
        var candidates: [String: [Candidate]] = [:]
        for state in states {
            for item in state.items {
                candidates[item.contentHash, default: []].append((item, state.deviceID))
            }
        }
        var merged: [SyncItem] = []
        for (hash, versions) in candidates where !concealedHashes.contains(hash) {
            guard let newestCopy = versions.max(by: { ($0.item.createdAt, $0.deviceID) < ($1.item.createdAt, $1.deviceID) }),
                  let newestTag = versions.max(by: { tagRank($0) < tagRank($1) }) else {
                continue
            }
            var item = newestCopy.item
            // A tag fused into a namesake (`fusingSameNames`) is re-pointed here, before the orphan check below, so
            // its items follow the surviving tag instead of falling back to the history. `tagChangedAt` is kept.
            item.tagID = newestTag.item.tagID.map { tagRemap[$0] ?? $0 }
            item.tagChangedAt = newestTag.item.tagChangedAt
            // Checked before the orphan rule below: re-dating an orphan must not let it outlive its own deletion.
            if let deletedAt = deletions[DeletionKey(kind: .item, key: hash)], deletedAt > item.lastChange {
                continue
            }
            if let tagID = item.tagID, !tagIDs.contains(tagID) {
                let tagDeletedAt = deletions[DeletionKey(kind: .tag, key: tagID.uuidString)] ?? item.createdAt
                item.tagID = nil
                item.createdAt = max(item.createdAt, tagDeletedAt)
                item.tagChangedAt = max(item.tagChangedAt, tagDeletedAt)
            }
            merged.append(item)
        }
        return merged
    }

    /// Newest tag change first; on equal times having a tag wins (two histories saved before sync must not lose a
    /// tag), then the higher device ID.
    private static func tagRank(_ candidate: Candidate) -> (Date, Int, String) {
        let hasTag = candidate.item.tagID == nil
            ? 0
            : 1
        return (candidate.item.tagChangedAt, hasTag, candidate.deviceID)
    }

    /// Same limits as `HistoryStore.prune()`, applied here so images of dropped items are never copied.
    private static func withinLimits(_ items: [SyncItem], now: Date) -> [SyncItem] {
        let newestFirst = items.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.contentHash < rhs.contentHash
        }
        var untaggedKept = 0
        return newestFirst.filter { item in
            guard item.tagID == nil else {
                return true
            }
            guard now.timeIntervalSince(item.createdAt) <= Config.maxAge, untaggedKept < Config.maxItems else {
                return false
            }
            untaggedKept += 1
            return true
        }
    }

    private static func nameKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
