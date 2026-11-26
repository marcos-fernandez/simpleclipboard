import ClipboardCore
import SwiftUI

/// A size of the cards to choose, as a small picture of the history with cards of that size and its name under it.
struct DensityTile: View {
    let density: PanelDensity
    let isSelected: Bool
    let action: () -> Void

    private static let cardCornerRadius: CGFloat = 3
    private static let cardSpacing: CGFloat = 4
    private static let cornerRadius: CGFloat = 8
    private static let padding: CGFloat = 6
    private static let selectionStroke: CGFloat = 2
    private static let size = CGSize(width: 104, height: 68)
    /// Between the picture and the name.
    private static let titleSpacing: CGFloat = 6

    /// The cards drawn in the picture: fewer and larger, or more and smaller.
    private var cardCount: Int {
        switch density {
        case .comfortable:
            return 2
        case .compact:
            return 3
        }
    }

    /// Of a card of the picture, in the proportion its header has in a card of the history.
    private var cardHeaderHeight: CGFloat {
        cardHeight * density.cardHeaderHeight / density.cardHeight
    }

    /// Of a card of the picture, in the proportion the two sizes have in the history.
    private var cardHeight: CGFloat {
        (Self.size.height - 2 * Self.padding) * density.cardHeight / PanelDensity.comfortable.cardHeight
    }

    var body: some View {
        let traits: AccessibilityTraits = isSelected
            ? .isSelected
            : []
        return Button(action: action) {
            VStack(spacing: Self.titleSpacing) {
                picture
                Text(density.title)
            }
            // The whole tile is the target, not only the drawn parts.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(traits)
    }

    /// The cards at the bottom, as the history is at the bottom of the screen.
    private var picture: some View {
        HStack(spacing: Self.cardSpacing) {
            ForEach(0..<cardCount, id: \.self) { _ in
                VStack(spacing: 0) {
                    Color.secondary.opacity(0.45)
                        .frame(height: cardHeaderHeight)
                    Color.secondary.opacity(0.2)
                }
                .frame(height: cardHeight)
                .clipShape(RoundedRectangle(cornerRadius: Self.cardCornerRadius))
            }
        }
        .padding(Self.padding)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .bottom)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: Self.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Self.cornerRadius)
                .strokeBorder(
                    isSelected
                        ? AnyShapeStyle(Color.accentColor)
                        : AnyShapeStyle(.quaternary),
                    lineWidth: isSelected
                        ? Self.selectionStroke
                        : 1
                )
        }
    }
}
