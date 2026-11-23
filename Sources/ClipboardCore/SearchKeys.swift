import Foundation

/// Which keys, pressed while the keyboard is on the cards of the history, start a search, and what counts as one.
public enum SearchKeys {
    /// The edit shortcuts, by the letter pressed with ⌘, that are for the search field wherever the keyboard is:
    /// paste, select all and undo (with ⇧, redo). Not copy and cut: on the cards there is no selected text.
    private static let editShortcutsOfTheField: Set<String> = ["a", "v", "z"]
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

    /// Whether ⌘ with the key that gives `key` takes the keyboard to the search field before it acts. ⇧⌘V, the
    /// history and then ⌘V is how something just copied is looked for: with the keyboard on the cards the paste
    /// would go to nobody.
    public static func isEditShortcutOfTheField(_ key: String?) -> Bool {
        key.map { editShortcutsOfTheField.contains($0.lowercased()) } ?? false
    }

    /// Whether `query` is a search. One of only blanks is none: it finds what no search finds, so Esc closes
    /// instead of clearing it, it is not kept for the next opening and nothing is "not found".
    public static func isSearch(_ query: String) -> Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
