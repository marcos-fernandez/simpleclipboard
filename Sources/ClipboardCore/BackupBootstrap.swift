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

/// Why the automatic backup does not run (see `BackupBootstrap.automaticBackupBlock`).
public enum AutomaticBackupBlock: Equatable, Sendable {
    /// The backup in iCloud was neither made nor restored by this Mac: it may be another Mac's.
    case notOwnBackup
    /// Local data was found damaged and could not be recovered: the backup may be its only good copy.
    case localDataLost
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

    /// Checked before every automatic backup, also after the first-launch decision is done: the backup folder can
    /// show up in iCloud Drive later. nil when it may run. Only the user lifts a block, with "Back Up Now" or
    /// "Restore from iCloud…" (`hasOwnBackup` becomes true and the loss is cleared). With no backup there is
    /// nothing to replace.
    public static func automaticBackupBlock(
        hasBackup: Bool, hasOwnBackup: Bool, localDataWasLost: Bool
    ) -> AutomaticBackupBlock? {
        guard hasBackup else {
            return nil
        }
        guard hasOwnBackup else {
            return .notOwnBackup
        }
        return localDataWasLost
            ? .localDataLost
            : nil
    }
}
