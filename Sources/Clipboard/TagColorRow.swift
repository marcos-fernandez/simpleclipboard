import ClipboardCore
import SwiftUI

/// The colours a tag can have, as dots in a row, the one it has ringed. In the menu of a tag's tab and in the
/// overlay of a new tag.
struct TagColorRow: View {
    let selected: Int
    /// What is left before the first dot and after the last.
    let inset: CGFloat
    let onPick: (Int) -> Void

    /// Larger than the dot of a tag beside its name (`TagDot`): these are buttons.
    private static let dotSize: CGFloat = 16
    private static let dotSpacing: CGFloat = 6
    /// What a menu leaves before the text of its items.
    static let menuInset: CGFloat = 14
    private static let ringGap: CGFloat = 2
    private static let ringWidth: CGFloat = 2
    private static let verticalInset: CGFloat = 4

    var body: some View {
        HStack(spacing: Self.dotSpacing) {
            ForEach(TagColors.order, id: \.self) { index in
                Button {
                    onPick(index)
                } label: {
                    Circle()
                        .fill(TagPalette.color(index))
                        .frame(width: Self.dotSize, height: Self.dotSize)
                        .padding(Self.ringGap + Self.ringWidth)
                        .overlay {
                            if index == selected {
                                Circle()
                                    .strokeBorder(Color.primary.opacity(0.6), lineWidth: Self.ringWidth)
                            }
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(TagPalette.name(index))
                .accessibilityAddTraits(
                    index == selected
                        ? .isSelected
                        : []
                )
            }
        }
        .padding(.horizontal, inset)
        .padding(.vertical, Self.verticalInset)
    }
}
