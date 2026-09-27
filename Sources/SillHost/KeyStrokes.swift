import Foundation

// A device's key (kind 8's `.key`: a USB HID usage going down or up, with UIKeyModifierFlags bits) as
// the keyboard event InputInjector posts for it: the Mac's virtual key, and the flags it carries.
//
// Pure: Foundation only, checked on its own with swiftc (Tests/checks/key-strokes; its `package`
// access needs -package-name sill). Nothing here posts anything: InputInjector makes the event from
// its source and posts it.

/// One keyboard event to post: a virtual key (Carbon's kVK_*) going down or up, carrying these flags
/// (CGEventFlags bits). A modifier's own key (54 to 62) becomes a flags-changed event: CoreGraphics
/// makes one for those keycodes.
package struct KeyStroke: Equatable, Sendable {
    package var virtualKey: UInt16
    package var down: Bool
    package var flags: UInt64

    package init(virtualKey: UInt16, down: Bool, flags: UInt64) {
        self.virtualKey = virtualKey; self.down = down; self.flags = flags
    }
}

package struct KeyStrokes: Sendable {
    package init() {}

    /// A device's key: the event to post, or nil for a usage no Mac key answers to (the injector
    /// drops it and counts it).
    package mutating func key(usage: UInt16, down: Bool, modifiers: UInt64) -> KeyStroke? {
        guard let virtualKey = Self.virtualKeys[usage] else { return nil }
        return KeyStroke(virtualKey: virtualKey, down: down, flags: Self.flags(fromDevice: modifiers))
    }

    /// The client sends UIKeyModifierFlags bits. They sit at the same bit positions as the
    /// CGEventFlags masks, but build the flags explicitly rather than reinterpreting the number:
    /// anything else in there (numeric pad, iOS-only bits) has no business reaching the Mac.
    package static func flags(fromDevice modifiers: UInt64) -> UInt64 {
        var flags: UInt64 = 0
        if modifiers & (1 << 16) != 0 { flags |= capsLock }
        if modifiers & (1 << 17) != 0 { flags |= shift }
        if modifiers & (1 << 18) != 0 { flags |= control }
        if modifiers & (1 << 19) != 0 { flags |= option }
        if modifiers & (1 << 20) != 0 { flags |= command }
        return flags
    }

    /// CGEventFlags' masks, as plain bits (CoreGraphics is not imported here): maskAlphaShift,
    /// maskShift, maskControl, maskAlternate, maskCommand.
    package static let capsLock: UInt64 = 0x01_0000
    package static let shift: UInt64 = 0x02_0000
    package static let control: UInt64 = 0x04_0000
    package static let option: UInt64 = 0x08_0000
    package static let command: UInt64 = 0x10_0000

    /// USB HID usage (UIKeyboardHIDUsage on the client) → macOS virtual keycode (Carbon kVK_*).
    /// Only the keys a phone keyboard can send; anything else is dropped and counted.
    package static let virtualKeys: [UInt16: UInt16] = [
        // Letters, 0x04…0x1D = A…Z
        0x04: 0, 0x05: 11, 0x06: 8, 0x07: 2, 0x08: 14, 0x09: 3, 0x0A: 5, 0x0B: 4, 0x0C: 34,
        0x0D: 38, 0x0E: 40, 0x0F: 37, 0x10: 46, 0x11: 45, 0x12: 31, 0x13: 35, 0x14: 12,
        0x15: 15, 0x16: 1, 0x17: 17, 0x18: 32, 0x19: 9, 0x1A: 13, 0x1B: 7, 0x1C: 16, 0x1D: 6,
        // Digits, 0x1E…0x27 = 1…9 then 0
        0x1E: 18, 0x1F: 19, 0x20: 20, 0x21: 21, 0x22: 23, 0x23: 22, 0x24: 26, 0x25: 28,
        0x26: 25, 0x27: 29,
        // Editing and punctuation
        0x28: 36,   // Return
        0x29: 53,   // Escape
        0x2A: 51,   // Delete (backspace)
        0x2B: 48,   // Tab
        0x2C: 49,   // Space
        0x2D: 27,   // -
        0x2E: 24,   // =
        0x2F: 33,   // [
        0x30: 30,   // ]
        0x31: 42,   // \
        0x33: 41,   // ;
        0x34: 39,   // '
        0x35: 50,   // `
        0x36: 43,   // ,
        0x37: 47,   // .
        0x38: 44,   // /
        0x39: 57,   // Caps Lock
        // F1…F12
        0x3A: 122, 0x3B: 120, 0x3C: 99, 0x3D: 118, 0x3E: 96, 0x3F: 97,
        0x40: 98, 0x41: 100, 0x42: 101, 0x43: 109, 0x44: 103, 0x45: 111,
        // Navigation
        0x4A: 115,  // Home
        0x4B: 116,  // Page Up
        0x4C: 117,  // Forward Delete
        0x4D: 119,  // End
        0x4E: 121,  // Page Down
        0x4F: 124,  // Right
        0x50: 123,  // Left
        0x51: 125,  // Down
        0x52: 126,  // Up
        // Modifiers, in case the client sends them as keys as well as flags
        0xE0: 59,   // Left Control
        0xE1: 56,   // Left Shift
        0xE2: 58,   // Left Option
        0xE3: 55,   // Left Command
        0xE4: 62,   // Right Control
        0xE5: 60,   // Right Shift
        0xE6: 61,   // Right Option
        0xE7: 54,   // Right Command
    ]
}
