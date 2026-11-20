import AppKit
import ApplicationServices
import ClipboardCore
import os
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static let logger = Logger(subsystem: Config.bundleID, category: "AppDelegate")

    private var store: HistoryStore!
    /// Writes the store's saves in the background: flushed before anything reads the files from disk.
    private var persistence: BackgroundPersistence!
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

    private static let loginItemRegisteredKey = "loginItemRegistered"
    private static let pickActionKey = "pickAction"

    private let settingsState = SettingsState()
    private var settings: SettingsWindowController!
    /// The app in front when the action under way asked for its first alert; nil while the action has shown none.
    private var appInFrontBeforeAlert: NSRunningApplication?

    private var sync: SyncService!
    private var syncStatus: SyncStatus = .off
    private var syncTimer: Timer?
    /// One-shot, restarted on every save: publishes `Config.syncPublishDelay` after the last local change.
    private var syncSoonTimer: Timer?
    private var syncItem: NSMenuItem!
    private var syncInfoItem: NSMenuItem!

    /// One for the app's lifetime: a session is only freed once invalidated.
    private let updateSession = UpdateCheck.makeSession()
    private var updateTimer: Timer?
    private var availableUpdate: AppVersion?
    private var lastUpdateAnswer: Date?
    private var updateItem: NSMenuItem!
    private var updateSeparator: NSMenuItem!

    /// In English like the rest of the menu, whatever the language of the system.
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "en_US")
        return formatter
    }()

    private var pickAction: PickAction {
        PickAction(stored: UserDefaults.standard.string(forKey: Self.pickActionKey))
    }

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
        let files = FilePersistence(directory: directory)
        persistence = BackgroundPersistence(wrapping: files)
        store = HistoryStore(persistence: persistence)
        if files.dataWasLost {
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
                // Only for a Mac that has backed up before: on a new one iCloud Drive may not have listed another
                // Mac's backup yet, and a first backup this early would replace it unseen.
                if self?.lastBackupDate != nil {
                    self?.backUpIfChanged()
                }
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

        panel = PanelController(
            store: store,
            onPick: { [weak self] item, target in
                guard let self else {
                    return
                }
                // Nothing pasted (its image file is missing) is not a use: the item keeps its place and nothing is
                // saved.
                if Paster.paste(item, imageData: store.imageData(for: item), into: target, action: pickAction) {
                    store.promote(id: item.id)
                }
            },
            onOpenSettings: { [weak self] in
                self?.openSettings()
            }
        )

        hotkey = HotkeyManager { [weak self] in
            self?.panel.toggle()
        }
        let hotkeyRegistered = hotkey.register()
        if !hotkeyRegistered {
            Self.logger.error("Cannot register ⇧⌘V")
        }

        settings = SettingsWindowController(
            state: settingsState,
            actions: SettingsActions(
                setOpensAtLogin: { [weak self] isOn in
                    self?.setOpensAtLogin(isOn)
                },
                setPickAction: { [weak self] action in
                    self?.setPickAction(action)
                },
                openAccessibilitySettings: {
                    NSWorkspace.shared.open(Config.accessibilitySettingsURL)
                }
            ),
            onBecomeKey: { [weak self] in
                self?.refreshSettings()
            }
        )
        setUpStatusItem(hotkeyRegistered: hotkeyRegistered)
        startUpdateChecks()
        registerLoginItem()
        // Only pasting needs the permission: set to copy, the app does not ask for it at launch.
        if pickAction == .pasteDirectly {
            requestAccessibilityIfNeeded()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // The last copies may still be converting, and the last changes on their way to disk.
        monitor.flush()
        persistence.flush()
        Paster.clearConcealedValue()
    }

    private func setUpStatusItem(hotkeyRegistered: Bool) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: Config.appName)

        let menu = NSMenu()
        // Hidden until a check finds a newer release, so without one the menu is unchanged.
        updateItem = NSMenuItem(title: "", action: #selector(openReleasesPage), keyEquivalent: "")
        updateItem.target = self
        updateItem.isHidden = true
        menu.addItem(updateItem)
        updateSeparator = .separator()
        updateSeparator.isHidden = true
        menu.addItem(updateSeparator)
        if !hotkeyRegistered {
            let warning = NSMenuItem(title: "⚠︎ Could not register ⇧⌘V", action: nil, keyEquivalent: "")
            warning.isEnabled = false
            menu.addItem(warning)
        }
        // Shown like the other shortcuts; the global one is registered by HotkeyManager.
        let openItem = NSMenuItem(title: "Open History", action: #selector(openHistory), keyEquivalent: "v")
        openItem.keyEquivalentModifierMask = [.command, .shift]
        openItem.target = self
        menu.addItem(openItem)
        let clearItem = NSMenuItem(title: "Clear History…", action: #selector(clearHistory), keyEquivalent: "")
        clearItem.target = self
        menu.addItem(clearItem)
        menu.addItem(.separator())
        backupNowItem = NSMenuItem(title: "Back Up Now", action: #selector(backUpNow), keyEquivalent: "")
        backupNowItem.target = self
        menu.addItem(backupNowItem)
        restoreItem = NSMenuItem(title: "Restore…", action: #selector(restoreBackup), keyEquivalent: "")
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
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
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

    @objc private func openSettings() {
        settings.show()
    }

    /// Shows `alert`. An action that may show one ends with `handFocusBack()`.
    @discardableResult
    private func runAlert(_ alert: NSAlert) -> NSApplication.ModalResponse {
        if appInFrontBeforeAlert == nil {
            appInFrontBeforeAlert = NSWorkspace.shared.frontmostApplication
        }
        AppActivation.activate()
        return alert.runModal()
    }

    /// Once per action, after its last alert: gives focus back to the app that was in front, so the next ⇧⌘V targets
    /// it and not us. The app is not hidden, which would take the settings window with it: that window stays as it
    /// was. Whether the user was in it cannot be told: a click on the menu-bar item already puts the other app in
    /// front, before the menu opens.
    private func handFocusBack() {
        guard let app = appInFrontBeforeAlert else {
            return
        }
        appInFrontBeforeAlert = nil
        guard app != .current else {
            return
        }
        if app.isTerminated {
            NSApp.hide(nil)
        } else {
            app.activate()
        }
    }

    @objc private func clearHistory() {
        defer {
            handFocusBack()
        }
        let alert = NSAlert()
        alert.messageText = "Clear the history?"
        alert.informativeText = "Untagged items will be deleted. Tagged items are kept. This cannot be undone."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        if runAlert(alert) == .alertFirstButtonReturn {
            store.removeUntagged()
        }
    }

    // MARK: updates

    /// Checks `Config.updateCheckLaunchDelay` after launch and then whenever `Config.updateCheckInterval` has passed
    /// since the last answer, looked at every `Config.updateCheckPollInterval`. A failed check is silent and changes
    /// nothing: the next look tries again.
    private func startUpdateChecks() {
        let timer = Timer(timeInterval: Config.updateCheckPollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.checkForUpdate()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        updateTimer = timer
        let launchTimer = Timer(timeInterval: Config.updateCheckLaunchDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.checkForUpdate()
            }
        }
        RunLoop.main.add(launchTimer, forMode: .common)
    }

    private func checkForUpdate() {
        guard UpdateCheck.isDue(lastAnswer: lastUpdateAnswer, now: Date()) else {
            return
        }
        let session = updateSession
        let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        Task { [weak self] in
            // The request and the parsing run off the main actor; only the result comes back to it.
            let result = await UpdateCheck.check(currentVersion: currentVersion) {
                try await session.data(from: Config.latestReleaseAPIURL)
            }
            self?.showUpdate(result)
        }
    }

    private func showUpdate(_ result: UpdateCheckResult) {
        if result != .failed {
            lastUpdateAnswer = Date()
        }
        availableUpdate = result.availableUpdate(replacing: availableUpdate)
        updateItem.isHidden = availableUpdate == nil
        updateSeparator.isHidden = availableUpdate == nil
        updateItem.title = availableUpdate
            .map { "Update Available: \($0)…" }
            ?? ""
        // Set here and not in menuNeedsUpdate: the icon has to change without the menu being opened.
        let plainIcon = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: Config.appName)
        // Falls back to the plain icon: a symbol missing on this macOS would leave the menu-bar item invisible.
        statusItem.button?.image = availableUpdate == nil
            ? plainIcon
            // Coloured, so no longer a template image: the arrow alone is too small to notice in the menu bar.
            : NSImage(systemSymbolName: "arrow.up.doc.on.clipboard", accessibilityDescription: "\(Config.appName), update available")?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.systemOrange]))
                ?? plainIcon
    }

    @objc private func openReleasesPage() {
        NSWorkspace.shared.open(Config.releasesPageURL)
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

    /// Connected whether sync is on or not: `SyncService.record` keeps deletions made while it is off once this Mac
    /// has joined, so turning sync on again does not bring them back.
    private func connectDeletionRecorder() {
        store.deletionRecorder = { [weak self] deletions in
            self?.sync.record(deletions)
        }
        store.knownDeletion = { [weak self] contentHash in
            self?.sync.latestDeletion(ofItem: contentHash)
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
        runSync()
    }

    private func refreshSyncItems() {
        let text = MenuSummary.syncText(syncStatus, isAvailable: sync.isAvailable, relative: Self.relative)
        syncItem.state = sync.isEnabled
            ? .on
            : .off
        syncItem.isEnabled = MenuSummary.canToggleSync(isEnabled: sync.isEnabled, isAvailable: sync.isAvailable)
        syncInfoItem.title = text
        syncInfoItem.isHidden = text.isEmpty
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
                // A write still on its way would land on top of the restored files.
                persistence.flush()
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
              automaticBackupBlock == nil else {
            return
        }
        // The dates compared are those of the files on disk, so the latest change must be written first.
        persistence.flush()
        guard backup.hasChanges(since: lastBackupDate) else {
            return
        }
        performBackup(manual: false)
    }

    @discardableResult
    private func performBackup(manual: Bool) -> Bool {
        do {
            // The backup copies the files on disk: the latest change must be written first.
            persistence.flush()
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
        defer {
            handFocusBack()
        }
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
            guard runAlert(alert) == .alertFirstButtonReturn else {
                return
            }
        }
        // A successful manual backup also counts as the first-launch decision: this Mac's data wins.
        if performBackup(manual: true) {
            UserDefaults.standard.set(true, forKey: Self.backupBootstrapKey)
        }
    }

    @objc private func restoreBackup() {
        defer {
            handFocusBack()
        }
        let alert = NSAlert()
        alert.messageText = "Restore from iCloud Drive?"
        alert.informativeText = "The local history and tags will be replaced."
        alert.addButton(withTitle: "Restore")
        alert.addButton(withTitle: "Cancel")
        if runAlert(alert) == .alertFirstButtonReturn {
            do {
                // After the alert: timers keep saving while it is open. A write still on its way would land on top
                // of the restored files.
                persistence.flush()
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
    }

    private func showError(_ message: String, error: Error) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = Self.describe(error)
        runAlert(alert)
    }

    private static func describe(_ error: Error) -> String {
        switch error as? BackupError {
        case .iCloudUnavailable:
            return "iCloud Drive is not available."
        case .noBackup:
            return "There is no backup in iCloud."
        case .incompleteBackup:
            return "The iCloud backup is incomplete: some files have not been downloaded yet, or were already missing when it was made. Open it in Finder and try again; if it still fails, make a new backup."
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

    private static func relative(_ date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshBackupItems()
        refreshSyncItems()
    }

    /// What the line says and when a backup can be restored is decided by `MenuSummary`; this gathers the state.
    private func refreshBackupItems() {
        let isAvailable = backup.isAvailable
        let isAwaitingUser = !isBackupBootstrapDone
            && backupBootstrapDecision(
                localWasEmptyAtFirstCheck: UserDefaults.standard.object(forKey: Self.backupBootstrapLocalWasEmptyKey) as? Bool
            ) == .awaitUser
        backupNowItem.isEnabled = isAvailable
        restoreItem.isEnabled = MenuSummary.canRestore(isAvailable: isAvailable, hasBackup: backup.hasBackup)
        backupInfoItem.title = MenuSummary.backup(
            isAvailable: isAvailable,
            isAwaitingUser: isAwaitingUser,
            block: automaticBackupBlock,
            lastBackupDate: lastBackupDate
        ).text(relative: Self.relative)
    }

    private func refreshSettings() {
        settingsState.opensAtLogin = SMAppService.mainApp.status == .enabled
        settingsState.pickAction = pickAction
        settingsState.isAccessibilityGranted = AXIsProcessTrusted()
    }

    private func setPickAction(_ action: PickAction) {
        UserDefaults.standard.set(action.rawValue, forKey: Self.pickActionKey)
        if action == .pasteDirectly {
            requestAccessibilityIfNeeded()
        }
        refreshSettings()
    }

    /// Registers only on first launch so a user who disables it, in Settings or in System Settings, is respected.
    private func registerLoginItem() {
        guard !UserDefaults.standard.bool(forKey: Self.loginItemRegisteredKey) else {
            return
        }
        do {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
            UserDefaults.standard.set(true, forKey: Self.loginItemRegisteredKey)
        } catch {
            Self.logger.error("Cannot register login item: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func setOpensAtLogin(_ isOn: Bool) {
        defer {
            handFocusBack()
        }
        // The view only hears of a value that changes: taken first, so that after a failure the refresh below puts
        // the switch back.
        settingsState.opensAtLogin = isOn
        do {
            if isOn {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            // The user has chosen: the first-launch registration must not run again.
            UserDefaults.standard.set(true, forKey: Self.loginItemRegisteredKey)
            Self.logger.info("Open at login set to \(isOn, privacy: .public)")
        } catch {
            Self.logger.error("Cannot change login item: \(error.localizedDescription, privacy: .public)")
            // Only the settings window calls this: the user stays in it, even when the click that flipped the switch
            // is the one that brought it forward and another app is still in front.
            appInFrontBeforeAlert = .current
            showError("Could not change the login item", error: error)
        }
        refreshSettings()
    }

    /// Shows the system dialog that leads to System Settings > Privacy > Accessibility.
    private func requestAccessibilityIfNeeded() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
