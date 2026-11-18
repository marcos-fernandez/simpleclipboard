public enum BackupBootstrapDecision: Equatable, Sendable {
    /// iCloud Drive not available yet: decide later, no automatic backup.
    case wait
    /// Empty Mac and a backup exists: restore it automatically.
    case restore
    /// A backup exists, this Mac has data and has never made or restored a backup itself:
    /// no automatic restore or backup until the user chooses.
    case awaitUser
    /// Nothing to restore, or this Mac had data at the first check and has made or restored
    /// a backup itself: normal operation, this Mac's data wins.
    case done
}

/// The first-launch decision: a new Mac picks up the existing iCloud backup instead of
/// overwriting it, but data this Mac already has is never replaced automatically.
public enum BackupBootstrap {
    /// `localWasEmptyAtFirstCheck`: recorded at the first check where iCloud Drive was available
    /// (nil = not recorded yet; the caller records `localIsEmpty` at that check).
    /// `hasOwnBackup`: this Mac has made or restored a backup itself, so the backup is not
    /// another Mac's that would be overwritten without the user choosing.
    public static func decide(
        isAvailable: Bool, hasBackup: Bool, localIsEmpty: Bool, localWasEmptyAtFirstCheck: Bool?, hasOwnBackup: Bool
    ) -> BackupBootstrapDecision {
        guard isAvailable else {
            return .wait
        }
        guard hasBackup else {
            return .done
        }
        if localWasEmptyAtFirstCheck == false {
            return hasOwnBackup
                ? .done
                : .awaitUser
        }
        return localIsEmpty
            ? .restore
            : .awaitUser
    }
}
