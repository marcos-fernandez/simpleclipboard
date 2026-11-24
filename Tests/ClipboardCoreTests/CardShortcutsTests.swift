import Testing
@testable import ClipboardCore

/// A card shows the shortcut that picks it: the label painted and the key that acts must be the same position.
struct CardShortcutsTests {
    @Test func labelsFollowTheNumberRowFromOneToNine() {
        // The whole row: two digits swapped would paint a card with the shortcut of its neighbour.
        let labels = (0..<9).map { CardShortcuts.label(position: $0) }
        #expect(labels == ["⌘1", "⌘2", "⌘3", "⌘4", "⌘5", "⌘6", "⌘7", "⌘8", "⌘9"])
    }

    @Test func cardsBeyondTheDigitsHaveNoLabel() {
        #expect(CardShortcuts.label(position: 9) == nil)
        #expect(CardShortcuts.label(position: -1) == nil)
    }

    @Test(arguments: [(1, 0), (2, 1), (3, 2), (4, 3), (5, 4), (6, 5), (7, 6), (8, 7), (9, 8)])
    func eachDigitPicksTheCardThatShowsIt(digit: Int, position: Int) {
        #expect(CardShortcuts.position(digit: digit) == position)
        #expect(CardShortcuts.label(position: position) == "⌘\(digit)")
    }

    @Test func otherNumbersPickNothing() {
        // The 0 too: its key is the tenth of the row, and the strip shows nine cards.
        #expect(CardShortcuts.position(digit: 0) == nil)
        #expect(CardShortcuts.position(digit: 10) == nil)
        #expect(CardShortcuts.position(digit: -1) == nil)
    }

    @Test(arguments: [(6, 6), (9, 9), (14, 9), (0, 0), (-1, 0)])
    func onlyTheCardsThatFitHaveAShortcutUpToTheNineDigits(cardsThatFit: Int, expected: Int) {
        #expect(CardShortcuts.count(cardsThatFit: cardsThatFit) == expected)
    }
}
