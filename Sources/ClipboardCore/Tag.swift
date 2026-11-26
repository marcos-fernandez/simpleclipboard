import Foundation

/// A named, coloured collection. Tagged items never expire.
public struct Tag: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    /// Index into the fixed palette, 0..<Config.tagColorCount.
    public var colorIndex: Int
    /// Last create, rename or recolour; nil in tags saved before sync existed. Sync compares it across Macs.
    public var changedAt: Date?
    /// The order the user gave its items, as content hashes (an item has no other identity across Macs); nil until
    /// one is moved, and the items are then newest first. An item that is not listed, one tagged since, goes before
    /// the listed ones.
    public var itemOrder: [String]?
    /// When `itemOrder` was last set; with a stamp of its own, so a rename on one Mac and a move on another both
    /// survive. Sync compares it across Macs.
    public var itemOrderChangedAt: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        colorIndex: Int,
        changedAt: Date? = nil,
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

    /// `items` (newest first) in the order of this tag: the ones it does not list first, the last one tagged before
    /// the others (and as they come, the ones tagged at the same time or never stamped), then the listed ones in
    /// the order of the list.
    public func ordered(_ items: [ClipItem]) -> [ClipItem] {
        guard let itemOrder, !itemOrder.isEmpty else {
            return items
        }
        let positions = Dictionary(itemOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        // With the place each one comes in: the sort then gives the same order every time, whatever it does with
        // equal dates.
        let unlisted = items.enumerated().filter { positions[$0.element.contentHash] == nil }
            .sorted { lhs, rhs in
                let dates = (lhs.element.tagChangedAt ?? .distantPast, rhs.element.tagChangedAt ?? .distantPast)
                return dates.0 != dates.1
                    ? dates.0 > dates.1
                    : lhs.offset < rhs.offset
            }
            .map(\.element)
        let listed = items.filter { positions[$0.contentHash] != nil }
            .sorted { (positions[$0.contentHash] ?? 0) < (positions[$1.contentHash] ?? 0) }
        return unlisted + listed
    }
}
