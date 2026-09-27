import Foundation
import StreamProtocol

// The keys this device sends for a shortcut: the Spotlight key's ⌘Space, the portrait key row's keys
// with whatever is latched, a latched ⌘, ⌃ or ⌥ on the software keyboard, and the modifiers the
// portrait trackpad holds down around a click or a drag. One place, so each is sent the same way.
//
// Pure: Foundation and StreamProtocol only, checked with swiftc beside the host's KeyStrokes
// (Tests/checks/key-strokes), which is what the Mac makes of these events.

/// The modifier bits an `InputEvent.key` carries: `UIKeyModifierFlags` raw values, which sit at the
/// same bit positions as the `CGEventFlags` the host posts with, so they travel unchanged.
struct KeyModifiers: OptionSet {
    let rawValue: UInt64

    static let shift   = KeyModifiers(rawValue: 1 << 17)
    static let control = KeyModifiers(rawValue: 1 << 18)
    static let option  = KeyModifiers(rawValue: 1 << 19)
    static let command = KeyModifiers(rawValue: 1 << 20)

    /// The three that make shortcuts instead of characters. Shift is not one of them: it changes
    /// which character the keyboard produces, which the text path already handles.
    static let shortcutMakers: KeyModifiers = [.control, .option, .command]

    /// Each latched modifier as its own key: the HID usage to press, and the bit it contributes.
    /// A pointer event has no modifier field, so a modified click has to hold these down around it.
    var keys: [(usage: UInt16, flag: KeyModifiers)] {
        var out: [(usage: UInt16, flag: KeyModifiers)] = []
        if contains(.control) { out.append((0xE0, .control)) }
        if contains(.shift)   { out.append((0xE1, .shift)) }
        if contains(.option)  { out.append((0xE2, .option)) }
        if contains(.command) { out.append((0xE3, .command)) }
        return out
    }
}

enum KeyChord {
    /// One key, down and up, each carrying `modifiers`.
    static func press(_ usage: UInt16, with modifiers: KeyModifiers) -> [InputEvent] {
        [.key(hidUsage: usage, down: true, modifiers: modifiers.rawValue),
         .key(hidUsage: usage, down: false, modifiers: modifiers.rawValue)]
    }

    /// Spotlight on the Mac: exactly ⌘Space, down then up.
    static let spotlight: [InputEvent] = press(0x2C, with: .command)

    /// Each of `modifiers`' own keys going down, in `KeyModifiers.keys`' order, each carrying the
    /// flags in force once it is down: what the trackpad presses before a modified click or drag.
    static func modifiersDown(_ modifiers: KeyModifiers) -> [InputEvent] {
        var held: KeyModifiers = []
        return modifiers.keys.map { key in
            held.insert(key.flag)
            return .key(hidUsage: key.usage, down: true, modifiers: held.rawValue)
        }
    }

    /// The same keys going up in the reverse order, each carrying the flags still in force after it:
    /// what the trackpad releases after the click or the drag.
    static func modifiersUp(_ modifiers: KeyModifiers) -> [InputEvent] {
        var held = modifiers
        return modifiers.keys.reversed().map { key in
            held.remove(key.flag)
            return .key(hidUsage: key.usage, down: false, modifiers: held.rawValue)
        }
    }
}
