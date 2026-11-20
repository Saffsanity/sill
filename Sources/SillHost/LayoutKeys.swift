import Foundation
import Carbon.HIToolbox

/// Which Mac key types a character on the keyboard layout in use, and whether with Shift.
///
/// Text from a device's software keyboard used to be posted as virtual key 0 with a Unicode string.
/// AppKit's text system reads the string, but an app that reads the keycode (the iOS Simulator, a
/// virtual machine, a game, a remote desktop) saw key 0, `a`, for every character. A character that
/// a key of the layout types is therefore posted as that key (the string stays on the event for the
/// apps that read it); only a character no key types alone goes as before.
///
/// Main actor: the Text Input Sources calls belong there. The table is made again when the layout
/// changes, which is checked at each lookup by the source's ID.
@MainActor
struct LayoutKeys {
    struct Press: Equatable {
        var virtualKey: CGKeyCode
        var shift: Bool
    }

    private var layoutID: String?
    private var presses: [Character: Press] = [:]

    mutating func press(for character: Character) -> Press? {
        refreshIfLayoutChanged()
        return presses[character]
    }

    private mutating func refreshIfLayoutChanged() {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else { return }
        let id = Self.string(source, kTISPropertyInputSourceID) ?? ""
        guard id != layoutID else { return }
        layoutID = id
        presses = [:]
        guard let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        data.withUnsafeBytes { buffer in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return }
            // Without Shift first, so a character both types is the plain key. The keypad's keys are
            // left out (the main block types the same characters) and so is anything a dead key
            // would hold back: an accent typed through a key must not wait for the next letter.
            for shift in [false, true] {
                for code in CGKeyCode(0)..<CGKeyCode(127) where !Self.keypad.contains(code) {
                    guard let character = Self.character(code, shift: shift, layout: layout),
                          presses[character] == nil else { continue }
                    presses[character] = Press(virtualKey: code, shift: shift)
                }
            }
        }
    }

    /// The keypad's keycodes (kVK_ANSI_Keypad…).
    private static let keypad: Set<CGKeyCode> = [65, 67, 69, 71, 75, 76, 78, 81, 82, 83, 84, 85, 86, 87, 88, 89, 91, 92]

    private static func character(_ code: CGKeyCode, shift: Bool, layout: UnsafePointer<UCKeyboardLayout>) -> Character? {
        var dead: UInt32 = 0
        var length = 0
        var units = [UniChar](repeating: 0, count: 4)
        let modifiers = UInt32(shift ? (shiftKey >> 8) & 0xFF : 0)
        let status = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDown), modifiers,
                                    UInt32(LMGetKbdType()), 0,
                                    &dead, units.count, &length, &units)
        guard status == noErr, dead == 0, length == 1 else { return nil }
        let string = String(utf16CodeUnits: units, count: length)
        guard string.count == 1, let character = string.first,
              !(character.unicodeScalars.first.map { $0.value < 0x20 || $0.value == 0x7F } ?? true) else { return nil }
        return character
    }

    private static func string(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }
}
