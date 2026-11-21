import Foundation

public enum Config {
    public static let appName = "SimpleClipboard"
    public static let bundleID = "io.github.marcos-fernandez.SimpleClipboard"
    /// Former name; only used to migrate data on first launch after the rename.
    public static let legacyAppName = "Clipboard"
    public static let legacyBundleID = "com.marcosfernandez.Clipboard"
    /// Untagged items kept. A typical month of copying fits.
    public static let maxItems = 1000
    public static let maxAge: TimeInterval = 30 * 24 * 60 * 60
    public static let concealedLifetime: TimeInterval = 10 * 60
    public static let pollInterval: TimeInterval = 0.5
    public static let purgeInterval: TimeInterval = 30
    /// Same as 1Password's own clipboard clearing.
    public static let concealedPasteboardLifetime: TimeInterval = 90
    /// Size of the fixed tag palette (TagPalette in the app).
    public static let tagColorCount = TagColors.order.count
    /// Automatic iCloud Drive backup, only when something changed.
    public static let backupInterval: TimeInterval = 60 * 60
    /// Also once this long after launch, so a Mac that never runs the app for a whole `backupInterval` backs up too.
    public static let backupLaunchDelay: TimeInterval = 60
    /// Sync: deletions, and Macs that stopped publishing, are forgotten after this.
    public static let syncRetention: TimeInterval = 90 * 24 * 60 * 60
    /// An image no Mac uses is only deleted from iCloud after this: it can arrive before the file of the Mac using it.
    public static let syncImageGrace: TimeInterval = 7 * 24 * 60 * 60
    /// A Mac publishes at least this often, so a quiet one is not taken for gone after `syncRetention`.
    public static let syncRefreshInterval: TimeInterval = 24 * 60 * 60
    /// A stamp further ahead of this Mac's clock is taken for a broken clock and not followed (`HistoryStore`'s
    /// `stamp(after:)`): following it would date this Mac's changes, and through them every Mac's, that far ahead.
    public static let maxClockSkew: TimeInterval = 24 * 60 * 60
    /// How often other Macs' files are checked (also at launch and on wake).
    public static let syncPollInterval: TimeInterval = 30
    /// Publish this long after the last local change, not on every keystroke-like burst of saves.
    public static let syncPublishDelay: TimeInterval = 2
    /// Larger copies are not recorded: every change rewrites the whole history and republishes it to iCloud, so one
    /// huge item would make every later copy slow.
    public static let maxTextBytes = 2 * 1024 * 1024
    public static let maxImageBytes = 20 * 1024 * 1024
    /// A TIFF is refused unconverted beyond this. It is uncompressed, so its size is not the PNG's: the limit above
    /// applies after the conversion. Beyond 16 times that limit the PNG would need over 16:1 compression to fit,
    /// which only near-flat images reach, and those are never this large (a 6K screen capture is about 80 MB).
    public static let maxTIFFBytes = 16 * maxImageBytes

    /// System Settings > Privacy & Security > Accessibility.
    public static let accessibilitySettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )!

    /// Built here, never taken from the response: the menu item only ever opens this page.
    public static let releasesPageURL = URL(string: "https://github.com/marcos-fernandez/simpleclipboard/releases/latest")!
    public static let latestReleaseAPIURL = URL(
        string: "https://api.github.com/repos/marcos-fernandez/simpleclipboard/releases/latest"
    )!
    /// Unauthenticated GitHub API calls are limited per IP address: once a day is plenty to hear of a release.
    public static let updateCheckInterval: TimeInterval = 24 * 60 * 60
    /// How often the app looks whether a check is due. Much shorter than the interval: timers stand still while the
    /// Mac sleeps, so a single daily one would fire every few days on a laptop, and a failed check is tried again
    /// after this long instead of a day later.
    public static let updateCheckPollInterval: TimeInterval = 60 * 60
    /// Also once this long after launch, as the app mostly starts at login, before the network may be up.
    public static let updateCheckLaunchDelay: TimeInterval = 60
    public static let updateCheckTimeout: TimeInterval = 30

    public static let concealedSourceBundleIDs: Set<String> = [
        "com.1password.1password",
        "com.agilebits.onepassword7",
        // Apple's Passwords app (macOS 15+): not relied on to mark its copies as concealed.
        "com.apple.Passwords",
    ]
    public static let ignoredSourceBundleIDs: Set<String> = [
        "com.apple.keychainaccess",
    ]

    /// Written by Paster so the monitor does not re-record our own pastes.
    public static let ownMarkerType = "io.github.marcos-fernandez.SimpleClipboard.self"
    /// nspasteboard.org conventions.
    public static let concealedType = "org.nspasteboard.ConcealedType"
    public static let transientType = "org.nspasteboard.TransientType"
    public static let autoGeneratedType = "org.nspasteboard.AutoGeneratedType"
    /// Finder file copies are out of scope.
    public static let fileURLType = "public.file-url"
}
