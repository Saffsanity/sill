//! USB HID usages (page 7, what the devices send in kind 8's `.key`) as the PC's keys: Set 1
//! scancodes, the "make" codes SendInput takes with KEYEVENTF_SCANCODE, and whether the key is one
//! of the extended ones (an E0 prefix on the wire, KEYEVENTF_EXTENDEDKEY for SendInput).
//!
//! Every usage the Mac host maps (Sources/SillHost/KeyStrokes.swift, `virtualKeys`) is here, plus
//! the PC keys a hardware keyboard on an iPad can also send (Insert, the keypad, the non-US keys,
//! the Application key, Print Screen, Scroll Lock, F13–F24). Pure: no OS calls, tested on any
//! machine.
//!
//! Scancodes are layout independent: the PC's own keyboard layout turns them into characters, as
//! it does for its own keyboard. So a device's key reaches the PC as the key in that place on a
//! US keyboard (A is the key right of Caps Lock), which is what a hardware keyboard on a PC does.

/// One key of a PC keyboard: its Set 1 make code and whether it is an extended (E0) key.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct ScanKey {
    pub code: u8,
    pub extended: bool,
}

impl ScanKey {
    pub const fn new(code: u8) -> Self {
        ScanKey { code, extended: false }
    }
    pub const fn ext(code: u8) -> Self {
        ScanKey { code, extended: true }
    }
}

/// The PC's modifier keys a device's modifiers become (README.md: ⌘ and ⌃ both Ctrl, ⌥ Alt,
/// ⇧ Shift).
pub const LEFT_CTRL: ScanKey = ScanKey::new(0x1D);
pub const RIGHT_CTRL: ScanKey = ScanKey::ext(0x1D);
pub const LEFT_SHIFT: ScanKey = ScanKey::new(0x2A);
pub const RIGHT_SHIFT: ScanKey = ScanKey::new(0x36);
pub const LEFT_ALT: ScanKey = ScanKey::new(0x38);

/// Return, Tab and Backspace, which typed text sends as keys ("\n", "\t", "\u{8}").
pub const RETURN: ScanKey = ScanKey::new(0x1C);
pub const TAB: ScanKey = ScanKey::new(0x0F);
pub const BACKSPACE: ScanKey = ScanKey::new(0x0E);

/// The modifier class a key belongs to (what its press holds), used to decide whether a chord
/// still needs its modifier pressed.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum Modifier {
    Ctrl,
    Shift,
    Alt,
}

impl Modifier {
    /// The key Sill presses for a chord that carries this modifier but whose device holds no key
    /// of it.
    pub fn chord_key(self) -> ScanKey {
        match self {
            Modifier::Ctrl => LEFT_CTRL,
            Modifier::Shift => LEFT_SHIFT,
            Modifier::Alt => LEFT_ALT,
        }
    }
}

/// The class of a PC key, if it is a modifier.
pub fn modifier_of(key: ScanKey) -> Option<Modifier> {
    match key {
        LEFT_CTRL | RIGHT_CTRL => Some(Modifier::Ctrl),
        LEFT_SHIFT | RIGHT_SHIFT => Some(Modifier::Shift),
        LEFT_ALT => Some(Modifier::Alt),
        k if k == ScanKey::ext(0x38) => Some(Modifier::Alt),
        _ => None,
    }
}

/// The protocol's modifier bits (UIKeyModifierFlags, platform.rs's `Input::Key`).
pub const FLAG_SHIFT: u64 = 1 << 17;
pub const FLAG_CONTROL: u64 = 1 << 18;
pub const FLAG_OPTION: u64 = 1 << 19;
pub const FLAG_COMMAND: u64 = 1 << 20;

