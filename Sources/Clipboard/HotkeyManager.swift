import Carbon.HIToolbox

/// Global ⇧⌘V via Carbon; needs no Accessibility permission.
/// "V" is the key that types "v" in the layout active at registration, not the physical ANSI V key.
@MainActor
final class HotkeyManager {
    private let onPress: @MainActor () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    init(onPress: @escaping @MainActor () -> Void) {
        self.onPress = onPress
    }

    /// Returns false when the shortcut could not be registered.
    func register() -> Bool {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else {
                    return noErr
                }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                MainActor.assumeIsolated {
                    manager.onPress()
                }
                return noErr
            },
            1,
            &eventType,
            userData,
            &handlerRef
        )
        guard handlerStatus == noErr else {
            return false
        }
        let hotKeyID = EventHotKeyID(signature: OSType(0x434C_4950), id: 1) // 'CLIP'
        // The "v" key is resolved once, for the layout active now; a later layout switch is not followed.
        let status = RegisterEventHotKey(
            UInt32(KeyboardLayout.keyCodeForV()),
            UInt32(cmdKey | shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        return status == noErr
    }
}
