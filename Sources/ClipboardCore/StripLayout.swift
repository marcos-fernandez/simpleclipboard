/// How many cards the history strip shows at once, and how wide each one is.
public struct StripLayout: Equatable, Sendable {
    public let cardCount: Int
    public let cardWidth: Double

    /// As many cards of `minCardWidth` as fit whole in `width`, at least one and at most `maxCardCount`, then
    /// widened to fill it: no card is cut at the edge, whatever the screen, and a very wide one shows larger cards
    /// and not more of them than there are shortcuts.
    public init(width: Double, minCardWidth: Double, spacing: Double, maxCardCount: Int) {
        let fitting = Int(((width + spacing) / (minCardWidth + spacing)).rounded(.down))
        let count = max(1, min(fitting, maxCardCount))
        let exact = (width - Double(count - 1) * spacing) / Double(count)
        cardCount = count
        // Down to half a point, a whole pixel of a Retina screen: rounded up, the last card would go past the edge.
        cardWidth = (exact * 2).rounded(.down) / 2
    }

    /// The position (from 0) of the first card in view once the card at `selected` has to be in view, with the card
    /// at `current` first until now and `cardCount` cards in view: the strip moves only as far as that card needs,
    /// so it stays still while the selection is among the cards in view.
    public static func leadingCard(current: Int, selected: Int, cardCount: Int) -> Int {
        let count = max(1, cardCount)
        if selected < current {
            return selected
        }
        if selected >= current + count {
            return selected - count + 1
        }
        return current
    }

    /// The position (from 0) a card dragged from `index` is dropped at, `distance` points away along the strip, where
    /// each card with the space after it takes `slotWidth`: the place of the card it is over by more than half,
    /// never past either end of the `itemCount` cards.
    public static func dropPosition(
        from index: Int, movedBy distance: Double, slotWidth: Double, itemCount: Int
    ) -> Int {
        guard slotWidth > 0, itemCount > 0 else {
            return index
        }
        let slots = (distance / slotWidth).rounded()
        // Compared as numbers before turning it into one: a distance beyond what an Int holds must not trap.
        let position = min(max(0, Double(index) + slots), Double(itemCount - 1))
        return Int(position)
    }

    /// The positions of the cards that a card dragged from `index` to `position` passes: the ones that move one
    /// place towards where it was, to make room for it. None when it has not left its place.
    public static func passedPositions(from index: Int, to position: Int) -> Range<Int> {
        position > index
            ? (index + 1)..<(position + 1)
            : position..<index
    }

    /// The position nearest to `index` that the strip can put first in view: with `itemCount` cards, the last
    /// `cardCount` fill the view, and none of them but the first can reach its leading edge.
    public static func reachableLeadingCard(_ index: Int, itemCount: Int, cardCount: Int) -> Int {
        min(max(0, index), max(0, itemCount - max(1, cardCount)))
    }
}
