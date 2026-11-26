/// The font of the text of a card.
public enum CardFont: String, CaseIterable, Sendable {
    /// The system's font.
    case system
    /// The system's monospaced font: columns and code keep their shape.
    case monospaced

    public var title: String {
        switch self {
        case .system:
            return "System"
        case .monospaced:
            return "Monospaced"
        }
    }

    /// `stored`: the saved setting. Missing or unknown, it is `system`: the font the cards had before the setting
    /// existed.
    public init(stored: String?) {
        self = stored.flatMap(CardFont.init(rawValue:)) ?? .system
    }
}
