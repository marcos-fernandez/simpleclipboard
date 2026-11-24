import Foundation
import Testing
@testable import ClipboardCore

struct PauseTests {
    private let end = Date(timeIntervalSince1970: 1_000_000)

    @Test func withoutAnEndThereIsNoPause() {
        #expect(!Pause.isActive(until: nil, now: end))
    }

    @Test func thePauseLastsUntilItsEnd() {
        #expect(Pause.isActive(until: end, now: end.addingTimeInterval(-1)))
        #expect(!Pause.isActive(until: end, now: end))
        #expect(!Pause.isActive(until: end, now: end.addingTimeInterval(1)))
    }

    @Test func anEndMuchFurtherAwayThanTheLongestPauseIsNoPause() {
        // The longest pause and an hour of slack.
        let furthest = 9.0 * 60 * 60
        #expect(Pause.isActive(until: end, now: end.addingTimeInterval(-furthest)))
        #expect(!Pause.isActive(until: end, now: end.addingTimeInterval(-furthest - 1)))
    }

    @Test func theLongestPauseHoldsWhenTheClockStepsBackALittle() {
        // Set for eight hours, and the clock is then corrected ten minutes back: it is still a pause.
        let longest = 8.0 * 60 * 60
        #expect(Pause.isActive(until: end, now: end.addingTimeInterval(-longest - 10 * 60)))
    }

    @Test func theDurationsGoFromShortestToLongest() {
        #expect(Pause.durations == Pause.durations.sorted())
    }

    @Test func aDurationIsNamedInMinutesOrInHours() {
        #expect(Pause.durations.map(Pause.title(of:)) == [
            "For 5 Minutes", "For 15 Minutes", "For 30 Minutes", "For 1 Hour", "For 4 Hours", "For 8 Hours",
        ])
    }
}
