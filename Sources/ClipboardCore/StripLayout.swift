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
}
