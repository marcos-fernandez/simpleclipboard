import Testing
@testable import ClipboardCore

/// A card shows the shortcut that picks it: the label painted and the key that acts must be the same position.
struct CardShortcutsTests {
    @Test func labelsFollowTheNumberRowWithZeroLast() {
        // The whole row: two digits swapped would paint a card with the shortcut of its neighbour.
        let labels = (0..<10).map { CardShortcuts.label(position: $0) }
        #expect(labels == ["⌘1", "⌘2", "⌘3", "⌘4", "⌘5", "⌘6", "⌘7", "⌘8", "⌘9", "⌘0"])
    }

    @Test func cardsBeyondTheDigitsHaveNoLabel() {
        #expect(CardShortcuts.label(position: 10) == nil)
        #expect(CardShortcuts.label(position: -1) == nil)
    }

    @Test(arguments: [(1, 0), (2, 1), (3, 2), (4, 3), (5, 4), (6, 5), (7, 6), (8, 7), (9, 8), (0, 9)])
    func eachDigitPicksTheCardThatShowsIt(digit: Int, position: Int) {
        #expect(CardShortcuts.position(digit: digit) == position)
        #expect(CardShortcuts.label(position: position) == "⌘\(digit)")
    }

    @Test func otherNumbersPickNothing() {
        #expect(CardShortcuts.position(digit: 10) == nil)
        #expect(CardShortcuts.position(digit: -1) == nil)
    }

    @Test(arguments: [(6, 6), (10, 10), (14, 10), (0, 0), (-1, 0)])
    func onlyTheCardsThatFitHaveAShortcutUpToTheTenDigits(cardsThatFit: Int, expected: Int) {
        #expect(CardShortcuts.count(cardsThatFit: cardsThatFit) == expected)
    }
}
