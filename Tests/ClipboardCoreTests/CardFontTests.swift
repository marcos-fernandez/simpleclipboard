import Testing
@testable import ClipboardCore

struct CardFontTests {
    @Test func aSavedChoiceIsReadBack() {
        // The texts as they are saved: renaming a case would send every saved choice back to the default.
        #expect(CardFont(stored: "monospaced") == .monospaced)
        #expect(CardFont(stored: "system") == .system)
        #expect(CardFont.monospaced.rawValue == "monospaced")
        #expect(CardFont.system.rawValue == "system")
    }

    @Test(arguments: [nil, "", "serif"])
    func withoutAKnownChoiceTheCardsKeepTheFontTheyHad(stored: String?) {
        #expect(CardFont(stored: stored) == .system)
    }
}
