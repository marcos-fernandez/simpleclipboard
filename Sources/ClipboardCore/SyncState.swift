import Foundation

/// What one Mac publishes as iCloud Drive/SimpleClipboard/Sync/devices/<deviceID>.json. Only that Mac writes it.
public struct SyncState: Codable, Equatable, Sendable {
    /// A file with a higher version comes from a newer app on another Mac and is not read.
    /// 2: tag deletions may carry `SyncDeletion.fusedInto`. An app of version 1 would read such a deletion as a plain
    /// one and send the fused tag's items back to the history, untagging them on every Mac.
    public static let currentVersion = 2
    /// Stands for "never changed" in data saved before sync existed (2001-01-01). Never `createdAt`: it changes on
    /// every re-copy and would make an old "no tag" look newer than a real tag change.
    public static let unstamped = Date(timeIntervalSinceReferenceDate: 0)

    public var version: Int
    public var deviceID: String
    public var publishedAt: Date
    public var items: [SyncItem]
    public var tags: [SyncTag]
    /// This Mac's own deletions of the last `Config.syncRetention`.
    public var deletions: [SyncDeletion]

    public init(
        version: Int = SyncState.currentVersion,
        deviceID: String,
        publishedAt: Date,
        items: [SyncItem],
        tags: [SyncTag],
        deletions: [SyncDeletion]
    ) {
        self.version = version
        self.deviceID = deviceID
        self.publishedAt = publishedAt
        self.items = items
        self.tags = tags
        self.deletions = deletions
    }
}

/// An item as other Macs see it: no local ID, never concealed.
public struct SyncItem: Codable, Equatable, Sendable {
    public var contentHash: String
    public var kind: ClipItem.Kind
    public var text: String?
    public var imageFileName: String?
    public var createdAt: Date
    public var sourceAppBundleID: String?
    public var sourceAppName: String?
    public var tagID: UUID?
    public var tagChangedAt: Date
    /// Optional, as its date: not in the files of an app from before items could be named.
    public var customName: String?
    public var customNameChangedAt: Date?

    public init(
        contentHash: String,
        kind: ClipItem.Kind,
        text: String?,
        imageFileName: String?,
        createdAt: Date,
        sourceAppBundleID: String?,
        sourceAppName: String?,
        tagID: UUID?,
        tagChangedAt: Date,
        customName: String? = nil,
        customNameChangedAt: Date? = nil
    ) {
        self.contentHash = contentHash
        self.kind = kind
        self.text = text
        self.imageFileName = imageFileName
        self.createdAt = createdAt
        self.sourceAppBundleID = sourceAppBundleID
        self.sourceAppName = sourceAppName
        self.tagID = tagID
        self.tagChangedAt = tagChangedAt
        self.customName = customName
        self.customNameChangedAt = customNameChangedAt
    }

    public init(_ item: ClipItem) {
        self.init(
            contentHash: item.contentHash, kind: item.kind, text: item.text, imageFileName: item.imageFileName,
            createdAt: item.createdAt, sourceAppBundleID: item.sourceAppBundleID, sourceAppName: item.sourceAppName,
            tagID: item.tagID, tagChangedAt: item.tagChangedAt ?? SyncState.unstamped,
            customName: item.customName, customNameChangedAt: item.customNameChangedAt
        )
    }

    /// A deletion only removes an item it happened after: copying or tagging it again later brings it back. Not
    /// naming it: a name says nothing about wanting the item, and a Mac on a version from before the names would
    /// not count it, so the two would not agree on which items are left.
    var lastChange: Date {
        max(createdAt, tagChangedAt)
    }
}

public struct SyncTag: Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var colorIndex: Int
    public var changedAt: Date
    /// Optional, as its date: not in the files of an app from before the items of a tag could be put in order.
    public var itemOrder: [String]?
    public var itemOrderChangedAt: Date?

    public init(
        id: UUID,
        name: String,
        colorIndex: Int,
        changedAt: Date,
        itemOrder: [String]? = nil,
        itemOrderChangedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.colorIndex = colorIndex
        self.changedAt = changedAt
        self.itemOrder = itemOrder
        self.itemOrderChangedAt = itemOrderChangedAt
    }

    public init(_ tag: Tag) {
        self.init(
            id: tag.id, name: tag.name, colorIndex: tag.colorIndex, changedAt: tag.changedAt ?? SyncState.unstamped,
            itemOrder: tag.itemOrder, itemOrderChangedAt: tag.itemOrderChangedAt
        )
    }
}
