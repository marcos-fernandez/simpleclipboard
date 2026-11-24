import SwiftUI

/// The dot of a tag, before its name.
struct TagDot: View {
    let color: Color
    let size: CGFloat

    /// In a dialog, beside text of the size of a body.
    static let dialogSize: CGFloat = 12
    /// Beside the small text of a tab.
    static let tabSize: CGFloat = 8

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
