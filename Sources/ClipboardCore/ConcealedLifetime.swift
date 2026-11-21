import Foundation

/// How long what is copied from a secured app is kept ("Keep For" under "Secured Apps" in the settings).
public enum ConcealedLifetime {
    /// What the settings offer, shortest first. The one of `Config` is among them.
    public static let choices: [TimeInterval] = [60, 5 * 60, 10 * 60, 30 * 60]

    /// The one in use. `stored`: what was saved, nil when nothing was. Anything that is not one of the choices is
    /// the one of `Config`: a value written by hand must not keep a secret for days.
    public static func lifetime(stored: TimeInterval?) -> TimeInterval {
        guard let stored, choices.contains(stored) else {
            return Config.concealedLifetime
        }
        return stored
    }

    /// How the settings name a lifetime: in whole minutes, which is what the choices are.
    public static func title(of lifetime: TimeInterval) -> String {
        let minutes = Int(lifetime / 60)
        return minutes == 1
            ? "1 minute"
            : "\(minutes) minutes"
    }
}
