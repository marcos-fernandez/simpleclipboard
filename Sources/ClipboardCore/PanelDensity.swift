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

    /// `stored`: the saved setting. Missing or unknown, it is `comfortable`, the default.
    public init(stored: String?) {
        self = stored.flatMap(PanelDensity.init(rawValue:)) ?? .comfortable
    }
}

/// The measures that change with the size of the cards, in points: each one that of the comfortable size, scaled.
/// The footer and the text of a card are the same at any size, so that they stay as easy to read.
extension PanelDensity {
    public var cardHeaderHeight: Double {
        scaled(48)
    }

    public var cardHeight: Double {
        scaled(240)
    }

    public var cardIconSize: Double {
        scaled(24)
    }

    /// The cards are widened from this to fill the strip (see `StripLayout`).
    public var minCardWidth: Double {
        scaled(220)
    }

    /// How much of the comfortable size the cards keep.
    private var scale: Double {
        switch self {
        case .comfortable:
            return 1
        case .compact:
            return 0.75
        }
    }

    /// To whole points: a card drawn on half a point is blurred on a screen that is not Retina.
    private func scaled(_ measure: Double) -> Double {
        (measure * scale).rounded()
    }
}
