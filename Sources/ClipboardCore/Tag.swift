import Foundation

/// A named, coloured collection. Tagged items never expire.
public struct Tag: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    /// Index into the fixed palette, 0..<Config.tagColorCount.
    public var colorIndex: Int
    /// Last create, rename or recolour; nil in tags saved before sync existed. Sync compares it across Macs.
    public var changedAt: Date?

    public init(id: UUID = UUID(), name: String, colorIndex: Int, changedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.colorIndex = colorIndex
        self.changedAt = changedAt
    }
}
