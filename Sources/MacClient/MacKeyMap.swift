import AppKit

/// This Mac's keys as the wire carries them (InputEvent.key): a macOS virtual keycode (kVK_*) to its
/// USB HID usage, and NSEvent's modifier flags to the bits the host reads (UIKeyModifierFlags, the
/// same bit positions as CGEventFlags and NSEvent.ModifierFlags). The table is the exact inverse of
/// the host's `KeyStrokes.virtualKeys` (Sources/SillHost/KeyStrokes.swift), so every key the host
/// can post is one the client sends and nothing else is; `Tests/checks/mac-keys` holds the two to
/// that. A key outside it (a numeric keypad's, F13 and up, media keys) is not sent.
enum MacKeyMap {
    static let hidUsages: [UInt16: UInt16] = [
        // Letters A…Z
        0: 0x04, 11: 0x05, 8: 0x06, 2: 0x07, 14: 0x08, 3: 0x09, 5: 0x0A, 4: 0x0B, 34: 0x0C,
        38: 0x0D, 40: 0x0E, 37: 0x0F, 46: 0x10, 45: 0x11, 31: 0x12, 35: 0x13, 12: 0x14,
        15: 0x15, 1: 0x16, 17: 0x17, 32: 0x18, 9: 0x19, 13: 0x1A, 7: 0x1B, 16: 0x1C, 6: 0x1D,
        // Digits 1…9, 0
        18: 0x1E, 19: 0x1F, 20: 0x20, 21: 0x21, 23: 0x22, 22: 0x23, 26: 0x24, 28: 0x25,
        25: 0x26, 29: 0x27,
        // Editing and punctuation
        36: 0x28,   // Return
        53: 0x29,   // Escape
        51: 0x2A,   // Delete (backspace)
        48: 0x2B,   // Tab
        49: 0x2C,   // Space
        27: 0x2D,   // -
        24: 0x2E,   // =
        33: 0x2F,   // [
        30: 0x30,   // ]
        42: 0x31,   // \
        41: 0x33,   // ;
        39: 0x34,   // '
        50: 0x35,   // `
        43: 0x36,   // ,
        47: 0x37,   // .
        44: 0x38,   // /
        57: 0x39,   // Caps Lock
        // F1…F12
        122: 0x3A, 120: 0x3B, 99: 0x3C, 118: 0x3D, 96: 0x3E, 97: 0x3F,
        98: 0x40, 100: 0x41, 101: 0x42, 109: 0x43, 103: 0x44, 111: 0x45,
        // Navigation
        115: 0x4A,  // Home
        116: 0x4B,  // Page Up
        117: 0x4C,  // Forward Delete
        119: 0x4D,  // End
        121: 0x4E,  // Page Down
        124: 0x4F,  // Right
        123: 0x50,  // Left
        125: 0x51,  // Down
        126: 0x52,  // Up
        // Modifiers' own keys
        59: 0xE0,   // Left Control
        56: 0xE1,   // Left Shift
        58: 0xE2,   // Left Option
        55: 0xE3,   // Left Command
        62: 0xE4,   // Right Control
        60: 0xE5,   // Right Shift
        61: 0xE6,   // Right Option
        54: 0xE7,   // Right Command
    ]

    /// The modifier flag each modifier key's keycode holds while down: a flagsChanged event says a
    /// modifier key moved, and whether it went down is whether its flag is now set.
    static let modifierFlag: [UInt16: NSEvent.ModifierFlags] = [
        59: .control, 62: .control, 56: .shift, 60: .shift,
        58: .option, 61: .option, 55: .command, 54: .command, 57: .capsLock,
    ]

    /// The wire's modifier bits: caps lock, shift, control, option, command (bits 16 to 20), and
    /// nothing else (fn, the numeric pad, device-dependent bits stay here).
    static func wireModifiers(_ flags: NSEvent.ModifierFlags) -> UInt64 {
        let kept = flags.intersection([.capsLock, .shift, .control, .option, .command])
        return UInt64(kept.rawValue)
    }
}
