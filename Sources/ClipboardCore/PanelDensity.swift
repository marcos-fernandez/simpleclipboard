/// How much room the history takes on the screen, by the size of its cards.
public enum PanelDensity: String, CaseIterable, Sendable {
    /// The cards at their full size.
    case comfortable
    /// Smaller cards: a lower strip, with more of them in view.
    case compact

    public var title: String {
        switch self {
        case .comfortable:
            return "Comfortable"
        case .compact:
            return "Compact"
        }
    }

    /// `stored`: the saved setting. Missing or unknown, it is `comfortable`: the size the cards had before the
    /// setting existed.
    public init(stored: String?) {
        self = stored.flatMap(PanelDensity.init(rawValue:)) ?? .comfortable
    }
}
