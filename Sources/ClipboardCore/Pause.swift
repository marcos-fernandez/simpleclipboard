import Foundation

/// Recording stopped for a while ("Pause" in the menu-bar menu).
public enum Pause {
    /// How far past the longest pause an end may be and still count. The clock can step back a little after the
    /// longest pause was set (a correction on wake, a change by hand): without slack that pause would be taken for
    /// none, and what is copied during a pause that was asked for would be recorded.
    private static let clockSlack: TimeInterval = 60 * 60
    /// What the menu offers, shortest first.
    public static let durations: [TimeInterval] = [5 * 60, 15 * 60, 30 * 60, 60 * 60, 4 * 60 * 60, 8 * 60 * 60]

    /// Whether recording is stopped at `now`. `until`: when the pause ends, nil without one. An end much further
    /// away than the longest pause is not one the menu set (the clock was moved back by days, the value was written
    /// by hand): it is no pause, rather than one that stops recording for days while the menu only says an hour.
    public static func isActive(until: Date?, now: Date) -> Bool {
        guard let until, let longest = durations.max() else {
            return false
        }
        return now < until && until.timeIntervalSince(now) <= longest + clockSlack
    }

    /// How the menu names a duration: in minutes under an hour, in whole hours from there.
    public static func title(of duration: TimeInterval) -> String {
        let minutes = Int(duration / 60)
        guard minutes >= 60 else {
            return "For \(minutes) Minutes"
        }
        let hours = minutes / 60
        return hours == 1
            ? "For 1 Hour"
            : "For \(hours) Hours"
    }
}
