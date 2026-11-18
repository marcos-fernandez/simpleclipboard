import ClipboardCore
import SwiftUI

/// The only place tag colours are defined. Same size as Config.tagColorCount.
enum TagPalette {
    static let colors: [Color] = [.red, .orange, .yellow, .green, .mint, .blue, .purple, .pink]
    static let names = ["Red", "Orange", "Yellow", "Green", "Mint", "Blue", "Purple", "Pink"]

    static func color(_ index: Int) -> Color {
        colors.indices.contains(index)
            ? colors[index]
            : .gray
    }
}
