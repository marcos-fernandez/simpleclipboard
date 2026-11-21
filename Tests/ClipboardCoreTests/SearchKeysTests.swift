import Testing
@testable import ClipboardCore

struct SearchKeysTests {
    @Test(arguments: ["a", "Z", "7", " ", ".", "ñ", "é", "あ"])
    func aKeyThatTypesStartsASearch(characters: String) {
        #expect(SearchKeys.typesText(characters))
    }

    @Test(arguments: ["", nil] as [String?])
    func aDeadKeyGoesToTheFieldToBeComposed(characters: String?) {
        // The accent of "á" comes alone and with no character: dropped, the search would start at a bare "a".
        #expect(SearchKeys.typesText(characters))
    }

    @Test(arguments: [
        "\t", "\r", "\u{3}", "\u{1B}", "\u{7F}", "\u{8}",
        // Up arrow, left arrow, F1 and forward delete.
        "\u{F700}", "\u{F702}", "\u{F704}", "\u{F728}",
    ])
    func aKeyThatTypesNothingIsLeftToThePanel(characters: String) {
        #expect(!SearchKeys.typesText(characters))
    }
}
