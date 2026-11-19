import Foundation

/// What the menu-bar menu says about the backup.
public enum BackupSummary: Equatable, Sendable {
    case iCloudUnavailable
    /// A backup exists that this Mac has neither made nor restored: the user has to choose.
    case awaitingChoice
    /// Local data was found damaged and not recovered: the automatic backup is paused.
    case localDataLost
    /// This Mac has never made or restored a backup.
    case noBackup
    case lastBackup(Date)

    /// `relative`: a date as "5 minutes ago", from the app's formatter.
    public func text(relative: (Date) -> String) -> String {
        switch self {
        case .iCloudUnavailable:
            return "iCloud Drive not available"
        case .awaitingChoice:
            return "Backup not restored"
        case .localDataLost:
            return "Local data was damaged"
        case .noBackup:
            return "No backups yet"
        case .lastBackup(let date):
            return "Last backup \(relative(date))"
        }
    }
}

/// The lines and items of the menu-bar menu that depend on the state of the backup and of sync. Pure, so the rules
/// are tested without the menu.
public enum MenuSummary {
    /// `isAwaitingUser`: the first-launch decision is waiting for the user (`BackupBootstrapDecision.awaitUser`).
    /// `block`: why the automatic backup does not run (`BackupBootstrap.automaticBackupBlock`).
    /// What stops the automatic backup comes first: the date of the last backup alone would read as "all is well".
    public static func backup(
        isAvailable: Bool, isAwaitingUser: Bool, block: AutomaticBackupBlock?, lastBackupDate: Date?
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
        return lastBackupDate.map(BackupSummary.lastBackup) ?? .noBackup
    }

    /// `isAvailable`: iCloud Drive is there.
    public static func canRestore(isAvailable: Bool, hasBackup: Bool) -> Bool {
        isAvailable && hasBackup
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
