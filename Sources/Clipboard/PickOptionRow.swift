import SwiftUI

/// A radio button with its explanation underneath. Drawn here: in a grouped form the system's radio group puts the
/// buttons on the trailing edge and takes no second line.
struct PickOptionRow: View {
    let title: String
    let caption: String
    let isSelected: Bool
    let action: () -> Void

    /// Between the name of the option and its explanation.
    private static let captionSpacing: CGFloat = 2
    /// Between the button and its text; also what lines up something placed under the text.
    static let spacing: CGFloat = 8

    var body: some View {
        let symbol = isSelected
            ? "circle.inset.filled"
            : "circle"
        let symbolColor = isSelected
            ? Color.accentColor
            : Color.secondary
        let traits: AccessibilityTraits = isSelected
            ? .isSelected
            : []
        return Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: Self.spacing) {
                Image(systemName: symbol)
                    .foregroundStyle(symbolColor)
                VStack(alignment: .leading, spacing: Self.captionSpacing) {
                    Text(title)
                    Text(caption)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            // The whole row is the target, not only the drawn parts.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(traits)
    }
}
