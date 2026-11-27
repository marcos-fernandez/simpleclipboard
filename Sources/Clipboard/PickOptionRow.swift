import SwiftUI

/// A radio button with its explanation underneath. Put together here: in a grouped form the system's radio group
/// puts the buttons on the trailing edge and takes no second line.
struct PickOptionRow: View {
    let title: String
    let caption: String
    let isSelected: Bool
    let action: () -> Void

    /// Between the name of the option and its explanation.
    private static let captionSpacing: CGFloat = 2
    /// Between the parts of a notice placed under the text of an option.
    static let noticeSpacing: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: Self.captionSpacing) {
            RadioButton(title: title, isOn: isSelected, action: action)
                .fixedSize()
            Text(caption)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, RadioButton.titleInset)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
