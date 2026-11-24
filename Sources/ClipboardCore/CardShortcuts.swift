/// The shortcuts that pick the cards in view of the history strip: ⌘ with a digit, in the order of the number row.
/// They follow the strip as it scrolls: ⌘1 is always the first card in view.
public enum CardShortcuts {
    /// Without the 0: its key comes after the 9 and would be the tenth, but its number says otherwise. The strip
    /// shows no more cards than these (see `StripLayout`).
    public static let digits = [1, 2, 3, 4, 5, 6, 7, 8, 9]

    /// How many cards, from the first in view, have a shortcut: the ones that fit on the screen, as far as there are
    /// digits. A card that is off the screen has none: its shortcut would paste something the user does not see.
    public static func count(cardsThatFit: Int) -> Int {
        min(max(0, cardsThatFit), digits.count)
    }

    /// What the card at `position` (from 0, the first in view) shows as its shortcut; nil beyond the digits.
    public static func label(position: Int) -> String? {
        guard digits.indices.contains(position) else {
            return nil
        }
        return "⌘\(digits[position])"
    }

    /// The position (from 0, the first in view) of the card that ⌘ with `digit` picks; nil for anything that is not
    /// one of the digits.
    public static func position(digit: Int) -> Int? {
        digits.firstIndex(of: digit)
    }
}
