import CoreGraphics

/// The measures of the history strip and of its cards, in points. In one place because they depend on each other:
/// `StripLayout` is given the room these leave for the cards, and the views draw with the same numbers.
enum PanelMetrics {
    static let cardCornerRadius: CGFloat = 12
    static let cardFooterHeight: CGFloat = 24
    static let cardHeaderHeight: CGFloat = 48
    /// How much of the colour of its tag, or of its app, the header of a card takes: a tint, light enough for the
    /// text over it to be read on any of the colours.
    static let cardHeaderTint: CGFloat = 0.45
    static let cardHeight: CGFloat = 220
    static let cardIconSize: CGFloat = 24
    static let cardPadding: CGFloat = 8
    /// The border of the selected card, drawn half inside and half outside it.
    static let cardSelectionStroke: CGFloat = 3
    static let cardSpacing: CGFloat = 12
    /// The cards are widened from this to fill the strip (see `StripLayout`).
    static let minCardWidth: CGFloat = 220
    /// Around the row of cards, inside the strip's padding: room for the stroke of the selected card.
    static let rowInset: CGFloat = 4
    /// The row of the search field and the tabs.
    static let searchRowHeight: CGFloat = 30
    /// Between the search field, the tabs and the share button.
    static let searchRowSpacing: CGFloat = 12
    /// The share button at the end of the search row, and what is kept clear for it at both ends of the row, so
    /// that the field and the tabs stay centred.
    static let shareButtonSize: CGFloat = 28
    static let stripPadding: CGFloat = 16
    /// Between the search row and the cards.
    static let stripSpacing: CGFloat = 12
    static let textFontSize: CGFloat = 12
    /// Of the system font at `textFontSize`.
    static let textLineHeight: CGFloat = 15

    /// What the strip is made of from top to bottom, with room above and below the cards for the border of the
    /// selected one. Derived: a taller card must not push its footer out of the strip.
    static var stripHeight: CGFloat {
        2 * stripPadding + searchRowHeight + stripSpacing + cardHeight + 2 * cardSelectionStroke
    }

    /// The lines of text that fit between the header and the footer of a card.
    static var textLineLimit: Int {
        Int((cardHeight - cardHeaderHeight - cardFooterHeight - 2 * cardPadding) / textLineHeight)
    }

    /// The room that a strip of `stripWidth` leaves for its row of cards.
    static func cardRowWidth(stripWidth: CGFloat) -> CGFloat {
        stripWidth - 2 * (stripPadding + rowInset)
    }
}
