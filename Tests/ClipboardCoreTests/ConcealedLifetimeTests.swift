import Foundation
import Testing
@testable import ClipboardCore

struct ConcealedLifetimeTests {
    @Test func withoutASavedValueItIsTheOneOfConfig() {
        #expect(ConcealedLifetime.lifetime(stored: nil) == Config.concealedLifetime)
    }

    @Test(arguments: ConcealedLifetime.choices)
    func aSavedChoiceIsUsed(choice: TimeInterval) {
        #expect(ConcealedLifetime.lifetime(stored: choice) == choice)
    }

    @Test(arguments: [0, -60, 61, 7 * 24 * 60 * 60])
    func aSavedValueThatIsNoChoiceIsTheOneOfConfig(stored: TimeInterval) {
        #expect(ConcealedLifetime.lifetime(stored: stored) == Config.concealedLifetime)
    }

    @Test func theChoicesGoFromShortestToLongest() {
        #expect(ConcealedLifetime.choices == ConcealedLifetime.choices.sorted())
    }

    @Test func aLifetimeIsNamedInMinutes() {
        #expect(ConcealedLifetime.title(of: 60) == "1 minute")
        #expect(ConcealedLifetime.title(of: 600) == "10 minutes")
    }

    @Test func theOneOfConfigIsAChoice() {
        // Otherwise the settings would show no selection on a new install.
        #expect(ConcealedLifetime.choices.contains(Config.concealedLifetime))
    }
}
