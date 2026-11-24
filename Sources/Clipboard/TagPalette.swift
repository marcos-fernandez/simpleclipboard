import ClipboardCore
import SwiftUI

/// What each colour of a tag looks like and is called, by the number a tag is saved with. Which numbers there are,
/// and the order they are offered in, is `TagColors` in the core; these two lists have one entry for each.
enum TagPalette {
    /// The colours of Finder's tags; the grey took the place of a mint, and a pink that came eighth is gone: it read
    /// as the red again.
    private static let colors: [Color] = [.red, .orange, .yellow, .green, .gray, .blue, .purple]
    private static let names = ["Red", "Orange", "Yellow", "Green", "Gray", "Blue", "Purple"]

    /// Grey for a number that has no colour, as the eighth a tag could be saved with.
    static func color(_ index: Int) -> Color {
        colors.indices.contains(index)
            ? colors[index]
            : .gray
    }

    static func name(_ index: Int) -> String {
        names.indices.contains(index)
            ? names[index]
            : "Gray"
    }
}
