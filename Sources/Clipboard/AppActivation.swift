import AppKit

@MainActor
enum AppActivation {
    /// Brings the app to the front for a window or an alert of its own.
    /// Not `NSApp.activate()`: that one only asks, and the system does not always grant it to an app with no Dock
    /// icon whose menu-bar menu was just used. The window or the alert then shows without keyboard focus, behind
    /// the app in front. This call is marked to be deprecated in a future release; there is no other that insists.
    static func activate() {
        NSApp.activate(ignoringOtherApps: true)
    }
}
