import Observation
import SwiftUI

/// What the settings window shows. `AppDelegate` owns the value and refreshes it.
@MainActor
@Observable
final class SettingsState {
    var opensAtLogin = false
}

struct SettingsView: View {
    let state: SettingsState
    let setOpensAtLogin: @MainActor (Bool) -> Void

    var body: some View {
        Form {
            Section("General") {
                Toggle(
                    "Open at Login",
                    isOn: Binding(get: { state.opensAtLogin }, set: setOpensAtLogin)
                )
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}
