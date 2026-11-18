import Carbon.HIToolbox
import CoreGraphics

/// Virtual key codes name physical keys, not characters: on Dvorak the key at kVK_ANSI_V types ".".
@MainActor
enum KeyboardLayout {
    /// The key code that types "v" in the current layout, or kVK_ANSI_V when the layout cannot be read
    /// (e.g. layouts without Unicode layout data).
    /// Translated with ⌘ held: layouts such as "Dvorak – QWERTY ⌘" switch to QWERTY while ⌘ is down, and every
    /// caller sends or listens for a ⌘ shortcut.
    static func keyCodeForV() -> CGKeyCode {
        let fallback = CGKeyCode(kVK_ANSI_V)
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else {
            return fallback
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue()
        return withExtendedLifetime(source) {
            guard let bytes = CFDataGetBytePtr(layoutData) else {
                return fallback
            }
            let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
            let commandState = UInt32((cmdKey >> 8) & 0xFF)
            let keyboardType = UInt32(LMGetKbdType())
            let target = UniChar(UInt8(ascii: "v"))
            for keyCode in 0..<128 {
                var deadKeyState: UInt32 = 0
                var characters = [UniChar](repeating: 0, count: 4)
                var length = 0
                let status = UCKeyTranslate(
                    layout,
                    UInt16(keyCode),
                    UInt16(kUCKeyActionDown),
                    commandState,
                    keyboardType,
                    OptionBits(kUCKeyTranslateNoDeadKeysMask),
                    &deadKeyState,
                    characters.count,
                    &length,
                    &characters
                )
                if status == noErr, length == 1, characters[0] == target {
                    return CGKeyCode(keyCode)
                }
            }
            return fallback
        }
    }
}
