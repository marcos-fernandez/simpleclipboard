import Testing
@testable import ClipboardCore

struct PickActionTests {
    @Test func aSavedChoiceIsReadBack() {
        // The texts as they are saved: renaming a case would send every saved choice back to the default.
        #expect(PickAction(stored: "copyToClipboard") == .copyToClipboard)
        #expect(PickAction(stored: "pasteDirectly") == .pasteDirectly)
        #expect(PickAction.copyToClipboard.rawValue == "copyToClipboard")
        #expect(PickAction.pasteDirectly.rawValue == "pasteDirectly")
    }

    @Test func withoutASavedChoiceItemsArePastedAsBeforeTheSettingExisted() {
        #expect(PickAction(stored: nil) == .pasteDirectly)
    }

    @Test func theWelcomeOfANewInstallStartsOnCopying() {
        #expect(PickAction.atWelcome(isNewInstall: true, stored: nil) == .copyToClipboard)
    }

    @Test(arguments: [
        (nil, .pasteDirectly), ("pasteDirectly", .pasteDirectly), ("copyToClipboard", .copyToClipboard),
    ] as [(String?, PickAction)])
    func theWelcomeOfAnInstallThatRanBeforeStartsOnWhatItWasDoing(stored: String?, expected: PickAction) {
        // Without a saved choice it was pasting: the welcome must not move it to copying.
        #expect(PickAction.atWelcome(isNewInstall: false, stored: stored) == expected)
    }

    @Test func anUnknownSavedChoiceFallsBackToPasting() {
        // A value written by a newer version this one does not know.
        #expect(PickAction(stored: "somethingElse") == .pasteDirectly)
    }
}
