import ClipboardCore
import SwiftUI

/// The measures of the history strip and of its cards, in points. In one place because they depend on each other:
/// `StripLayout` is given the room these leave for the cards, and the views draw with the same numbers.
enum PanelMetrics {
    static let cardCornerRadius: CGFloat = 12
    static let cardFooterHeight: CGFloat = 24
    /// How much of the colour of its tag, or of its app, the header of a card takes: a tint, light enough for the
    /// text over it to be read on any of the colours.
    static let cardHeaderTint: CGFloat = 0.45
    static let cardPadding: CGFloat = 8
    /// The border of the selected card, drawn half inside and half outside it.
    static let cardSelectionStroke: CGFloat = 3
    static let cardSpacing: CGFloat = 12
    /// How much is left of the icon of the menu button while paused.
    static let menuIconDimming: CGFloat = 0.4
    /// Around the row of cards, inside the strip's padding: room for the stroke of the selected card.
    static let rowInset: CGFloat = 4
    /// The row of the search field and the tabs, and the buttons at its ends, the menu and the share one: as
    /// much is kept clear at both ends of the row, so that the field and the tabs stay centred.
    static let searchRowHeight: CGFloat = 30
    /// Between the search field and the tabs, and between them and the buttons at the ends of the row.
    static let searchRowSpacing: CGFloat = 12
    static let stripPadding: CGFloat = 16
    /// Between the search row and the cards.
    static let stripSpacing: CGFloat = 12
    static let textFontSize: CGFloat = 12
    /// Of either font of a card (`CardFont`) at `textFontSize`: to be measured again if that size, or the fonts,
    /// ever change.
    static let textLineHeight: CGFloat = 15

    /// What the strip is made of from top to bottom, with room above and below the cards for the border of the
    /// selected one. Derived: a taller card must not push its footer out of the strip.
    static func stripHeight(density: PanelDensity) -> CGFloat {
        2 * stripPadding + searchRowHeight + stripSpacing + density.cardHeight + 2 * cardSelectionStroke
    }

    /// The lines of text that fit between the header and the footer of a card.
    static func textLineLimit(density: PanelDensity) -> Int {
        Int((density.cardHeight - density.cardHeaderHeight - cardFooterHeight - 2 * cardPadding) / textLineHeight)
    }

    /// The room that a strip of `stripWidth` leaves for its row of cards.
    static func cardRowWidth(stripWidth: CGFloat) -> CGFloat {
        stripWidth - 2 * (stripPadding + rowInset)
    }
}

extension CardFont {
    /// For the text of a card.
    var font: Font {
        switch self {
        case .system:
            return .system(size: PanelMetrics.textFontSize)
        case .monospaced:
            return .system(size: PanelMetrics.textFontSize, design: .monospaced)
        }
    }
}
