import Testing
@testable import ClipboardCore

/// The lists decide what never reaches the history and what is kept hidden: an app lost from one would have its
/// copies recorded as any other.
struct AppListTests {
    @Test func withoutASavedListTheDefaultsAreListed() {
        #expect(AppList.list(stored: nil, defaults: ["com.b", "com.a"]) == ["com.a", "com.b"])
    }

    @Test func aSavedEmptyListStaysEmpty() {
        // The user removed every app, the default ones too: they must not come back at the next launch.
        #expect(AppList.list(stored: [], defaults: ["com.a"]) == [])
    }

    @Test func aSavedListIsNotMixedWithTheDefaults() {
        #expect(AppList.list(stored: ["com.b"], defaults: ["com.a"]) == ["com.b"])
    }

    @Test func aSavedListWithARepeatedAppListsItOnce() {
        #expect(AppList.list(stored: ["com.a", "com.b", "com.a"], defaults: []) == ["com.a", "com.b"])
    }

    @Test func anAppAlreadyInTheListIsNotAddedAgain() {
        #expect(AppList.adding(["com.a", "com.b", "com.b"], to: ["com.a"]) == ["com.a", "com.b"])
    }

    @Test func addingAppsLeavesOutTheOnesOfTheOtherListAndNamesThem() {
        let addition = AppList.addition(of: ["com.a", "com.b", "com.c"], to: ["com.x"], other: ["com.c", "com.a"])
        #expect(addition == AppList.Addition(list: ["com.x", "com.b"], refused: ["com.a", "com.c"]))
    }

    @Test func addingOnlyAppsOfTheOtherListSavesNothing() {
        let addition = AppList.addition(of: ["com.a"], to: ["com.x"], other: ["com.a"])
        #expect(addition == AppList.Addition(list: nil, refused: ["com.a"]))
    }

    @Test func addingAppsTheListAlreadyHasSavesNothing() {
        // A saved list no longer follows its defaults: choosing an app that is there must not save it.
        let addition = AppList.addition(of: ["com.x", "com.x"], to: ["com.x"], other: [])
        #expect(addition == AppList.Addition(list: nil, refused: []))
    }

    @Test func anAppChosenTwiceIsRefusedOnce() {
        #expect(AppList.addition(of: ["com.a", "com.a"], to: [], other: ["com.a"]).refused == ["com.a"])
    }

    @Test func theAppsOfTheOtherListAreLeftOut() {
        #expect(AppList.excluding(["com.b"], from: ["com.a", "com.b", "com.c"]) == ["com.a", "com.c"])
        #expect(AppList.excluding([], from: ["com.a"]) == ["com.a"])
    }

    @Test func removingAnAppLeavesTheOthersInPlace() {
        #expect(AppList.removing("com.b", from: ["com.a", "com.b", "com.c"]) == ["com.a", "com.c"])
    }

    @Test func removingAnAppThatIsNotThereChangesNothing() {
        #expect(AppList.removing("com.z", from: ["com.a"]) == ["com.a"])
    }
}
