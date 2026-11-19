import Observation
import SwiftUI

/// What the settings window shows. `AppDelegate` owns the values and refreshes them.
@MainActor
@Observable
final class SettingsState {
    var opensAtLogin = false
    var isBackupAvailable = false
    var hasBackup = false
    var backupInfo = ""
    var isSyncEnabled = false
    /// False when sync is off and iCloud Drive is not there to turn it on.
    var canToggleSync = false
    /// Empty when there is nothing to say (sync off and possible).
    var syncInfo = ""
}

@MainActor
struct SettingsActions {
    let setOpensAtLogin: @MainActor (Bool) -> Void
    let backUpNow: @MainActor () -> Void
    let restoreBackup: @MainActor () -> Void
    let setSyncEnabled: @MainActor (Bool) -> Void
}

struct SettingsView: View {
    let state: SettingsState
    let actions: SettingsActions

    var body: some View {
        Form {
            Section("General") {
                Toggle(
                    "Open at Login",
                    isOn: Binding(get: { state.opensAtLogin }, set: actions.setOpensAtLogin)
                )
            }
            Section("iCloud Drive Backup") {
                LabeledContent(state.backupInfo) {
                    Button("Back Up Now", action: actions.backUpNow)
                        .disabled(!state.isBackupAvailable)
                    Button("Restore…", action: actions.restoreBackup)
                        .disabled(!state.hasBackup)
                }
            }
            Section {
                Toggle(
                    "Sync Between Macs",
                    isOn: Binding(get: { state.isSyncEnabled }, set: actions.setSyncEnabled)
                )
                .disabled(!state.canToggleSync)
                if !state.syncInfo.isEmpty {
                    Text(state.syncInfo)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Sync")
            } footer: {
                Text("The history and the tags are kept in iCloud Drive and joined with those of your other Macs. Anything copied as concealed, such as a password from 1Password, never leaves this Mac.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}
