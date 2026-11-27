import Foundation

/// A named, coloured collection. Tagged items never expire.
public struct Tag: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    /// Index into the fixed palette, 0..<Config.tagColorCount.
    public var colorIndex: Int
    /// Last create, rename or recolour; nil in tags saved before sync existed. Sync compares it across Macs.
    public var changedAt: Date?
    /// The order of its items, as content hashes (an item has no other identity across Macs); nil in a tag saved
    /// before its items had an order, which are then newest first. `HistoryStore` writes every item of the tag in
    /// it; one that is not listed all the same (tagged on a Mac that knows nothing of the order) goes before the
    /// listed ones.
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

    /// `items` (newest first) in the order of this tag: the ones it does not list first, as they come, then the
    /// listed ones in the order of the list.
    public func ordered(_ items: [ClipItem]) -> [ClipItem] {
        guard let itemOrder, !itemOrder.isEmpty else {
            return items
        }
        let positions = Dictionary(itemOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let unlisted = items.filter { positions[$0.contentHash] == nil }
        // With the place each one has in the list: no two are the same, so the sort gives one order only.
        let listed = items.compactMap { item in positions[item.contentHash].map { (item: item, position: $0) } }
            .sorted { $0.position < $1.position }
            .map(\.item)
        return unlisted + listed
    }
}
