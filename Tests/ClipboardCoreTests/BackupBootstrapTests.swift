import Testing
@testable import ClipboardCore

/// The first-launch decision is the only code that can replace this Mac's history and tags
/// without the user asking: it must restore only onto an empty Mac.
struct BackupBootstrapTests {
    @Test(arguments: [nil, true, false] as [Bool?])
    func waitsWhileICloudDriveIsUnavailable(localWasEmpty: Bool?) {
        // Without iCloud Drive we cannot know whether a backup exists, so nothing is decided yet.
        #expect(BackupBootstrap.decide(
            isAvailable: false, hasBackup: true, localIsEmpty: true, localWasEmptyAtFirstCheck: localWasEmpty,
            hasOwnBackup: false
        ) == .wait)
    }

    @Test(arguments: [nil, true, false] as [Bool?])
    func withoutABackupThereIsNothingToRestore(localWasEmpty: Bool?) {
        // No backup to lose or to restore: start backing up this Mac right away.
        #expect(BackupBootstrap.decide(
            isAvailable: true, hasBackup: false, localIsEmpty: true, localWasEmptyAtFirstCheck: localWasEmpty,
            hasOwnBackup: false
        ) == .done)
    }

    @Test(arguments: [true, false])
    func aMacThatHadDataAtTheFirstCheckAndBacksItselfUpKeepsIt(localIsEmpty: Bool) {
        // An existing Mac's data wins; it is never replaced automatically. The backup is its own,
        // so the automatic backup only updates it.
        #expect(BackupBootstrap.decide(
            isAvailable: true, hasBackup: true, localIsEmpty: localIsEmpty, localWasEmptyAtFirstCheck: false,
            hasOwnBackup: true
        ) == .done)
    }

    @Test(arguments: [true, false])
    func anotherMacsBackupIsNotOverwrittenWithoutTheUserChoosing(localIsEmpty: Bool) {
        // A new Mac that copied things before iCloud Drive was available holds a few items, while the
        // backup it finds is another Mac's full history: the automatic backup must not replace it, and
        // this Mac's data must not be replaced either. Only the user can choose which one wins.
        #expect(BackupBootstrap.decide(
            isAvailable: true, hasBackup: true, localIsEmpty: localIsEmpty, localWasEmptyAtFirstCheck: false,
            hasOwnBackup: false
        ) == .awaitUser)
    }

    @Test(arguments: [nil, true] as [Bool?])
    func anEmptyMacRestoresTheBackup(localWasEmpty: Bool?) {
        // A new Mac picks up the existing backup instead of overwriting it with nothing.
        #expect(BackupBootstrap.decide(
            isAvailable: true, hasBackup: true, localIsEmpty: true, localWasEmptyAtFirstCheck: localWasEmpty,
            hasOwnBackup: false
        ) == .restore)
    }

    @Test func aMacThatCopiedThingsSinceTheFirstCheckWaitsForTheUser() {
        // A Mac that copied things while iCloud was downloading must never lose them automatically.
        #expect(BackupBootstrap.decide(
            isAvailable: true, hasBackup: true, localIsEmpty: false, localWasEmptyAtFirstCheck: true,
            hasOwnBackup: false
        ) == .awaitUser)
    }

    @Test func aMacWithDataAtTheFirstAvailableCheckIsNotRestoredOver() {
        // Nothing recorded yet and local data present: never restore over it.
        #expect(BackupBootstrap.decide(
            isAvailable: true, hasBackup: true, localIsEmpty: false, localWasEmptyAtFirstCheck: nil,
            hasOwnBackup: false
        ) == .awaitUser)
    }

    // MARK: automatic backup

    @Test(arguments: [true, false])
    func theFirstBackupIsMadeAutomatically(localDataWasLost: Bool) {
        // With no backup in iCloud there is nothing to lose, and the user expects one to appear.
        #expect(BackupBootstrap.automaticBackupBlock(
            hasBackup: false, hasOwnBackup: false, localDataWasLost: localDataWasLost
        ) == nil)
    }

    @Test func aBackupThisMacMadeOrRestoredIsUpdatedAutomatically() {
        #expect(BackupBootstrap.automaticBackupBlock(
            hasBackup: true, hasOwnBackup: true, localDataWasLost: false
        ) == nil)
    }

    @Test func aBackupThisMacNeverMadeNorRestoredIsNotReplacedAutomatically() {
        // A new Mac where iCloud Drive listed the backup folder only after the first-launch decision: an hour
        // later its few items would replace the other Mac's whole history.
        #expect(BackupBootstrap.automaticBackupBlock(
            hasBackup: true, hasOwnBackup: false, localDataWasLost: false
        ) == .notOwnBackup)
    }

    @Test func afterLocalDataWasLostTheBackupIsNotReplacedAutomatically() {
        // The backup may be the only good copy of what a damaged file held: the hourly backup would replace it
        // with the near-empty history this Mac started again with.
        #expect(BackupBootstrap.automaticBackupBlock(
            hasBackup: true, hasOwnBackup: true, localDataWasLost: true
        ) == .localDataLost)
    }
}
