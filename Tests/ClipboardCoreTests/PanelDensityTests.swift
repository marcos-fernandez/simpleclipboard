import Testing
@testable import ClipboardCore

struct PanelDensityTests {
    @Test func aSavedChoiceIsReadBack() {
        // The texts as they are saved: renaming a case would send every saved choice back to the default.
        #expect(PanelDensity(stored: "comfortable") == .comfortable)
        #expect(PanelDensity(stored: "compact") == .compact)
        #expect(PanelDensity.comfortable.rawValue == "comfortable")
        #expect(PanelDensity.compact.rawValue == "compact")
    }

    @Test(arguments: [nil, "", "dense"])
    func withoutAKnownChoiceTheCardsAreOfTheDefaultSize(stored: String?) {
        #expect(PanelDensity(stored: stored) == .comfortable)
    }

    @Test func theComfortableCardsHaveTheirFullMeasures() {
        #expect(PanelDensity.comfortable.cardHeaderHeight == 48)
        #expect(PanelDensity.comfortable.cardHeight == 240)
        #expect(PanelDensity.comfortable.cardIconSize == 24)
        #expect(PanelDensity.comfortable.minCardWidth == 220)
    }

    // Three quarters of each, in whole points.
    @Test func theCompactCardsAreSmallerInEveryMeasure() {
        #expect(PanelDensity.compact.cardHeaderHeight == 36)
        #expect(PanelDensity.compact.cardHeight == 180)
        #expect(PanelDensity.compact.cardIconSize == 18)
        #expect(PanelDensity.compact.minCardWidth == 165)
    }
}