/// The PC modifiers a device's flags ask for: ⌘ and ⌃ are Ctrl, ⌥ Alt, ⇧ Shift. Caps Lock (1<<16)
/// and the iOS-only bits are ignored: Caps Lock is a key with its own state on a PC.
pub fn modifiers_from_flags(flags: u64) -> Vec<Modifier> {
    let mut out = Vec::new();
    if flags & (FLAG_CONTROL | FLAG_COMMAND) != 0 {
        out.push(Modifier::Ctrl);
    }
    if flags & FLAG_SHIFT != 0 {
        out.push(Modifier::Shift);
    }
    if flags & FLAG_OPTION != 0 {
        out.push(Modifier::Alt);
    }
    out
}

/// Whether a HID usage is one of the modifiers' own keys (0xE0–0xE7).
pub fn is_modifier_usage(usage: u16) -> bool {
    (0xE0..=0xE7).contains(&usage)
}

/// HID usage → PC key. None for a usage no PC key answers to (the caller drops it).
pub fn scan_key(usage: u16) -> Option<ScanKey> {
    let n = ScanKey::new;
    let e = ScanKey::ext;
    Some(match usage {
        // Letters A…Z (0x04…0x1D)
        0x04 => n(0x1E), // A
        0x05 => n(0x30), // B
        0x06 => n(0x2E), // C
        0x07 => n(0x20), // D
        0x08 => n(0x12), // E
        0x09 => n(0x21), // F
        0x0A => n(0x22), // G
        0x0B => n(0x23), // H
        0x0C => n(0x17), // I
        0x0D => n(0x24), // J
        0x0E => n(0x25), // K
        0x0F => n(0x26), // L
        0x10 => n(0x32), // M
        0x11 => n(0x31), // N
        0x12 => n(0x18), // O
        0x13 => n(0x19), // P
        0x14 => n(0x10), // Q
        0x15 => n(0x13), // R
        0x16 => n(0x1F), // S
        0x17 => n(0x14), // T
        0x18 => n(0x16), // U
        0x19 => n(0x2F), // V
        0x1A => n(0x11), // W
        0x1B => n(0x2D), // X
        0x1C => n(0x15), // Y
        0x1D => n(0x2C), // Z
        // Digits 1…9, 0 (0x1E…0x27)
        0x1E..=0x26 => n((usage - 0x1E + 0x02) as u8),
        0x27 => n(0x0B),
        // Editing and punctuation
        0x28 => RETURN,    // Return
        0x29 => n(0x01),   // Escape
        0x2A => BACKSPACE, // Delete (backspace)
        0x2B => TAB,       // Tab
        0x2C => n(0x39),   // Space
        0x2D => n(0x0C),   // -
        0x2E => n(0x0D),   // =
        0x2F => n(0x1A),   // [
        0x30 => n(0x1B),   // ]
        0x31 => n(0x2B),   // \
        0x32 => n(0x2B),   // Non-US # (the same key position on ISO boards)
        0x33 => n(0x27),   // ;
        0x34 => n(0x28),   // '
        0x35 => n(0x29),   // `
        0x36 => n(0x33),   // ,
        0x37 => n(0x34),   // .
        0x38 => n(0x35),   // /
        0x39 => n(0x3A),   // Caps Lock
        // F1…F10, F11, F12
        0x3A..=0x43 => n((usage - 0x3A + 0x3B) as u8),
        0x44 => n(0x57),
        0x45 => n(0x58),
        // Print Screen, Scroll Lock (Pause needs a sequence of its own: left out)
        0x46 => e(0x37),
        0x47 => n(0x46),
        // Navigation
        0x49 => e(0x52), // Insert
        0x4A => e(0x47), // Home
        0x4B => e(0x49), // Page Up
        0x4C => e(0x53), // Forward Delete
        0x4D => e(0x4F), // End
        0x4E => e(0x51), // Page Down
        0x4F => e(0x4D), // Right
        0x50 => e(0x4B), // Left
        0x51 => e(0x50), // Down
        0x52 => e(0x48), // Up
        // Keypad
        0x53 => e(0x45), // Num Lock (a plain 0x45 is Pause)
        0x54 => e(0x35), // /
        0x55 => n(0x37), // *
        0x56 => n(0x4A), // -
        0x57 => n(0x4E), // +
        0x58 => e(0x1C), // Enter
        0x59 => n(0x4F), // 1
        0x5A => n(0x50), // 2
        0x5B => n(0x51), // 3
        0x5C => n(0x4B), // 4
        0x5D => n(0x4C), // 5
        0x5E => n(0x4D), // 6
        0x5F => n(0x47), // 7
        0x60 => n(0x48), // 8
        0x61 => n(0x49), // 9
        0x62 => n(0x52), // 0
        0x63 => n(0x53), // .
        0x64 => n(0x56), // Non-US \ (ISO, left of Z)
        0x65 => e(0x5D), // Application (context menu)
        0x67 => n(0x59), // Keypad =
        // F13…F24
        0x68..=0x6E => n((usage - 0x68 + 0x64) as u8), // F13–F19: 0x64–0x6A
        0x6F => n(0x6B),                               // F20
        0x70 => n(0x6C),                               // F21
        0x71 => n(0x6D),                               // F22
        0x72 => n(0x6E),                               // F23
        0x73 => n(0x76),                               // F24
        // Modifiers, when a device sends them as keys as well as flags: ⌘ and ⌃ are Ctrl, ⌥ Alt
        // (both sides the left Alt: the right one is AltGr on many layouts), ⇧ Shift.
        0xE0 => LEFT_CTRL,   // Left Control
        0xE1 => LEFT_SHIFT,  // Left Shift
        0xE2 => LEFT_ALT,    // Left Option
        0xE3 => LEFT_CTRL,   // Left Command
        0xE4 => RIGHT_CTRL,  // Right Control
        0xE5 => RIGHT_SHIFT, // Right Shift
        0xE6 => LEFT_ALT,    // Right Option
        0xE7 => RIGHT_CTRL,  // Right Command
        _ => return None,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Every usage KeyStrokes.swift's `virtualKeys` maps (the Mac host's table), so the PC answers
    /// to every key the Mac does.
    const MAC_USAGES: &[u16] = &[
        0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10, 0x11, 0x12, 0x13, 0x14,
        0x15, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F, 0x20, 0x21, 0x22, 0x23, 0x24, 0x25,
        0x26, 0x27, 0x28, 0x29, 0x2A, 0x2B, 0x2C, 0x2D, 0x2E, 0x2F, 0x30, 0x31, 0x33, 0x34, 0x35, 0x36, 0x37,
        0x38, 0x39, 0x3A, 0x3B, 0x3C, 0x3D, 0x3E, 0x3F, 0x40, 0x41, 0x42, 0x43, 0x44, 0x45, 0x4A, 0x4B, 0x4C,
        0x4D, 0x4E, 0x4F, 0x50, 0x51, 0x52, 0xE0, 0xE1, 0xE2, 0xE3, 0xE4, 0xE5, 0xE6, 0xE7,
    ];

    #[test]
    fn covers_every_usage_the_mac_maps() {
        assert_eq!(MAC_USAGES.len(), 82);
        for &u in MAC_USAGES {
            assert!(scan_key(u).is_some(), "usage {u:#04x} has no PC key");
        }
    }

    #[test]
    fn known_keys() {
        assert_eq!(scan_key(0x04), Some(ScanKey::new(0x1E))); // A
        assert_eq!(scan_key(0x1D), Some(ScanKey::new(0x2C))); // Z
        assert_eq!(scan_key(0x1E), Some(ScanKey::new(0x02))); // 1
        assert_eq!(scan_key(0x26), Some(ScanKey::new(0x0A))); // 9
        assert_eq!(scan_key(0x27), Some(ScanKey::new(0x0B))); // 0
        assert_eq!(scan_key(0x3A), Some(ScanKey::new(0x3B))); // F1
        assert_eq!(scan_key(0x43), Some(ScanKey::new(0x44))); // F10
        assert_eq!(scan_key(0x44), Some(ScanKey::new(0x57))); // F11
        assert_eq!(scan_key(0x45), Some(ScanKey::new(0x58))); // F12
        assert_eq!(scan_key(0x4F), Some(ScanKey::ext(0x4D))); // Right
        assert_eq!(scan_key(0x52), Some(ScanKey::ext(0x48))); // Up
        assert_eq!(scan_key(0x4C), Some(ScanKey::ext(0x53))); // Forward Delete
        assert_eq!(scan_key(0x68), Some(ScanKey::new(0x64))); // F13
        assert_eq!(scan_key(0x6E), Some(ScanKey::new(0x6A))); // F19
        assert_eq!(scan_key(0x73), Some(ScanKey::new(0x76))); // F24
        assert_eq!(scan_key(0x00), None);
        assert_eq!(scan_key(0x48), None); // Pause: a sequence, not one key
        assert_eq!(scan_key(0xE8), None);
    }

    #[test]
    fn letters_and_digits_are_distinct() {
        let mut seen = std::collections::HashSet::new();
        for u in 0x04..=0x27u16 {
            assert!(seen.insert(scan_key(u).unwrap()), "usage {u:#04x} repeats a key");
        }
    }

    #[test]
    fn navigation_keys_are_extended_and_the_main_block_is_not() {
        for u in [0x49u16, 0x4A, 0x4B, 0x4C, 0x4D, 0x4E, 0x4F, 0x50, 0x51, 0x52, 0x54, 0x58, 0x65] {
            assert!(scan_key(u).unwrap().extended, "usage {u:#04x} should be extended");
        }
        for u in (0x04..=0x45u16).filter(|&u| u != 0x46) {
            if let Some(k) = scan_key(u) {
                assert!(!k.extended, "usage {u:#04x} should not be extended");
            }
        }
    }

    #[test]
    fn modifiers_follow_the_policy() {
        // ⌘ and ⌃ are Ctrl, ⌥ Alt, ⇧ Shift.
        assert_eq!(modifier_of(scan_key(0xE3).unwrap()), Some(Modifier::Ctrl));
        assert_eq!(modifier_of(scan_key(0xE7).unwrap()), Some(Modifier::Ctrl));
        assert_eq!(modifier_of(scan_key(0xE0).unwrap()), Some(Modifier::Ctrl));
        assert_eq!(modifier_of(scan_key(0xE4).unwrap()), Some(Modifier::Ctrl));
        assert_eq!(modifier_of(scan_key(0xE2).unwrap()), Some(Modifier::Alt));
        assert_eq!(modifier_of(scan_key(0xE6).unwrap()), Some(Modifier::Alt));
        assert_eq!(modifier_of(scan_key(0xE1).unwrap()), Some(Modifier::Shift));
        assert_eq!(modifier_of(scan_key(0xE5).unwrap()), Some(Modifier::Shift));
        assert_eq!(modifier_of(scan_key(0x04).unwrap()), None);
        assert_eq!(modifiers_from_flags(FLAG_COMMAND), vec![Modifier::Ctrl]);
        assert_eq!(modifiers_from_flags(FLAG_CONTROL | FLAG_COMMAND), vec![Modifier::Ctrl]);
        assert_eq!(
            modifiers_from_flags(FLAG_SHIFT | FLAG_OPTION | FLAG_COMMAND),
            vec![Modifier::Ctrl, Modifier::Shift, Modifier::Alt]
        );
        assert_eq!(modifiers_from_flags(1 << 16), vec![]); // Caps Lock's flag
        for u in 0xE0..=0xE7u16 {
            assert!(is_modifier_usage(u));
            assert!(modifier_of(scan_key(u).unwrap()).is_some());
        }
        assert!(!is_modifier_usage(0x39));
    }
}
