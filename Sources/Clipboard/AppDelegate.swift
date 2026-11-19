import AppKit
import ApplicationServices
import ClipboardCore
import os
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static let logger = Logger(subsystem: Config.bundleID, category: "AppDelegate")

    private var store: HistoryStore!
    private var monitor: ClipboardMonitor!
    private var panel: PanelController!
    private var hotkey: HotkeyManager!
    private var statusItem: NSStatusItem!
    private var purgeTimer: Timer?

    private static let lastBackupKey = "lastBackupDate"
    /// Set once the first-launch decision is done (see `BackupBootstrap`).
    private static let backupBootstrapKey = "backupBootstrapDone"
    private static let backupBootstrapLocalWasEmptyKey = "backupBootstrapLocalWasEmpty"
    /// Set at launch when local data was found damaged and not recovered (`FilePersistence.dataWasLost`); kept across
    /// relaunches, where the data looks fine again, until a manual backup or a restore succeeds.
    private static let localDataLostKey = "localDataLost"

    private var backup: BackupService!
    private var backupTimer: Timer?
    private var backupInfoItem: NSMenuItem!
    private var backupNowItem: NSMenuItem!
    private var restoreItem: NSMenuItem!

    private var sync: SyncService!
    private var syncStatus: SyncStatus = .off
    private var syncTimer: Timer?
    /// One-shot, restarted on every save: publishes `Config.syncPublishDelay` after the last local change.
    private var syncSoonTimer: Timer?
    private var syncItem: NSMenuItem!
    private var syncInfoItem: NSMenuItem!

    private static let relativeFormatter = RelativeDateTimeFormatter()

    private var lastBackupDate: Date? {
        UserDefaults.standard.object(forKey: Self.lastBackupKey) as? Date
    }

    /// The app used to be called Clipboard: carry over its data folder, iCloud backup folder and
    /// backup state. The login-item flag is not copied, so the renamed app registers itself again.
    private func migrateFromLegacyName(legacyDirectory: URL, directory: URL, iCloudDriveRoot: URL) {
        do {
            try LegacyMigration.moveDirectory(from: legacyDirectory, to: directory, recognisedBy: ["history.json"])
            if FileManager.default.fileExists(atPath: iCloudDriveRoot.path) {
                try LegacyMigration.moveDirectory(
                    from: iCloudDriveRoot.appendingPathComponent(Config.legacyAppName, isDirectory: true),
                    to: iCloudDriveRoot.appendingPathComponent(Config.appName, isDirectory: true),
                    recognisedBy: ["Backup", "Sync"]
                )
            }
        } catch {
            Self.logger.error("Cannot migrate data from the old app name: \(error.localizedDescription, privacy: .public)")
        }
        if let legacyDefaults = UserDefaults(suiteName: Config.legacyBundleID) {
            LegacyMigration.copyDefaults(
                keys: [Self.lastBackupKey, Self.backupBootstrapKey, Self.backupBootstrapLocalWasEmptyKey],
                from: legacyDefaults,
                to: .standard
            )
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let applicationSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = applicationSupport.appendingPathComponent(Config.appName, isDirectory: true)
        let iCloudDriveRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        migrateFromLegacyName(
            legacyDirectory: applicationSupport.appendingPathComponent(Config.legacyAppName, isDirectory: true),
            directory: directory,
            iCloudDriveRoot: iCloudDriveRoot
        )

        backup = BackupService(localDirectory: directory, iCloudDriveRoot: iCloudDriveRoot)
        // Before FilePersistence, which creates an empty images/ that would keep the leftover images out.
        do {
            try backup.recoverInterruptedRestore()
        } catch {
            Self.logger.error("Cannot recover an interrupted restore: \(error.localizedDescription, privacy: .public)")
        }
        let persistence = FilePersistence(directory: directory)
        store = HistoryStore(persistence: persistence)
        if persistence.dataWasLost {
            UserDefaults.standard.set(true, forKey: Self.localDataLostKey)
        }
        restoreOnFirstLaunchIfNeeded()
        // After the first-launch restore: a new Mac must not publish what that restore replaced as deletions.
        sync = SyncService(localDirectory: directory, iCloudDriveRoot: iCloudDriveRoot)
        startSync()

        let backupTimer = Timer(timeInterval: Config.backupInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.backUpIfChanged()
            }
        }
        RunLoop.main.add(backupTimer, forMode: .common)
        self.backupTimer = backupTimer
        let launchBackupTimer = Timer(timeInterval: Config.backupLaunchDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.backUpIfChanged()
            }
        }
        RunLoop.main.add(launchBackupTimer, forMode: .common)

        monitor = ClipboardMonitor(store: store)
        monitor.start()

        let purgeTimer = Timer(timeInterval: Config.purgeInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.store.purgeExpired()
            }
        }
        // .common keeps concealed items expiring while a menu or modal alert is open.
        RunLoop.main.add(purgeTimer, forMode: .common)
        self.purgeTimer = purgeTimer

        panel = PanelController(store: store) { [weak self] item, target in
            guard let self else {
                return
            }
            // Nothing pasted (its image file is missing) is not a use: the item keeps its place and nothing is saved.
            if Paster.paste(item, imageData: store.imageData(for: item), into: target) {
                store.promote(id: item.id)
            }
        }

        hotkey = HotkeyManager { [weak self] in
            self?.panel.toggle()
        }
        let hotkeyRegistered = hotkey.register()
        if !hotkeyRegistered {
            Self.logger.error("Cannot register ⇧⌘V")
        }

        setUpStatusItem(hotkeyRegistered: hotkeyRegistered)
        registerLoginItem()
        requestAccessibilityIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        Paster.clearConcealedValue()
    }

    private func setUpStatusItem(hotkeyRegistered: Bool) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: Config.appName)

        let menu = NSMenu()
        if !hotkeyRegistered {
            let warning = NSMenuItem(title: "⚠︎ Could not register ⇧⌘V", action: nil, keyEquivalent: "")
            warning.isEnabled = false
            menu.addItem(warning)
        }
        let openItem = NSMenuItem(title: "Open History (⇧⌘V)", action: #selector(openHistory), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
        let clearItem = NSMenuItem(title: "Clear History…", action: #selector(clearHistory), keyEquivalent: "")
        clearItem.target = self
        menu.addItem(clearItem)
        menu.addItem(.separator())
        backupNowItem = NSMenuItem(title: "Back Up Now", action: #selector(backUpNow), keyEquivalent: "")
        backupNowItem.target = self
        menu.addItem(backupNowItem)
        restoreItem = NSMenuItem(title: "Restore from iCloud…", action: #selector(restoreBackup), keyEquivalent: "")
        restoreItem.target = self
        menu.addItem(restoreItem)
        backupInfoItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        backupInfoItem.isEnabled = false
        menu.addItem(backupInfoItem)
        menu.addItem(.separator())
        syncItem = NSMenuItem(title: "Sync Between Macs", action: #selector(toggleSync), keyEquivalent: "")
        syncItem.target = self
        menu.addItem(syncItem)
        syncInfoItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        syncInfoItem.isEnabled = false
        menu.addItem(syncInfoItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        // Manual enabling: with auto-enabling, AppKit would re-enable items that have a target.
        menu.autoenablesItems = false
        menu.delegate = self
        refreshBackupItems()
        refreshSyncItems()
        statusItem.menu = menu
    }

    @objc private func openHistory() {
        panel.show()
    }

    @objc private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear the history?"
        alert.informativeText = "Untagged items will be deleted. Tagged items are kept. This cannot be undone."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            store.removeUntagged()
        }
        // Hand focus back so the next ⇧⌘V targets the app the user was in, not us.
        NSApp.hide(nil)
    }

    // MARK: sync

    /// Runs a round at launch, every `Config.syncPollInterval`, on wake and `Config.syncPublishDelay` after each local
    /// save. Each round is short and synchronous, like the backup.
    private func startSync() {
        store.onPersist = { [weak self] in
            self?.syncSoon()
        }
        let timer = Timer(timeInterval: Config.syncPollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.runSync()
            }
        }
        // .common keeps syncing while a menu or modal alert is open.
        RunLoop.main.add(timer, forMode: .common)
        syncTimer = timer
        _ = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.runSync()
            }
        }
        connectDeletionRecorder()
        runSync()
    }

    /// Deletions are recorded for other Macs only while sync is on.
    private func connectDeletionRecorder() {
        guard sync.isEnabled else {
            store.deletionRecorder = nil
            return
        }
        store.deletionRecorder = { [weak self] deletions in
            self?.sync.record(deletions)
        }
    }

    private func syncSoon() {
        guard sync.isEnabled else {
            return
        }
        syncSoonTimer?.invalidate()
        let timer = Timer(timeInterval: Config.syncPublishDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.runSync()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        syncSoonTimer = timer
    }

    private func runSync() {
        syncStatus = sync.sync(store)
    }

    @objc private func toggleSync() {
        if sync.isEnabled {
            sync.disable()
        } else {
            do {
                try sync.enable()
            } catch {
                Self.logger.error("Cannot enable sync: \(error.localizedDescription, privacy: .public)")
            }
        }
        connectDeletionRecorder()
        runSync()
    }

    private func refreshSyncItems() {
        syncItem.state = sync.isEnabled
            ? .on
            : .off
        syncItem.isEnabled = sync.isEnabled || sync.isAvailable
        let text = syncStatusText()
        syncInfoItem.title = text
        syncInfoItem.isHidden = text.isEmpty
    }

    /// Empty when there is nothing to say (sync off and possible).
    private func syncStatusText() -> String {
        let unavailable = "Not syncing: iCloud Drive is turned off"
        switch syncStatus {
        case .off:
            guard sync.isAvailable else {
                return unavailable
            }
            return ""
        case .iCloudUnavailable:
            return unavailable
        case .synced(let date):
            return "Synced \(Self.relativeFormatter.localizedString(for: date, relativeTo: Date()))"
        case .newerVersionElsewhere:
            return "Another Mac uses a newer version: update SimpleClipboard"
        case .writeFailed:
            return "Not syncing: could not write to iCloud Drive"
        case .waitingForOtherMacs:
            return "Not syncing: waiting for another Mac's data"
        }
    }

    // MARK: backup

    /// Runs the first-launch decision (`BackupBootstrap`) at launch and on every hourly tick until it is done.
    /// Whether this Mac was empty is recorded at the first check where iCloud Drive is available and kept
    /// across retries and relaunches. An empty Mac restores the backup (retried until it succeeds, e.g. once
    /// iCloud finishes downloading); a Mac with data that has never made or restored a backup itself waits
    /// for the user to choose "Restore" or "Back Up Now". While it is not done no automatic backup runs.
    private func restoreOnFirstLaunchIfNeeded() {
        guard !isBackupBootstrapDone else {
            return
        }
        let localWasEmpty = UserDefaults.standard.object(forKey: Self.backupBootstrapLocalWasEmptyKey) as? Bool
        let decision = backupBootstrapDecision(localWasEmptyAtFirstCheck: localWasEmpty)
        if localWasEmpty == nil, backup.isAvailable {
            UserDefaults.standard.set(isLocalEmpty, forKey: Self.backupBootstrapLocalWasEmptyKey)
        }
        switch decision {
        case .restore:
            do {
                try backup.restore()
                // Only fills an empty new Mac: the merge rules decide against the other Macs once sync is on.
                store.reloadFromDisk(markingChanges: false)
                UserDefaults.standard.set(Date(), forKey: Self.lastBackupKey)
                UserDefaults.standard.set(true, forKey: Self.backupBootstrapKey)
                UserDefaults.standard.removeObject(forKey: Self.localDataLostKey)
            } catch {
                Self.logger.error("First-launch restore failed, will retry: \(error.localizedDescription, privacy: .public)")
            }
        case .done:
            UserDefaults.standard.set(true, forKey: Self.backupBootstrapKey)
        case .wait, .awaitUser:
            break
        }
    }

    private var isBackupBootstrapDone: Bool {
        UserDefaults.standard.bool(forKey: Self.backupBootstrapKey)
    }

    private var isLocalEmpty: Bool {
        store.items.isEmpty && store.tags.isEmpty
    }

    /// Side-effect free, so the menu can show it too.
    private func backupBootstrapDecision(localWasEmptyAtFirstCheck: Bool?) -> BackupBootstrapDecision {
        BackupBootstrap.decide(
            isAvailable: backup.isAvailable,
            hasBackup: backup.hasBackup,
            localIsEmpty: isLocalEmpty,
            localWasEmptyAtFirstCheck: localWasEmptyAtFirstCheck,
            hasOwnBackup: lastBackupDate != nil
        )
    }

    /// nil when the automatic backup may replace the backup in iCloud.
    private var automaticBackupBlock: AutomaticBackupBlock? {
        BackupBootstrap.automaticBackupBlock(
            hasBackup: backup.hasBackup,
            hasOwnBackup: lastBackupDate != nil,
            localDataWasLost: UserDefaults.standard.bool(forKey: Self.localDataLostKey)
        )
    }

    private func backUpIfChanged() {
        restoreOnFirstLaunchIfNeeded()
        guard isBackupBootstrapDone,
              backup.isAvailable,
              automaticBackupBlock == nil,
              backup.hasChanges(since: lastBackupDate) else {
            return
        }
        performBackup(manual: false)
    }

    @discardableResult
    private func performBackup(manual: Bool) -> Bool {
        do {
            try backup.backUp()
            UserDefaults.standard.set(Date(), forKey: Self.lastBackupKey)
            // Only the user's choice lifts it: an automatic backup that ran because iCloud had not listed the
            // backup yet must not drop the protection.
            if manual {
                UserDefaults.standard.removeObject(forKey: Self.localDataLostKey)
            }
            return true
        } catch {
            Self.logger.error("Backup failed: \(error.localizedDescription, privacy: .public)")
            if manual {
                showError("Could not back up to iCloud Drive", error: error)
            }
            return false
        }
    }

    @objc private func backUpNow() {
        // A backup this Mac did not make (or one the first-launch decision has not settled), or one that may hold
        // what a damaged local file lost, is only replaced after the user confirms it.
        let block = automaticBackupBlock
        if backup.hasBackup, block != nil || !isBackupBootstrapDone {
            let alert = NSAlert()
            alert.messageText = "Replace the iCloud backup?"
            alert.informativeText = block == .localDataLost
                ? "This Mac's history or tags were found damaged and may be missing items the backup still has. It will be replaced with this Mac's data."
                : "iCloud Drive already holds a backup that was not made from this Mac. It will be replaced with this Mac's data."
            alert.addButton(withTitle: "Replace")
            alert.addButton(withTitle: "Cancel")
            NSApp.activate()
            let response = alert.runModal()
            NSApp.hide(nil)
            guard response == .alertFirstButtonReturn else {
                return
            }
        }
        // A successful manual backup also counts as the first-launch decision: this Mac's data wins.
        if performBackup(manual: true) {
            UserDefaults.standard.set(true, forKey: Self.backupBootstrapKey)
        }
    }

    @objc private func restoreBackup() {
        let alert = NSAlert()
        alert.messageText = "Restore from iCloud Drive?"
        alert.informativeText = "The local history and tags will be replaced."
        alert.addButton(withTitle: "Restore")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            do {
                try backup.restore()
                // A restore the user asked for wins, even with sync off: turning sync on later must not let an older
                // deletion from another Mac remove what was just restored.
                store.reloadFromDisk(markingChanges: true)
                UserDefaults.standard.set(Date(), forKey: Self.lastBackupKey)
                UserDefaults.standard.set(true, forKey: Self.backupBootstrapKey)
                UserDefaults.standard.removeObject(forKey: Self.localDataLostKey)
            } catch {
                Self.logger.error("Restore failed: \(error.localizedDescription, privacy: .public)")
                showError("Could not restore the backup", error: error)
            }
        }
        NSApp.hide(nil)
    }

    private func showError(_ message: String, error: Error) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = Self.describe(error)
        NSApp.activate()
        alert.runModal()
        NSApp.hide(nil)
    }

    private static func describe(_ error: Error) -> String {
        switch error as? BackupError {
        case .iCloudUnavailable:
            return "iCloud Drive is not available."
        case .noBackup:
            return "There is no backup in iCloud."
        case .incompleteBackup:
            return "The iCloud backup is incomplete or has not been downloaded yet. Open it in Finder and try again."
        case .nothingToBackUp:
            return "There is nothing to back up yet."
        case .corruptBackup:
            return "The iCloud backup is damaged and cannot be restored."
        case .unreadableLocalData:
            return "This Mac's history, tags or images folder cannot be read, so they were not backed up."
        case nil:
            return error.localizedDescription
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshBackupItems()
        refreshSyncItems()
    }

    private func refreshBackupItems() {
        guard backup.isAvailable else {
            backupNowItem.isEnabled = false
            restoreItem.isEnabled = false
            restoreItem.title = "Restore from iCloud…"
            backupInfoItem.title = "iCloud Drive not available"
            return
        }
        let hasBackup = backup.hasBackup
        backupNowItem.isEnabled = true
        restoreItem.isEnabled = hasBackup
        restoreItem.title = hasBackup
            ? "Restore from iCloud…"
            : "No Backup in iCloud"
        let isAwaitingUser = !isBackupBootstrapDone
            && backupBootstrapDecision(
                localWasEmptyAtFirstCheck: UserDefaults.standard.object(forKey: Self.backupBootstrapLocalWasEmptyKey) as? Bool
            ) == .awaitUser
        let block = automaticBackupBlock
        guard !isAwaitingUser, block != .notOwnBackup else {
            backupInfoItem.title = "iCloud backup not restored: restore it or make a new backup"
            return
        }
        guard block != .localDataLost else {
            backupInfoItem.title = "Local data was damaged: restore the backup or make a new one"
            return
        }
        backupInfoItem.title = lastBackupDate
            .map { "Last backup: \(Self.relativeFormatter.localizedString(for: $0, relativeTo: Date()))" }
            ?? "No backups yet"
    }

    /// Registers only on first launch so a user who disables it in System Settings is respected.
    private func registerLoginItem() {
        let registeredKey = "loginItemRegistered"
        guard !UserDefaults.standard.bool(forKey: registeredKey) else {
            return
        }
        do {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
            UserDefaults.standard.set(true, forKey: registeredKey)
        } catch {
            Self.logger.error("Cannot register login item: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Shows the system dialog that leads to System Settings > Privacy > Accessibility.
    private func requestAccessibilityIfNeeded() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
