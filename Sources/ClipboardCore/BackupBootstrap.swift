public enum BackupBootstrapDecision: Equatable, Sendable {
    /// iCloud Drive not available yet: decide later, no automatic backup.
    case wait
    /// Empty Mac and a backup exists: restore it automatically.
    case restore
    /// A backup exists but this Mac already has data it did not have at the first check:
    /// no automatic restore or backup until the user chooses.
    case awaitUser
    /// Nothing to restore or this Mac's data wins: normal operation.
    case done
}

/// The first-launch decision: a new Mac picks up the existing iCloud backup instead of
/// overwriting it, but data this Mac already has is never replaced automatically.
public enum BackupBootstrap {
    /// `localWasEmptyAtFirstCheck`: recorded at the first check where iCloud Drive was available
    /// (nil = not recorded yet; the caller records `localIsEmpty` at that check).
    public static func decide(
        isAvailable: Bool, hasBackup: Bool, localIsEmpty: Bool, localWasEmptyAtFirstCheck: Bool?
    ) -> BackupBootstrapDecision {
        guard isAvailable else {
            return .wait
        }
        guard hasBackup else {
            return .done
        }
        if localWasEmptyAtFirstCheck == false {
            return .done
        }
        return localIsEmpty
            ? .restore
            : .awaitUser
    }
}
