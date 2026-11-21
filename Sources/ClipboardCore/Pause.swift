import Foundation

/// Recording stopped for a while ("Pause" in the menu-bar menu).
public enum Pause {
    /// What the menu offers, shortest first.
    public static let durations: [TimeInterval] = [5 * 60, 15 * 60, 30 * 60, 60 * 60, 4 * 60 * 60, 8 * 60 * 60]

    /// Whether recording is stopped at `now`. `until`: when the pause ends, nil without one.
    public static func isActive(until: Date?, now: Date) -> Bool {
        guard let until else {
            return false
        }
        return now < until
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
