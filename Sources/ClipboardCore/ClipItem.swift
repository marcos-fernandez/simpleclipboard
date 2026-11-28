import Foundation

public enum ClipContent: Equatable, Sendable {
    case text(String)
    /// PNG bytes.
    case image(Data)
}

public struct SourceApp: Equatable, Sendable {
    public let bundleID: String?
    public let name: String?

    public init(bundleID: String?, name: String?) {
        self.bundleID = bundleID
        self.name = name
    }
}

public struct ClipItem: Codable, Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case text
        case image
    }

    public let id: UUID
    public var createdAt: Date
    public let kind: Kind
    public let text: String?
    /// PNG file name on disk; only for non-concealed images.
    public let imageFileName: String?
    /// PNG bytes kept only in memory; only for concealed images. Never encoded.
    public var inMemoryImage: Data?
    public let contentHash: String
    public let sourceAppBundleID: String?
    public let sourceAppName: String?
    public let isConcealed: Bool
    public let expiresAt: Date?
    /// nil = untagged. Concealed items are never tagged.
    public var tagID: UUID?
    /// When `tagID` was last set or cleared; nil in items saved before sync existed. Sync compares it across Macs.
    public var tagChangedAt: Date?
    /// The name the user gave it, shown in place of the app it was copied from; nil = none. Concealed items are
    /// never named.
    public var customName: String?
    /// When `customName` was last set or cleared; nil in items never named. Sync compares it across Macs.
    public var customNameChangedAt: Date?

    /// What the card is called: its name, or else the app it was copied from.
    public var displayName: String? {
        customName ?? sourceAppName
    }

    enum CodingKeys: String, CodingKey {
        case id, createdAt, kind, text, imageFileName, contentHash
        case sourceAppBundleID, sourceAppName, isConcealed, expiresAt, tagID, tagChangedAt
        case customName, customNameChangedAt
    }

    public init(
        id: UUID = UUID(),
        createdAt: Date,
        kind: Kind,
        text: String?,
        imageFileName: String?,
        inMemoryImage: Data? = nil,
        contentHash: String,
        source: SourceApp,
        isConcealed: Bool,
        expiresAt: Date?,
        tagID: UUID? = nil,
        tagChangedAt: Date? = nil,
        customName: String? = nil,
        customNameChangedAt: Date? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.kind = kind
        self.text = text
        self.imageFileName = imageFileName
        self.inMemoryImage = inMemoryImage
        self.contentHash = contentHash
        self.sourceAppBundleID = source.bundleID
        self.sourceAppName = source.name
        self.isConcealed = isConcealed
        self.expiresAt = expiresAt
        self.tagID = tagID
        self.tagChangedAt = tagChangedAt
        self.customName = customName
        self.customNameChangedAt = customNameChangedAt
    }
}
