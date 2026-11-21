import Foundation

/// Which keys, pressed while the keyboard is on the cards of the history, start a search.
public enum SearchKeys {
    /// The characters the keyboard gives to the keys that type nothing: the arrows, the function keys, forward
    /// delete (AppKit's function-key range, in the private use area of Unicode).
    private static let functionKeys: ClosedRange<UInt32> = 0xF700...0xF8FF

    /// Whether a key that gives `characters` goes to the search field. One that gives none is a dead key (the accent
    /// before a vowel): it types nothing yet, and the field has to be there to compose it with the next one.
    public static func typesText(_ characters: String?) -> Bool {
        guard let scalar = characters?.unicodeScalars.first else {
            return true
        }
        return !CharacterSet.controlCharacters.contains(scalar) && !functionKeys.contains(scalar.value)
    }
}
