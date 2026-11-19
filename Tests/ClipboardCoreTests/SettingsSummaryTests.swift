import Foundation
import Testing
@testable import ClipboardCore

/// The settings window is the only place that says whether the backup is safe and whether sync is running: a wrong
/// line there hides a backup waiting for the user's choice, or a sync that is not happening.
struct SettingsSummaryTests {
    private let lastBackup = Date(timeIntervalSince1970: 1_000)

    private func backup(
        isAvailable: Bool = true, hasBackup: Bool = true, isAwaitingUser: Bool = false,
        block: AutomaticBackupBlock? = nil, lastBackupDate: Date? = Date(timeIntervalSince1970: 1_000)
    ) -> BackupSummary {
        SettingsSummary.backup(
            isAvailable: isAvailable, hasBackup: hasBackup, isAwaitingUser: isAwaitingUser, block: block,
            lastBackupDate: lastBackupDate
        )
    }

    // MARK: backup

    @Test func withoutICloudDriveNothingElseIsSaid() {
        // Whether a backup exists cannot be known without iCloud Drive, whatever was recorded before.
        #expect(backup(isAvailable: false, isAwaitingUser: true, block: .localDataLost) == .iCloudUnavailable)
    }

    @Test func backupWaitingForTheFirstLaunchChoiceAsksForIt() {
        #expect(backup(isAwaitingUser: true) == .awaitingChoice)
    }

    @Test func backupOfAnotherMacAsksForTheChoiceToo() {
        #expect(backup(block: .notOwnBackup, lastBackupDate: nil) == .awaitingChoice)
    }

    @Test func damagedLocalDataIsSaidBeforeTheLastBackup() {
        // The date alone would read as "all is well" while the automatic backup is paused.
        #expect(backup(block: .localDataLost) == .localDataLost)
    }

    @Test func backupGoneFromICloudIsNotShownAsTheLastOne() {
        #expect(backup(hasBackup: false) == .noBackup)
    }

    @Test func ownBackupShowsWhenItWasMade() {
        #expect(backup() == .lastBackup(lastBackup))
    }

    @Test func backupSummariesReadAsInTheWindow() {
        let relative: (Date) -> String = { _ in "5 min ago" }
        #expect(BackupSummary.iCloudUnavailable.text(relative: relative) == "iCloud Drive not available")
        #expect(BackupSummary.awaitingChoice.text(relative: relative) == "iCloud backup not restored: restore it or make a new backup")
        #expect(BackupSummary.localDataLost.text(relative: relative) == "Local data was damaged: restore the backup or make a new one")
        #expect(BackupSummary.noBackup.text(relative: relative) == "No backup in iCloud")
        #expect(BackupSummary.lastBackup(lastBackup).text(relative: relative) == "Last backup: 5 min ago")
    }

    // MARK: sync

    @Test func syncOffSaysNothingWhileItCanBeTurnedOn() {
        #expect(SettingsSummary.syncText(.off, isAvailable: true) { _ in "" } == "")
    }

    @Test func syncOffWithoutICloudDriveSaysWhyItCannotBeTurnedOn() {
        #expect(SettingsSummary.syncText(.off, isAvailable: false) { _ in "" } == "Not syncing: iCloud Drive is turned off")
        #expect(SettingsSummary.syncText(.iCloudUnavailable, isAvailable: false) { _ in "" } == "Not syncing: iCloud Drive is turned off")
    }

    @Test func syncedShowsWhen() {
        let date = Date(timeIntervalSince1970: 2_000)
        let text = SettingsSummary.syncText(.synced(date), isAvailable: true) { $0 == date ? "1 min ago" : "wrong date" }
        #expect(text == "Synced 1 min ago")
    }

    @Test(arguments: [
        (SyncStatus.newerVersionElsewhere, "Another Mac uses a newer version: update SimpleClipboard"),
        (SyncStatus.writeFailed, "Not syncing: could not write to iCloud Drive"),
        (SyncStatus.waitingForOtherMacs, "Not syncing: waiting for another Mac's data"),
    ])
    func syncProblemsAreSaid(status: SyncStatus, expected: String) {
        #expect(SettingsSummary.syncText(status, isAvailable: true) { _ in "" } == expected)
    }

    @Test func syncSwitchIsLockedOnlyWhenOffAndICloudDriveIsMissing() {
        // Sync that is on must always be possible to turn off, even without iCloud Drive.
        #expect(SettingsSummary.canToggleSync(isEnabled: false, isAvailable: false) == false)
        #expect(SettingsSummary.canToggleSync(isEnabled: true, isAvailable: false) == true)
        #expect(SettingsSummary.canToggleSync(isEnabled: false, isAvailable: true) == true)
        #expect(SettingsSummary.canToggleSync(isEnabled: true, isAvailable: true) == true)
    }
}
