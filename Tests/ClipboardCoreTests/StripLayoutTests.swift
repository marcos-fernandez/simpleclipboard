import Testing
@testable import ClipboardCore

/// The cards are picked with ⌘ and a number, so the strip must show whole cards only: a shortcut for a card that is
/// cut at the edge, or off the screen, pastes something the user does not see.
struct StripLayoutTests {
    private static let maxCardCount = 9
    private static let minCardWidth = 220.0
    private static let spacing = 12.0

    private func layout(width: Double) -> StripLayout {
        StripLayout(
            width: width, minCardWidth: Self.minCardWidth, spacing: Self.spacing, maxCardCount: Self.maxCardCount
        )
    }

    @Test(arguments: [
        // The room left for the cards on screens 1512, 1920 and 2560 pt wide: the screen less 56 pt of margins
        // (see `PanelMetrics.cardRowWidth` in the app, and its margin around the strip).
        (1456.0, 6, 232.5),
        (1864.0, 8, 222.5),
        // Room for ten: nine are shown, wider.
        (2504.0, 9, 267.5),
    ])
    func widerScreensShowMoreCards(width: Double, count: Int, cardWidth: Double) {
        let layout = layout(width: width)
        #expect(layout.cardCount == count)
        #expect(layout.cardWidth == cardWidth)
    }

    @Test func cardsFillTheWidthWithoutGoingPastIt() {
        for width in stride(from: 300.0, through: 4000.0, by: 7.0) {
            let layout = layout(width: width)
            let used = Double(layout.cardCount) * layout.cardWidth + Double(layout.cardCount - 1) * Self.spacing
            #expect(used <= width, "width \(width)")
            // Less than half a point is lost to the rounding of each card.
            #expect(width - used < Double(layout.cardCount) / 2, "width \(width)")
        }
    }

    @Test func noScreenShowsMoreCardsThanTheMost() {
        for width in stride(from: 2000.0, through: 8000.0, by: 250.0) {
            #expect(layout(width: width).cardCount <= Self.maxCardCount, "width \(width)")
        }
    }

    @Test func cardsAreNeverNarrowerThanTheMinimumWhileOneFits() {
        for width in stride(from: 220.0, through: 4000.0, by: 7.0) {
            #expect(layout(width: width).cardWidth >= Self.minCardWidth, "width \(width)")
        }
    }

    @Test func oneMoreCardAppearsExactlyWhenItFitsWhole() {
        // Two cards and the gap between them. Half a point short of that, only one fits.
        let twoCards = 2 * Self.minCardWidth + Self.spacing
        #expect(layout(width: twoCards - 0.5).cardCount == 1)
        #expect(layout(width: twoCards).cardCount == 2)
        #expect(layout(width: twoCards).cardWidth == Self.minCardWidth)
    }

    @Test func roomForLessThanOneCardStillShowsOne() {
        let layout = layout(width: 100)
        #expect(layout.cardCount == 1)
        #expect(layout.cardWidth == 100)
    }

    // MARK: the first card in view

    @Test(arguments: [0, 3, 5])
    func stripStaysStillWhileTheSelectionIsInView(selected: Int) {
        #expect(StripLayout.leadingCard(current: 0, selected: selected, cardCount: 6) == 0)
        #expect(StripLayout.leadingCard(current: 4, selected: selected + 4, cardCount: 6) == 4)
    }

    @Test func selectionPastTheLastCardInViewBecomesTheLastOne() {
        #expect(StripLayout.leadingCard(current: 0, selected: 6, cardCount: 6) == 1)
        #expect(StripLayout.leadingCard(current: 0, selected: 20, cardCount: 6) == 15)
    }

    @Test func selectionBeforeTheFirstCardInViewBecomesTheFirstOne() {
        #expect(StripLayout.leadingCard(current: 4, selected: 3, cardCount: 6) == 3)
        #expect(StripLayout.leadingCard(current: 15, selected: 0, cardCount: 6) == 0)
    }

    @Test func stripThatShowsNoCardStillFollowsTheSelection() {
        #expect(StripLayout.leadingCard(current: 0, selected: 2, cardCount: 0) == 2)
    }

    @Test func stripOfOneCardMovesWithEverySelection() {
        #expect(StripLayout.leadingCard(current: 3, selected: 4, cardCount: 1) == 4)
        #expect(StripLayout.leadingCard(current: 3, selected: 2, cardCount: 1) == 2)
    }

    @Test func cardsThatFillTheEndOfTheStripCannotBeFirstInView() {
        // 8 cards, 6 in view: the strip stops with the third card first, so a shortcut counted from a later one
        // would leave the first cards in view without theirs.
        #expect(StripLayout.reachableLeadingCard(2, itemCount: 8, cardCount: 6) == 2)
        #expect(StripLayout.reachableLeadingCard(3, itemCount: 8, cardCount: 6) == 2)
        #expect(StripLayout.reachableLeadingCard(7, itemCount: 8, cardCount: 6) == 2)
    }

    @Test func listThatFitsInViewAlwaysStartsAtItsFirstCard() {
        #expect(StripLayout.reachableLeadingCard(3, itemCount: 4, cardCount: 6) == 0)
        #expect(StripLayout.reachableLeadingCard(0, itemCount: 0, cardCount: 6) == 0)
        #expect(StripLayout.reachableLeadingCard(-1, itemCount: 8, cardCount: 6) == 0)
    }
}
