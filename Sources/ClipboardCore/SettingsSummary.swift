import Foundation

/// What the settings window says about the backup in iCloud Drive.
public enum BackupSummary: Equatable, Sendable {
    case iCloudUnavailable
    /// A backup exists that this Mac has neither made nor restored: the user has to choose.
    case awaitingChoice
    /// Local data was found damaged and not recovered: the automatic backup is paused.
    case localDataLost
    case noBackup
    case lastBackup(Date)

    /// `relative`: a date as "5 min ago", from the app's formatter.
    public func text(relative: (Date) -> String) -> String {
        switch self {
        case .iCloudUnavailable:
            return "iCloud Drive not available"
        case .awaitingChoice:
            return "iCloud backup not restored: restore it or make a new backup"
        case .localDataLost:
            return "Local data was damaged: restore the backup or make a new one"
        case .noBackup:
            return "No backup in iCloud"
        case .lastBackup(let date):
            return "Last backup: \(relative(date))"
        }
    }
}

/// The lines and switches of the settings window that depend on the state of the backup and of sync. Pure, so the
/// rules are tested without the window.
public enum SettingsSummary {
    /// `isAwaitingUser`: the first-launch decision is waiting for the user (`BackupBootstrapDecision.awaitUser`).
    /// `block`: why the automatic backup does not run (`BackupBootstrap.automaticBackupBlock`).
    /// What stops the automatic backup comes first: the date of the last backup alone would read as "all is well".
    public static func backup(
        isAvailable: Bool, hasBackup: Bool, isAwaitingUser: Bool, block: AutomaticBackupBlock?, lastBackupDate: Date?
    ) -> BackupSummary {
        guard isAvailable else {
            return .iCloudUnavailable
        }
        if isAwaitingUser || block == .notOwnBackup {
            return .awaitingChoice
        }
        if block == .localDataLost {
            return .localDataLost
        }
        guard hasBackup else {
            return .noBackup
        }
        // A backup with no date of this Mac's is not this Mac's, whatever `block` says.
        return lastBackupDate.map(BackupSummary.lastBackup) ?? .awaitingChoice
    }

    /// Empty when there is nothing to say (sync off and possible). `isAvailable`: iCloud Drive is there.
    public static func syncText(_ status: SyncStatus, isAvailable: Bool, relative: (Date) -> String) -> String {
        let unavailable = "Not syncing: iCloud Drive is turned off"
        switch status {
        case .off:
            return isAvailable
                ? ""
                : unavailable
        case .iCloudUnavailable:
            return unavailable
        case .synced(let date):
            return "Synced \(relative(date))"
        case .newerVersionElsewhere:
            return "Another Mac uses a newer version: update \(Config.appName)"
        case .writeFailed:
            return "Not syncing: could not write to iCloud Drive"
        case .waitingForOtherMacs:
            return "Not syncing: waiting for another Mac's data"
        }
    }

    /// Sync that is on can always be turned off; turning it on needs iCloud Drive.
    public static func canToggleSync(isEnabled: Bool, isAvailable: Bool) -> Bool {
        isEnabled || isAvailable
    }
}
