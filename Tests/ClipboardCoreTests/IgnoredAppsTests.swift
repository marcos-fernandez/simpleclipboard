import Testing
@testable import ClipboardCore

/// The list decides what never reaches the history: an app lost from it would have its copies recorded.
struct IgnoredAppsTests {
    @Test func withoutASavedListKeychainAccessIsIgnoredAsBeforeTheSettingExisted() {
        #expect(IgnoredApps.list(stored: nil) == ["com.apple.keychainaccess"])
    }

    @Test func aSavedEmptyListStaysEmpty() {
        // The user removed every app, the default one too: it must not come back at the next launch.
        #expect(IgnoredApps.list(stored: []) == [])
    }

    @Test func aSavedListWithARepeatedAppListsItOnce() {
        #expect(IgnoredApps.list(stored: ["com.a", "com.b", "com.a"]) == ["com.a", "com.b"])
    }

    @Test func anAppAlreadyInTheListIsNotAddedAgain() {
        #expect(IgnoredApps.adding(["com.a", "com.b", "com.b"], to: ["com.a"]) == ["com.a", "com.b"])
    }

    @Test func removingAnAppLeavesTheOthersInPlace() {
        #expect(IgnoredApps.removing("com.b", from: ["com.a", "com.b", "com.c"]) == ["com.a", "com.c"])
    }

    @Test func removingAnAppThatIsNotThereChangesNothing() {
        #expect(IgnoredApps.removing("com.z", from: ["com.a"]) == ["com.a"])
    }
}
