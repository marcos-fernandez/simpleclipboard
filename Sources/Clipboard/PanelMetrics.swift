import AppKit
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

    /// What the strip is made of from top to bottom, with room above and below the cards for the border of the
    /// selected one. Derived: a taller card must not push its footer out of the strip.
    static func stripHeight(density: PanelDensity) -> CGFloat {
        2 * stripPadding + searchRowHeight + stripSpacing + density.cardHeight + 2 * cardSelectionStroke
    }

    /// The lines of text that fit between the header and the footer of a card.
    @MainActor
    static func textLineLimit(density: PanelDensity, font: CardFont) -> Int {
        Int((density.cardHeight - density.cardHeaderHeight - cardFooterHeight - 2 * cardPadding) / font.lineHeight)
    }

    /// The room that a strip of `stripWidth` leaves for its row of cards.
    static func cardRowWidth(stripWidth: CGFloat) -> CGFloat {
        stripWidth - 2 * (stripPadding + rowInset)
    }
}

/// The measures that change with the size of the cards: each one that of the comfortable size, scaled. The footer
/// and the text of a card are the same at any size, so that they stay as easy to read.
extension PanelDensity {
    var cardHeaderHeight: CGFloat {
        scaled(48)
    }

    var cardHeight: CGFloat {
        scaled(240)
    }

    var cardIconSize: CGFloat {
        scaled(24)
    }

    /// The cards are widened from this to fill the strip (see `StripLayout`).
    var minCardWidth: CGFloat {
        scaled(220)
    }

    /// How much of the comfortable size the cards keep.
    private var scale: CGFloat {
        switch self {
        case .comfortable:
            return 1
        case .compact:
            return 0.75
        }
    }

    /// To whole points: a card drawn on half a point is blurred on a screen that is not Retina.
    private func scaled(_ measure: CGFloat) -> CGFloat {
        (measure * scale).rounded()
    }
}

extension CardFont {
    @MainActor
    private static let layoutManager = NSLayoutManager()

    /// For the text of a card.
    var font: Font {
        Font(nsFont)
    }

    /// Of a line of text in it: how many lines fit in a card comes from it.
    @MainActor
    var lineHeight: CGFloat {
        Self.layoutManager.defaultLineHeight(for: nsFont)
    }

    /// The one font of each choice: the text is drawn and its lines are measured with the same.
    private var nsFont: NSFont {
        switch self {
        case .system:
            return .systemFont(ofSize: PanelMetrics.textFontSize)
        case .monospaced:
            return .monospacedSystemFont(ofSize: PanelMetrics.textFontSize, weight: .regular)
        }
    }
}
