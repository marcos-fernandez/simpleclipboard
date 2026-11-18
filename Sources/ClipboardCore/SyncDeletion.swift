import Foundation

/// A deletion other Macs must apply too. Rules: `SyncMerge`.
public struct SyncDeletion: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case item
        case tag
    }

    public let kind: Kind
    /// The content hash of an item, or the UUID string of a tag.
    public let key: String
    public let deletedAt: Date

    public init(kind: Kind, key: String, deletedAt: Date) {
        self.kind = kind
        self.key = key
        self.deletedAt = deletedAt
    }

    public static func item(_ contentHash: String, at date: Date) -> SyncDeletion {
        SyncDeletion(kind: .item, key: contentHash, deletedAt: date)
    }

    public static func tag(_ id: UUID, at date: Date) -> SyncDeletion {
        SyncDeletion(kind: .tag, key: id.uuidString, deletedAt: date)
    }
}
