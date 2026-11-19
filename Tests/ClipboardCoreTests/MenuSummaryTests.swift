import Foundation
import Testing
@testable import ClipboardCore

/// The menu-bar menu is the only place that says whether the backup is safe and whether sync is running: a wrong
/// line there hides a backup waiting for the user's choice, or a sync that is not happening.
struct MenuSummaryTests {
    private static let lastBackup = Date(timeIntervalSince1970: 1_000)

    private func backup(
        isAvailable: Bool = true, isAwaitingUser: Bool = false, block: AutomaticBackupBlock? = nil,
        lastBackupDate: Date? = MenuSummaryTests.lastBackup
    ) -> BackupSummary {
        MenuSummary.backup(
            isAvailable: isAvailable, isAwaitingUser: isAwaitingUser, block: block, lastBackupDate: lastBackupDate
        )
    }

    // MARK: backup

    @Test func withoutICloudDriveNothingElseIsSaid() {
        // Whether a backup exists cannot be known without iCloud Drive, whatever was recorded before.
        #expect(backup(isAvailable: false, isAwaitingUser: true, block: .localDataLost) == .iCloudUnavailable)
    }

    @Test func withoutICloudDriveAMacThatNeverBackedUpDoesNotSayNoBackups() {
        #expect(backup(isAvailable: false, lastBackupDate: nil) == .iCloudUnavailable)
    }

    @Test func backupWaitingForTheFirstLaunchChoiceAsksForIt() {
        #expect(backup(isAwaitingUser: true) == .awaitingChoice)
    }

    @Test func backupOfAnotherMacAsksForTheChoiceInsteadOfSayingNoBackups() {
        // A backup that is not this Mac's comes with no date of this Mac's.
        #expect(backup(block: .notOwnBackup, lastBackupDate: nil) == .awaitingChoice)
        #expect(backup(isAwaitingUser: true, block: .notOwnBackup, lastBackupDate: nil) == .awaitingChoice)
    }

    @Test func theChoiceIsAskedBeforeSayingTheDataWasDamaged() {
        #expect(backup(isAwaitingUser: true, block: .localDataLost) == .awaitingChoice)
    }

    @Test func damagedLocalDataIsSaidBeforeTheLastBackup() {
        // The date alone would read as "all is well" while the automatic backup is paused.
        #expect(backup(block: .localDataLost) == .localDataLost)
    }

    @Test func macThatNeverBackedUpSaysSo() {
        #expect(backup(lastBackupDate: nil) == .noBackup)
    }

    @Test func ownBackupShowsWhenItWasMade() {
        #expect(backup() == .lastBackup(Self.lastBackup))
    }

    @Test func backupSummariesReadAsInTheMenu() {
        let relative: (Date) -> String = { _ in "5 minutes ago" }
        #expect(BackupSummary.iCloudUnavailable.text(relative: relative) == "iCloud Drive not available")
        #expect(BackupSummary.awaitingChoice.text(relative: relative) == "Backup not restored")
        #expect(BackupSummary.localDataLost.text(relative: relative) == "Local data was damaged")
        #expect(BackupSummary.noBackup.text(relative: relative) == "No backups yet")
    }

    @Test func lastBackupShowsItsOwnDate() {
        let text = BackupSummary.lastBackup(Self.lastBackup).text {
            $0 == Self.lastBackup
                ? "5 minutes ago"
                : "wrong date"
        }
        #expect(text == "Last backup 5 minutes ago")
    }

    @Test func restoreNeedsICloudDriveAndABackupInIt() {
        #expect(MenuSummary.canRestore(isAvailable: true, hasBackup: true))
        #expect(!MenuSummary.canRestore(isAvailable: true, hasBackup: false))
        #expect(!MenuSummary.canRestore(isAvailable: false, hasBackup: true))
        #expect(!MenuSummary.canRestore(isAvailable: false, hasBackup: false))
    }

    // MARK: sync

    @Test func syncOffSaysNothingWhileItCanBeTurnedOn() {
        #expect(MenuSummary.syncText(.off, isAvailable: true) { _ in "" } == "")
    }

    @Test func syncOffWithoutICloudDriveSaysWhyItCannotBeTurnedOn() {
        #expect(MenuSummary.syncText(.off, isAvailable: false) { _ in "" } == "Not syncing: iCloud Drive is turned off")
        #expect(MenuSummary.syncText(.iCloudUnavailable, isAvailable: false) { _ in "" } == "Not syncing: iCloud Drive is turned off")
    }

    @Test func roundWithoutICloudDriveIsStillSaidOnceItIsBack() {
        // The status is from the last round and iCloud Drive is read live: it can be back before the next round.
        #expect(MenuSummary.syncText(.iCloudUnavailable, isAvailable: true) { _ in "" } == "Not syncing: iCloud Drive is turned off")
    }

    @Test func syncedShowsWhen() {
        let date = Date(timeIntervalSince1970: 2_000)
        let text = MenuSummary.syncText(.synced(date), isAvailable: true) {
            $0 == date
                ? "1 minute ago"
                : "wrong date"
        }
        #expect(text == "Synced 1 minute ago")
    }

    @Test func lastRoundIsStillSaidWhenICloudDriveHasGoneSince() {
        // The status is from the last round: what it found stays on the line until the next one.
        #expect(MenuSummary.syncText(.synced(Date()), isAvailable: false) { _ in "1 minute ago" } == "Synced 1 minute ago")
        #expect(MenuSummary.syncText(.writeFailed, isAvailable: false) { _ in "" } == "Not syncing: could not write to iCloud Drive")
        #expect(
            MenuSummary.syncText(.newerVersionElsewhere, isAvailable: false) { _ in "" }
                == "Another Mac uses a newer version: update SimpleClipboard"
        )
    }

    @Test(arguments: [
        (SyncStatus.newerVersionElsewhere, "Another Mac uses a newer version: update SimpleClipboard"),
        (SyncStatus.writeFailed, "Not syncing: could not write to iCloud Drive"),
        (SyncStatus.waitingForOtherMacs, "Not syncing: waiting for another Mac's data"),
    ])
    func syncProblemsAreSaid(status: SyncStatus, expected: String) {
        #expect(MenuSummary.syncText(status, isAvailable: true) { _ in "" } == expected)
    }

    @Test func syncItemIsLockedOnlyWhenOffAndICloudDriveIsMissing() {
        // Sync that is on must always be possible to turn off, even without iCloud Drive.
        #expect(!MenuSummary.canToggleSync(isEnabled: false, isAvailable: false))
        #expect(MenuSummary.canToggleSync(isEnabled: true, isAvailable: false))
        #expect(MenuSummary.canToggleSync(isEnabled: false, isAvailable: true))
        #expect(MenuSummary.canToggleSync(isEnabled: true, isAvailable: true))
    }
}
