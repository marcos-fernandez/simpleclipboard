import Testing
@testable import ClipboardCore

struct MenuBarIconTests {
    @Test func withoutASavedChoiceTheIconIsShownAsBeforeTheSettingExisted() {
        #expect(MenuBarIcon.isShown(stored: nil, hotkeyRegistered: true))
    }

    @Test func theSavedChoiceIsFollowedWhileTheHotkeyWorks() {
        #expect(MenuBarIcon.isShown(stored: true, hotkeyRegistered: true))
        #expect(!MenuBarIcon.isShown(stored: false, hotkeyRegistered: true))
    }

    @Test func withoutTheHotkeyTheIconIsShownWhateverTheChoice() {
        // Hidden, nothing would open the history or the menu.
        #expect(MenuBarIcon.isShown(stored: false, hotkeyRegistered: false))
        #expect(MenuBarIcon.isShown(stored: nil, hotkeyRegistered: false))
    }
}
