import Testing
@testable import ClipboardCore

/// The first-launch decision is the only code that can replace this Mac's history and tags
/// without the user asking: it must restore only onto an empty Mac.
struct BackupBootstrapTests {
    @Test(arguments: [nil, true, false] as [Bool?])
    func waitsWhileICloudDriveIsUnavailable(localWasEmpty: Bool?) {
        // Without iCloud Drive we cannot know whether a backup exists, so nothing is decided yet.
        #expect(BackupBootstrap.decide(
            isAvailable: false, hasBackup: true, localIsEmpty: true, localWasEmptyAtFirstCheck: localWasEmpty
        ) == .wait)
    }

    @Test(arguments: [nil, true, false] as [Bool?])
    func withoutABackupThereIsNothingToRestore(localWasEmpty: Bool?) {
        // No backup to lose or to restore: start backing up this Mac right away.
        #expect(BackupBootstrap.decide(
            isAvailable: true, hasBackup: false, localIsEmpty: true, localWasEmptyAtFirstCheck: localWasEmpty
        ) == .done)
    }

    @Test(arguments: [true, false])
    func aMacThatHadDataAtTheFirstCheckKeepsIt(localIsEmpty: Bool) {
        // An existing Mac's data wins; it is never replaced automatically.
        #expect(BackupBootstrap.decide(
            isAvailable: true, hasBackup: true, localIsEmpty: localIsEmpty, localWasEmptyAtFirstCheck: false
        ) == .done)
    }

    @Test(arguments: [nil, true] as [Bool?])
    func anEmptyMacRestoresTheBackup(localWasEmpty: Bool?) {
        // A new Mac picks up the existing backup instead of overwriting it with nothing.
        #expect(BackupBootstrap.decide(
            isAvailable: true, hasBackup: true, localIsEmpty: true, localWasEmptyAtFirstCheck: localWasEmpty
        ) == .restore)
    }

    @Test func aMacThatCopiedThingsSinceTheFirstCheckWaitsForTheUser() {
        // A Mac that copied things while iCloud was downloading must never lose them automatically.
        #expect(BackupBootstrap.decide(
            isAvailable: true, hasBackup: true, localIsEmpty: false, localWasEmptyAtFirstCheck: true
        ) == .awaitUser)
    }

    @Test func aMacWithDataAtTheFirstAvailableCheckIsNotRestoredOver() {
        // Nothing recorded yet and local data present: never restore over it.
        #expect(BackupBootstrap.decide(
            isAvailable: true, hasBackup: true, localIsEmpty: false, localWasEmptyAtFirstCheck: nil
        ) == .awaitUser)
    }
}
