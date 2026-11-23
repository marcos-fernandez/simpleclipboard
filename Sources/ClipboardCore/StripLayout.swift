/// How many cards the history strip shows at once, and how wide each one is.
public struct StripLayout: Equatable, Sendable {
    public let cardCount: Int
    public let cardWidth: Double

    /// As many cards of `minCardWidth` as fit whole in `width`, at least one, then widened to fill it: no card is cut
    /// at the edge, whatever the screen.
    public init(width: Double, minCardWidth: Double, spacing: Double) {
        let fitting = Int(((width + spacing) / (minCardWidth + spacing)).rounded(.down))
        let count = max(1, fitting)
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

    /// The position nearest to `index` that the strip can put first in view: with `itemCount` cards, the last
    /// `cardCount` fill the view, and none of them but the first can reach its leading edge.
    public static func reachableLeadingCard(_ index: Int, itemCount: Int, cardCount: Int) -> Int {
        min(max(0, index), max(0, itemCount - max(1, cardCount)))
    }
}
