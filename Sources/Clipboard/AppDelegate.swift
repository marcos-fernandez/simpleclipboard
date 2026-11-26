import AppKit
import ApplicationServices
import ClipboardCore
import os
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    /// Where installing the offered update has got to; the menu item shows it.
    private enum UpdateInstallState {
        case idle
        case downloading
        /// On disk, waiting for a restart.
        case installed(AppVersion)
    }

    private static let logger = Logger(subsystem: Config.bundleID, category: "AppDelegate")

    private var store: HistoryStore!
    /// Writes the store's saves in the background: flushed before anything reads the files from disk.
    private var persistence: BackgroundPersistence!
    private var monitor: ClipboardMonitor!
    private var panel: PanelController!
    private var hotkey: HotkeyManager!
    private var statusItem: NSStatusItem!
    private var hotkeyRegistered = false
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

    /// "Pause", or "Paused until 10:30" while paused, with its submenu: "Resume" while paused, and the durations.
    private var pauseItem: NSMenuItem!
    /// One-shot, at the end of the pause, to put the icon back.
    private var pauseTimer: Timer?
    private var resumeItem: NSMenuItem!
    private var resumeSeparator: NSMenuItem!

    private static let cardFontKey = "cardFont"
    private static let ignoredAppsKey = "ignoredSourceBundleIDs"
    private static let loginItemRegisteredKey = "loginItemRegistered"
    private static let panelDensityKey = "panelDensity"
    private static let pausedUntilKey = "pausedUntil"
    private static let pickActionKey = "pickAction"
    private static let securedAppsKey = "concealedSourceBundleIDs"
    private static let securedLifetimeKey = "concealedLifetime"
    private static let showsMenuBarIconKey = "showsMenuBarIcon"
    /// Set once the question of the first launch has been answered.
    private static let welcomeShownKey = "welcomeShown"
    /// What "Reset All Settings…" removes: what the settings window and the welcome save, and a pause, so the app
    /// comes back recording. Not the keys of the backup, which say what it has done and are no choice of the user.
    private static let settingsKeys = [
        cardFontKey, ignoredAppsKey, loginItemRegisteredKey, panelDensityKey, pausedUntilKey, pickActionKey,
        securedAppsKey, securedLifetimeKey, showsMenuBarIconKey, welcomeShownKey,
    ]

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
    private let updateDownloadSession = UpdateCheck.makeSession(timeout: Config.updateDownloadTimeout)
    private var updateTimer: Timer?
    private var updateInstallState = UpdateInstallState.idle
    private var availableUpdate: AppVersion?
    private var lastUpdateAnswer: Date?
    private var updateItem: NSMenuItem!
    private var updateSeparator: NSMenuItem!

    /// In English like the rest of the app, whatever the language of the system.
    private static let listFormatter: ListFormatter = {
        let formatter = ListFormatter()
        formatter.locale = Locale(identifier: "en_US")
        return formatter
    }()

    /// In English like the rest of the menu, whatever the language of the system.
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "en_US")
        return formatter
    }()

    /// Whether this launch is the first of the app on this Mac: its data folder was not there. Set at launch.
    private var isNewInstall = false

    private var cardFont: CardFont {
        CardFont(stored: UserDefaults.standard.string(forKey: Self.cardFontKey))
    }

    private var isPaused: Bool {
        Pause.isActive(until: pausedUntil, now: Date())
    }

    private var panelDensity: PanelDensity {
        PanelDensity(stored: UserDefaults.standard.string(forKey: Self.panelDensityKey))
    }

    /// Saved, so quitting or restarting does not end a pause.
    private var pausedUntil: Date? {
        UserDefaults.standard.object(forKey: Self.pausedUntilKey) as? Date
    }

    private var pickAction: PickAction {
        PickAction(stored: UserDefaults.standard.string(forKey: Self.pickActionKey))
    }

    private var securedLifetime: TimeInterval {
        ConcealedLifetime.lifetime(stored: UserDefaults.standard.object(forKey: Self.securedLifetimeKey) as? Double)
    }

    /// The saved "Show in Menu Bar", missing until the user changes it (see `MenuBarIcon`).
    private var storedShowsMenuBarIcon: Bool? {
        UserDefaults.standard.object(forKey: Self.showsMenuBarIconKey) as? Bool
    }

    /// Whether the menu-bar item is on show, which the setting alone does not decide.
    private var isMenuBarIconShown: Bool {
        MenuBarIcon.isShown(stored: storedShowsMenuBarIcon, hotkeyRegistered: hotkeyRegistered)
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
        // After the migration, which brings the folder of the old app name, and before anything creates it.
        isNewInstall = !FileManager.default.fileExists(atPath: directory.path)

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
        store.concealedLifetime = securedLifetime
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

        monitor = ClipboardMonitor(
            store: store,
            concealedSourceBundleIDs: { [weak self] in
                Set(self?.apps(of: .secured) ?? [])
            },
            ignoredSourceBundleIDs: { [weak self] in
                Set(self?.apps(of: .ignored) ?? [])
            }
        )
        monitor.isPaused = { [weak self] in
            self?.isPaused ?? false
        }
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
            if Paster.paste(item, imageData: store.imageData(for: item), into: target, action: pickAction) {
                store.promote(id: item.id)
            }
        }
        panel.cardFont = cardFont
        panel.density = panelDensity

        hotkey = HotkeyManager { [weak self] in
            self?.panel.toggle()
        }
        hotkeyRegistered = hotkey.register()
        if !hotkeyRegistered {
            Self.logger.error("Cannot register ⇧⌘V")
        }

        settings = SettingsWindowController(
            state: settingsState,
            actions: SettingsActions(
                addApps: { [weak self] list in
                    self?.addApps(to: list)
                },
                checkForUpdates: { [weak self] in
                    self?.checkForUpdate(askedByUser: true)
                },
                openAccessibilitySettings: {
                    NSWorkspace.shared.open(Config.accessibilitySettingsURL)
                },
                removeApp: { [weak self] bundleID, list in
                    self?.removeApp(bundleID, from: list)
                },
                resetAllSettings: { [weak self] in
                    self?.resetAllSettings()
                },
                resetPrivacy: { [weak self] in
                    self?.resetPrivacy()
                },
                setCardFont: { [weak self] font in
                    self?.setCardFont(font)
                },
                setOpensAtLogin: { [weak self] isOn in
                    self?.setOpensAtLogin(isOn)
                },
                setPanelDensity: { [weak self] density in
                    self?.setPanelDensity(density)
                },
                setPickAction: { [weak self] action in
                    self?.setPickAction(action)
                },
                setSecuredLifetime: { [weak self] lifetime in
                    self?.setSecuredLifetime(lifetime)
                },
                setShowsMenuBarIcon: { [weak self] isOn in
                    self?.setShowsMenuBarIcon(isOn)
                }
            ),
            onBecomeKey: { [weak self] in
                self?.refreshSettings()
            }
        )
        setUpStatusItem()
        startUpdateChecks()
        // A new install is asked first how to paste and whether to open at login; the permission and the login item
        // wait for its answer. One that already ran (its login item was registered) is never asked.
        if UserDefaults.standard.bool(forKey: Self.welcomeShownKey)
            || UserDefaults.standard.bool(forKey: Self.loginItemRegisteredKey) {
            registerLoginItem()
            // Only pasting needs the permission: set to copy, the app does not ask for it at launch.
            if pickAction == .pasteDirectly {
                requestAccessibilityIfNeeded()
            }
        } else {
            // At the next turn: the alert is modal, and the launch has to end first. From the run loop and not as a
            // task: a modal alert opened from a job of the main queue holds every other one back until it closes,
            // and what is copied meanwhile would not reach the history.
            RunLoop.main.perform { [weak self] in
                MainActor.assumeIsolated {
                    self?.showWelcome()
                }
            }
        }
    }

    /// An alert, as the app's other questions are, with the choices under its text.
    private func showWelcome() {
        let alert = NSAlert()
        let state = WelcomeState()
        defer {
            handFocusBack()
            // Nothing of ours is left on show. `handFocusBack` has nothing to go by when the login item failed: its
            // alert took the record of the app in front.
            NSApp.hide(nil)
        }
        // An install that ran before but never got its login item registered, or that came from the old app name,
        // is asked too: it starts on the way of pasting it had, chosen or not. Only a new one starts on copying.
        state.pickAction = PickAction.atWelcome(
            isNewInstall: isNewInstall, stored: UserDefaults.standard.string(forKey: Self.pickActionKey)
        )
        // The alert has no text of its own: its title cannot be made larger, so the welcome is drawn in the view.
        alert.messageText = ""
        alert.accessoryView = WelcomeView.accessoryView(state: state)
        alert.addButton(withTitle: "Done")
        runAlert(alert)

        UserDefaults.standard.set(true, forKey: Self.welcomeShownKey)
        // Against what the system has, which outlives the preferences of a reinstalled app: only a difference is
        // a change to make, and asking to remove a login item that is not there fails.
        if state.opensAtLogin != (SMAppService.mainApp.status == .enabled) {
            setOpensAtLogin(state.opensAtLogin)
        } else {
            // The user has chosen: the first-launch registration must not run at the next launch.
            UserDefaults.standard.set(true, forKey: Self.loginItemRegisteredKey)
        }
        // Asks for the Accessibility permission when the choice is to paste.
        setPickAction(state.pickAction)
    }

    /// Opening the app again (Finder, Spotlight, `open`) shows the history, whose menu button opens the menu. It is the
    /// way in that is left with the menu-bar icon hidden, by the setting or by macOS, and ⇧⌘V taken by another app:
    /// registering it succeeds even then.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panel.show()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        // The last copies may still be converting, and the last changes on their way to disk.
        monitor.flush()
        persistence.flush()
        Paster.clearConcealedValue()
    }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let menu = NSMenu()
        // Hidden until a check finds a newer release, so without one the menu is unchanged.
        updateItem = NSMenuItem(title: "", action: #selector(chooseUpdate), keyEquivalent: "")
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
        // With "Quit": the two ways of stopping the app, for a while or for good.
        pauseItem = NSMenuItem(title: "Pause", action: nil, keyEquivalent: "")
        let pauseMenu = NSMenu()
        // Only while paused; the durations stay, to pause for another while counted from then.
        resumeItem = NSMenuItem(title: "Resume", action: #selector(resume), keyEquivalent: "")
        resumeItem.target = self
        pauseMenu.addItem(resumeItem)
        resumeSeparator = .separator()
        pauseMenu.addItem(resumeSeparator)
        for duration in Pause.durations {
            let item = NSMenuItem(title: Pause.title(of: duration), action: #selector(pause(_:)), keyEquivalent: "")
            item.representedObject = duration
            item.target = self
            pauseMenu.addItem(item)
        }
        pauseItem.submenu = pauseMenu
        menu.addItem(pauseItem)
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        // Manual enabling: with auto-enabling, AppKit would re-enable items that have a target.
        menu.autoenablesItems = false
        menu.delegate = self
        refreshBackupItems()
        refreshPauseItems()
        refreshSyncItems()
        statusItem.menu = menu
        panel.menu = menu
        applyMenuBarIconSetting()
        // A pause may come from before the app was quit.
        refreshPause()
        // The timer of its end stands still while the Mac sleeps, and goes by the clock it was set with: after a
        // sleep or a change of the clock the pause is looked at again against its saved end, and the timer set for
        // what is left of it. Otherwise the icon would say "paused" after recording has started again.
        _ = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshPause()
            }
        }
        _ = NotificationCenter.default.addObserver(
            forName: .NSSystemClockDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshPause()
            }
        }
    }

    /// The one place that draws the menu-bar icon: with an arrow when a release is out, dimmed while paused. The menu
    /// button of the history shows the same icon, so the two never disagree.
    private func refreshStatusIcon() {
        let hasUpdate = availableUpdate != nil
        let isOnPause = isPaused
        let plain = "doc.on.clipboard"
        let states = [
            hasUpdate
                ? "update available"
                : nil,
            isOnPause
                ? "paused"
                : nil,
        ].compactMap { $0 }
        let description = ([Config.appName] + states).joined(separator: ", ")
        var icon = NSImage(
            systemSymbolName: hasUpdate
                ? "arrow.up.doc.on.clipboard"
                : plain,
            accessibilityDescription: description
        )
        if hasUpdate {
            // Coloured, so no longer a template image: the arrow alone is too small to notice in the menu bar. Blue
            // is what the system uses for what is new.
            icon = icon?.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.systemBlue]))
        }
        // Falls back to the plain icon: a symbol missing on this macOS would leave the menu-bar item invisible.
        icon = icon ?? NSImage(systemSymbolName: plain, accessibilityDescription: description)
        statusItem.button?.image = icon
        // Paused is the same icon dimmed, as the system dims what is off, and not another symbol: in the menu bar
        // the icon is all that says whose item it is. It still opens the menu.
        statusItem.button?.appearsDisabled = isOnPause
        panel.menuIcon = icon.map {
            MenuIcon(
                image: $0,
                isDimmed: isOnPause,
                label: (["\(Config.appName) Menu"] + states).joined(separator: ", ")
            )
        }
    }

    // MARK: pause

    @objc private func pause(_ sender: NSMenuItem) {
        guard let duration = sender.representedObject as? TimeInterval else {
            return
        }
        UserDefaults.standard.set(Date().addingTimeInterval(duration), forKey: Self.pausedUntilKey)
        refreshPause()
    }

    @objc private func resume() {
        UserDefaults.standard.removeObject(forKey: Self.pausedUntilKey)
        refreshPause()
    }

    /// The icon as the saved end of the pause says now, and the timer for that end.
    private func refreshPause() {
        refreshStatusIcon()
        schedulePauseEnd()
    }

    /// The icon goes back when the pause ends, not at the next look of the purge timer.
    private func schedulePauseEnd() {
        pauseTimer?.invalidate()
        pauseTimer = nil
        guard let end = pausedUntil, Pause.isActive(until: end, now: Date()) else {
            return
        }
        let timer = Timer(fire: end, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshStatusIcon()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pauseTimer = timer
    }

    private func refreshPauseItems() {
        // Read once: the end and whether it has come must be of the same moment.
        guard let end = pausedUntil, Pause.isActive(until: end, now: Date()) else {
            resumeItem.isHidden = true
            resumeSeparator.isHidden = true
            pauseItem.title = "Pause"
            return
        }
        resumeItem.isHidden = false
        resumeSeparator.isHidden = false
        // The time as the user has it set (12 or 24 hours): it is numbers, whatever the language of the rest.
        pauseItem.title = "Paused until \(end.formatted(date: .omitted, time: .shortened))"
    }

    /// Shows or hides the menu-bar item.
    private func applyMenuBarIconSetting() {
        // Hidden, not removed: it comes back in the place the user gave it in the menu bar.
        statusItem.isVisible = isMenuBarIconShown
    }

    private func setShowsMenuBarIcon(_ isOn: Bool) {
        UserDefaults.standard.set(isOn, forKey: Self.showsMenuBarIconKey)
        applyMenuBarIconSetting()
        refreshSettings()
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

    /// `askedByUser`: from the About pane of the settings. Checks whenever the last answer came, and the pane shows
    /// how it went.
    private func checkForUpdate(askedByUser: Bool = false) {
        guard askedByUser || UpdateCheck.isDue(lastAnswer: lastUpdateAnswer, now: Date()) else {
            return
        }
        if askedByUser {
            settingsState.updateCheck = .checking
        }
        let session = updateSession
        let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        Task { [weak self] in
            // The request and the parsing run off the main actor; only the result comes back to it.
            let result = await UpdateCheck.check(currentVersion: currentVersion) {
                try await session.data(from: Config.latestReleaseAPIURL)
            }
            self?.showUpdate(result)
            if askedByUser {
                self?.settingsState.updateCheck = .answered(result)
            } else if result != .failed, self?.settingsState.updateCheck != .checking {
                // A later answer has come: the one on show in the pane is old.
                self?.settingsState.updateCheck = .notAsked
            }
        }
    }

    private func showUpdate(_ result: UpdateCheckResult) {
        if result != .failed {
            lastUpdateAnswer = Date()
        }
        // Once an update is on its way the item stands for it: the running app still says the old version, so a
        // check would offer the same update again.
        guard case .idle = updateInstallState else {
            return
        }
        availableUpdate = result.availableUpdate(replacing: availableUpdate)
        updateItem.isHidden = availableUpdate == nil
        updateSeparator.isHidden = availableUpdate == nil
        refreshUpdateItem()
        // Set here and not in menuNeedsUpdate: the icon has to change without the menu being opened.
        refreshStatusIcon()
    }

    private func refreshUpdateItem() {
        switch updateInstallState {
        case .idle:
            updateItem.title = availableUpdate
                .map { "Update Available: \($0)…" }
                ?? ""
            updateItem.isEnabled = true
        case .downloading:
            updateItem.title = "Downloading Update…"
            updateItem.isEnabled = false
        case .installed(let version):
            updateItem.title = "Restart to Update to \(version)"
            updateItem.isEnabled = true
        }
        // An update on its way is not looked for again: `showUpdate` would leave the answer aside.
        if case .idle = updateInstallState {
            settingsState.canCheckForUpdates = true
        } else {
            settingsState.canCheckForUpdates = false
            // "Install it from the menu" is no longer so.
            settingsState.updateCheck = .notAsked
        }
    }

    @objc private func chooseUpdate() {
        switch updateInstallState {
        case .idle:
            if let availableUpdate {
                installUpdate(availableUpdate)
            }
        case .downloading:
            // The item is disabled meanwhile.
            break
        case .installed:
            restart()
        }
    }

    private func installUpdate(_ version: AppVersion) {
        let requirement: String
        do {
            requirement = try UpdateInstaller.runningAppRequirement()
        } catch {
            updateFailed(.signature)
            return
        }
        updateInstallState = .downloading
        refreshUpdateItem()
        let session = updateDownloadSession
        let app = Bundle.main.bundleURL
        Task { [weak self] in
            // The download and the install run off the main actor; only the outcome comes back to it.
            do {
                try await UpdateInstaller.install(version: version, over: app, requirement: requirement) { url in
                    try await session.download(from: url)
                }
                self?.updateInstalled(version)
            } catch {
                self?.updateFailed(error as? UpdateInstallError ?? .download)
            }
        }
    }

    private func updateInstalled(_ version: AppVersion) {
        updateInstallState = .installed(version)
        refreshUpdateItem()
        let alert = NSAlert()
        alert.messageText = "\(Config.appName) \(version) is installed"
        alert.informativeText = "Restart now to use it, or later: it opens the next time \(Config.appName) starts."
        alert.addButton(withTitle: "Restart")
        alert.addButton(withTitle: "Later")
        if runAlert(alert) == .alertFirstButtonReturn {
            restart()
        } else {
            handFocusBack()
        }
    }

    private func updateFailed(_ error: UpdateInstallError) {
        updateInstallState = .idle
        refreshUpdateItem()
        let alert = NSAlert()
        alert.messageText = "Cannot install the update"
        alert.informativeText = Self.describe(error)
        alert.addButton(withTitle: "Open Release Page")
        alert.addButton(withTitle: "Cancel")
        if runAlert(alert) == .alertFirstButtonReturn {
            // The browser comes to the front: focus is not handed back to the app that was there.
            appInFrontBeforeAlert = nil
            openReleasesPage()
        } else {
            handFocusBack()
        }
    }

    /// Opens the app on disk once this process has quit: a normal quit, so the last changes are written first.
    private func restart() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = UpdateInstaller.restartArguments(pid: getpid(), app: Bundle.main.bundleURL)
        do {
            try process.run()
        } catch {
            showError("Cannot restart \(Config.appName)", error: error)
            handFocusBack()
            return
        }
        NSApp.terminate(nil)
    }

    private func openReleasesPage() {
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
                showError("Could not back up", error: error)
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
            alert.messageText = "Replace the backup?"
            alert.informativeText = block == .localDataLost
                ? "This Mac's history or tags were found damaged and may be missing items the backup still has. It will be replaced with this Mac's data."
                : "There is already a backup that was not made from this Mac. It will be replaced with this Mac's data."
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
        alert.messageText = "Restore the backup?"
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
            return "There is no backup."
        case .incompleteBackup:
            return "The backup is incomplete: some files have not been downloaded yet, or were already missing when it was made. Open it in Finder and try again; if it still fails, make a new backup."
        case .nothingToBackUp:
            return "There is nothing to back up yet."
        case .corruptBackup:
            return "The backup is damaged and cannot be restored."
        case .unreadableLocalData:
            return "This Mac's history, tags or images folder cannot be read, so they were not backed up."
        case nil:
            return error.localizedDescription
        }
    }

    private static func describe(_ error: UpdateInstallError) -> String {
        switch error {
        case .cannotReplace:
            return "This user cannot replace \(Config.appName) in its folder. Install it from the release page instead."
        case .download:
            return "The update could not be downloaded. Check the connection, or try again later: the release may still be being published."
        case .mount:
            return "The downloaded disk image could not be opened."
        case .missingApp:
            return "The downloaded disk image does not contain \(Config.appName)."
        case .signature:
            return "The update is not signed like this copy of \(Config.appName), so it was not installed. A copy built from the source code cannot install releases."
        case .wrongVersion:
            return "The downloaded app is not the version that was offered, so it was not installed."
        }
    }

    private static func relative(_ date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshBackupItems()
        refreshPauseItems()
        // With the title of the pause: whatever the timers missed, the icon is right once the menu is looked at.
        refreshStatusIcon()
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
        // Names and icons are looked up here, once per change, and not by the view each time it draws.
        for list in PrivacyList.allCases {
            let listed = apps(of: list)
            settingsState.apps[list] = listed
                .map(AppRow.init(bundleID:))
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            // An app that left the list, as a secured one just added to the ignored ones, is no longer selected:
            // "−" would act on a row that is not there.
            if let selected = settingsState.selectedAppID[list], !listed.contains(selected) {
                settingsState.selectedAppID[list] = nil
            }
        }
        settingsState.opensAtLogin = SMAppService.mainApp.status == .enabled
        settingsState.cardFont = cardFont
        settingsState.panelDensity = panelDensity
        settingsState.pickAction = pickAction
        settingsState.securedLifetime = securedLifetime
        settingsState.isAccessibilityGranted = AXIsProcessTrusted()
        // Whether the item is on show and not the saved setting: without ⇧⌘V the icon stays, and a switch reading
        // off would say otherwise.
        settingsState.showsMenuBarIcon = isMenuBarIconShown
        settingsState.canHideMenuBarIcon = hotkeyRegistered
    }

    /// Where a list of the Privacy pane is saved and what it starts from.
    private static func storage(of list: PrivacyList) -> (key: String, defaults: Set<String>) {
        switch list {
        case .ignored:
            return (ignoredAppsKey, Config.ignoredSourceBundleIDs)
        case .secured:
            return (securedAppsKey, Config.concealedSourceBundleIDs)
        }
    }

    /// What a list of the Privacy pane holds: what the user saved or, with nothing saved, what it starts from.
    private func savedApps(of list: PrivacyList) -> [String] {
        let storage = Self.storage(of: list)
        return AppList.list(stored: UserDefaults.standard.stringArray(forKey: storage.key), defaults: storage.defaults)
    }

    /// Both lists as saved. What each shows and what is saved for it after a change are worked out from the two
    /// together (see `PrivacyLists`), and never from what a list shows.
    private var privacyLists: PrivacyLists {
        PrivacyLists(ignored: savedApps(of: .ignored), secured: savedApps(of: .secured))
    }

    /// The apps a list of the Privacy pane shows and acts on.
    private func apps(of list: PrivacyList) -> [String] {
        privacyLists.shown(list)
    }

    private func addApps(to list: PrivacyList) {
        settings.chooseApps { [weak self] urls in
            guard let self else {
                return
            }
            defer {
                handFocusBack()
            }
            // Something that is not an app with an identifier cannot be told apart as the source of a copy.
            let bundleIDs = urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
            let addition = privacyLists.adding(bundleIDs, to: list)
            if let added = addition.list {
                UserDefaults.standard.set(added, forKey: Self.storage(of: list).key)
                refreshSettings()
            }
            if !addition.refused.isEmpty {
                showIgnoredCannotBeSecured(addition.refused)
            }
        }
    }

    private func removeApp(_ bundleID: String, from list: PrivacyList) {
        let apps = privacyLists.removing(bundleID, from: list)
        UserDefaults.standard.set(apps, forKey: Self.storage(of: list).key)
        refreshSettings()
    }

    private func resetPrivacy() {
        defer {
            handFocusBack()
        }
        let alert = NSAlert()
        alert.messageText = "Reset Privacy to its defaults?"
        alert.informativeText = """
            The apps you added are removed, the ones each list started with come back, and what you copy from the \
            secured apps is kept for \(ConcealedLifetime.title(of: Config.concealedLifetime)) again.
            """
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        // Only the settings window calls this: the user stays in it (see `setOpensAtLogin`).
        appInFrontBeforeAlert = .current
        guard runAlert(alert) == .alertFirstButtonReturn else {
            return
        }
        // Nothing saved is what a new install has: the values of `Config`.
        for list in PrivacyList.allCases {
            UserDefaults.standard.removeObject(forKey: Self.storage(of: list).key)
        }
        UserDefaults.standard.removeObject(forKey: Self.securedLifetimeKey)
        store.concealedLifetime = securedLifetime
        settingsState.selectedAppID = [:]
        refreshSettings()
    }

    private func resetAllSettings() {
        let alert = NSAlert()
        alert.messageText = "Reset all settings?"
        alert.informativeText = """
            The settings go back to their defaults and \(Config.appName) restarts, asking again how to paste and \
            whether to open at login. A pause ends. The history, the tags and the backup are left as they are.
            """
        alert.addButton(withTitle: "Reset and Restart")
        alert.addButton(withTitle: "Cancel")
        // Only the settings window calls this: the user stays in it (see `setOpensAtLogin`).
        appInFrontBeforeAlert = .current
        guard runAlert(alert) == .alertFirstButtonReturn else {
            handFocusBack()
            return
        }
        // Nothing saved is the defaults. The restart reads it all again, and shows the welcome.
        for key in Self.settingsKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        restart()
    }

    private func setCardFont(_ font: CardFont) {
        UserDefaults.standard.set(font.rawValue, forKey: Self.cardFontKey)
        panel.cardFont = cardFont
        refreshSettings()
    }

    private func setPanelDensity(_ density: PanelDensity) {
        UserDefaults.standard.set(density.rawValue, forKey: Self.panelDensityKey)
        panel.density = panelDensity
        refreshSettings()
    }

    private func setPickAction(_ action: PickAction) {
        UserDefaults.standard.set(action.rawValue, forKey: Self.pickActionKey)
        if action == .pasteDirectly {
            requestAccessibilityIfNeeded()
        }
        refreshSettings()
    }

    /// For what is copied from now on: an item already kept hidden goes when it was going to.
    private func setSecuredLifetime(_ lifetime: TimeInterval) {
        UserDefaults.standard.set(lifetime, forKey: Self.securedLifetimeKey)
        store.concealedLifetime = securedLifetime
        refreshSettings()
    }

    private func showIgnoredCannotBeSecured(_ bundleIDs: [String]) {
        // In quotes, as the system names an app in its alerts: "Passwords" alone reads as a word of the sentence.
        let names = Self.listFormatter.string(from: bundleIDs.map { "“\(AppRow(bundleID: $0).name)”" }) ?? ""
        let ignored = PrivacyList.ignored.title
        let alert = NSAlert()
        alert.messageText = "\(names) cannot be added to \(PrivacyList.secured.title)"
        alert.informativeText = bundleIDs.count == 1
            ? """
                It is in \(ignored), so nothing you copy from it is kept. To secure it instead, remove it from \
                \(ignored) first.
                """
            : """
                They are in \(ignored), so nothing you copy from them is kept. To secure them instead, remove them \
                from \(ignored) first.
                """
        // Only the settings window calls this: the user stays in it (see `setOpensAtLogin`).
        appInFrontBeforeAlert = .current
        runAlert(alert)
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
            // From the settings window, the user stays in it, even when the click that flipped the switch is the
            // one that brought it forward and another app is still in front. The welcome hides the app itself.
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
