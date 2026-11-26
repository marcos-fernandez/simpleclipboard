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
    func withoutAKnownChoiceTheCardsKeepTheSizeTheyHad(stored: String?) {
        #expect(PanelDensity(stored: stored) == .comfortable)
    }
}
