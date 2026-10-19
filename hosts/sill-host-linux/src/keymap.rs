//! A device's key (a USB HID usage, page 7) as a Linux key: its evdev code (linux/input-event-codes.h),
//! whose X keycode on every evdev-based server (Xorg with libinput or evdev, XWayland, Xvfb with its
//! default "evdev" rules) is the code + 8, and the keysym it carries on a US layout, used only when a
//! server's keymap turns out not to be evdev's (`keysym`).
//!
//! The usages are physical positions, as a hardware keyboard's: the host's own layout gives them their
//! characters (a German layout types "z" for the US "y" key), as a USB keyboard plugged into it would.
//! Covers every usage the Mac host maps (KeyStrokes.swift `virtualKeys`) and a few a PC has besides
//! (Insert, Print Screen, Scroll Lock, Pause, the ISO key, Menu).
//!
//! Modifiers (README.md): ⌘ and ⌃ both become Control, ⌥ Alt, ⇧ Shift. Right Option is Left Alt's key:
//! on many layouts the right Alt key is AltGr (ISO_Level3_Shift), which is not what ⌥ means.
//!
//! Pure: no X, compiled and tested on every platform.

/// The modifier keys a device's bits stand for, as X sees them.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub enum Modifier {
    Control,
    Shift,
    Alt,
}

impl Modifier {
    pub const ALL: [Modifier; 3] = [Modifier::Control, Modifier::Shift, Modifier::Alt];

    /// The evdev code of the left-hand key that holds this modifier.
    pub fn evdev(self) -> u16 {
        match self {
            Modifier::Control => 29, // KEY_LEFTCTRL
            Modifier::Shift => 42,   // KEY_LEFTSHIFT
            Modifier::Alt => 56,     // KEY_LEFTALT
        }
    }

    /// Its keysym on any layout (Control_L, Shift_L, Alt_L).
    pub fn keysym(self) -> u32 {
        match self {
            Modifier::Control => 0xffe3,
            Modifier::Shift => 0xffe1,
            Modifier::Alt => 0xffe9,
        }
    }
}

/// The protocol's modifier bits (UIKeyModifierFlags): shift 1<<17, control 1<<18, option 1<<19,
/// command 1<<20 (caps lock 1<<16 is a key's state, not a modifier to hold, and is ignored).
pub const SHIFT_BIT: u64 = 1 << 17;
pub const CONTROL_BIT: u64 = 1 << 18;
pub const OPTION_BIT: u64 = 1 << 19;
pub const COMMAND_BIT: u64 = 1 << 20;

/// The modifiers a device's bits ask for, each once (⌘ and ⌃ are both Control).
pub fn modifiers(bits: u64) -> Vec<Modifier> {
    let mut out = Vec::new();
    if bits & (CONTROL_BIT | COMMAND_BIT) != 0 {
        out.push(Modifier::Control);
    }
    if bits & SHIFT_BIT != 0 {
        out.push(Modifier::Shift);
    }
    if bits & OPTION_BIT != 0 {
        out.push(Modifier::Alt);
    }
    out
}

/// The modifier a usage's own key holds (0xE0–0xE7), or None for any other key.
pub fn modifier_of(usage: u16) -> Option<Modifier> {
    match usage {
        0xE0 | 0xE3 | 0xE4 | 0xE7 => Some(Modifier::Control), // ⌃ and ⌘, both sides
        0xE1 | 0xE5 => Some(Modifier::Shift),
        0xE2 | 0xE6 => Some(Modifier::Alt),
        _ => None,
    }
}

/// The evdev code for a HID usage, or None for a usage no PC key answers to (dropped and counted).
pub fn evdev(usage: u16) -> Option<u16> {
    Some(match usage {
        // Letters, 0x04…0x1D = A…Z
        0x04 => 30, 0x05 => 48, 0x06 => 46, 0x07 => 32, 0x08 => 18, 0x09 => 33, 0x0A => 34,
        0x0B => 35, 0x0C => 23, 0x0D => 36, 0x0E => 37, 0x0F => 38, 0x10 => 50, 0x11 => 49,
        0x12 => 24, 0x13 => 25, 0x14 => 16, 0x15 => 19, 0x16 => 31, 0x17 => 20, 0x18 => 22,
        0x19 => 47, 0x1A => 17, 0x1B => 45, 0x1C => 21, 0x1D => 44,
        // Digits, 0x1E…0x27 = 1…9 then 0
        0x1E => 2, 0x1F => 3, 0x20 => 4, 0x21 => 5, 0x22 => 6, 0x23 => 7, 0x24 => 8, 0x25 => 9,
        0x26 => 10, 0x27 => 11,
        // Editing and punctuation
        0x28 => 28, // Return
        0x29 => 1,  // Escape
        0x2A => 14, // Backspace (the Mac's Delete)
        0x2B => 15, // Tab
        0x2C => 57, // Space
        0x2D => 12, // -
        0x2E => 13, // =
        0x2F => 26, // [
        0x30 => 27, // ]
        0x31 => 43, // \
        0x32 => 43, // non-US # (the same key on ISO boards)
        0x33 => 39, // ;
        0x34 => 40, // '
        0x35 => 41, // `
        0x36 => 51, // ,
        0x37 => 52, // .
        0x38 => 53, // /
        0x39 => 58, // Caps Lock
        // F1…F12
        0x3A => 59, 0x3B => 60, 0x3C => 61, 0x3D => 62, 0x3E => 63, 0x3F => 64,
        0x40 => 65, 0x41 => 66, 0x42 => 67, 0x43 => 68, 0x44 => 87, 0x45 => 88,
        // A PC's extra keys
        0x46 => 99,  // Print Screen (KEY_SYSRQ)
        0x47 => 70,  // Scroll Lock
        0x48 => 119, // Pause
        0x49 => 110, // Insert
        // Navigation
        0x4A => 102, // Home
        0x4B => 104, // Page Up
        0x4C => 111, // Forward Delete
        0x4D => 107, // End
        0x4E => 109, // Page Down
        0x4F => 106, // Right
        0x50 => 105, // Left
        0x51 => 108, // Down
        0x52 => 103, // Up
        0x64 => 86,  // the ISO key beside left Shift (KEY_102ND)
        0x65 => 127, // Menu (KEY_COMPOSE)
        // Modifiers: ⌃ and ⌘ are Control, ⌥ Alt, ⇧ Shift
        0xE0 => 29, // Left Control
        0xE1 => 42, // Left Shift
        0xE2 => 56, // Left Option → Left Alt
        0xE3 => 29, // Left Command → Left Control
        0xE4 => 97, // Right Control
        0xE5 => 54, // Right Shift
        0xE6 => 56, // Right Option → Left Alt (never AltGr)
        0xE7 => 97, // Right Command → Right Control
        _ => return None,
    })
}

/// The X keycode on an evdev keymap.
pub fn x_keycode(usage: u16) -> Option<u8> {
    evdev(usage).map(|code| (code + 8) as u8)
}

/// The keysym a usage carries on a US layout (unshifted), for servers whose keymap is not evdev's:
/// the key is then found by its keysym.
pub fn keysym(usage: u16) -> Option<u32> {
    Some(match usage {
        0x04..=0x1D => 0x61 + (usage - 0x04) as u32, // a…z
        0x1E..=0x26 => 0x31 + (usage - 0x1E) as u32, // 1…9
        0x27 => 0x30,                                // 0
        0x28 => 0xff0d,                              // Return
        0x29 => 0xff1b,                              // Escape
        0x2A => 0xff08,                              // BackSpace
        0x2B => 0xff09,                              // Tab
        0x2C => 0x20,                                // space
        0x2D => 0x2d,
        0x2E => 0x3d,
        0x2F => 0x5b,
        0x30 => 0x5d,
        0x31 | 0x32 => 0x5c,
        0x33 => 0x3b,
        0x34 => 0x27,
        0x35 => 0x60,
        0x36 => 0x2c,
        0x37 => 0x2e,
        0x38 => 0x2f,
        0x39 => 0xffe5,                                 // Caps_Lock
        0x3A..=0x45 => 0xffbe + (usage - 0x3A) as u32, // F1…F12
        0x46 => 0xff61,                                 // Print
        0x47 => 0xff14,                                 // Scroll_Lock
        0x48 => 0xff13,                                 // Pause
        0x49 => 0xff63,                                 // Insert
        0x4A => 0xff50,                                 // Home
        0x4B => 0xff55,                                 // Prior
        0x4C => 0xffff,                                 // Delete
        0x4D => 0xff57,                                 // End
        0x4E => 0xff56,                                 // Next
        0x4F => 0xff53,                                 // Right
        0x50 => 0xff51,                                 // Left
        0x51 => 0xff54,                                 // Down
        0x52 => 0xff52,                                 // Up
        0x64 => 0x3c,                                   // less
        0x65 => 0xff67,                                 // Menu
        0xE0 | 0xE3 => 0xffe3,                          // Control_L
        0xE1 => 0xffe1,                                 // Shift_L
        0xE2 | 0xE6 => 0xffe9,                          // Alt_L
        0xE4 | 0xE7 => 0xffe4,                          // Control_R
        0xE5 => 0xffe2,                                 // Shift_R
        _ => return None,
    })
}

/// Every usage this table maps, for the self-test and the tests.
pub fn all_usages() -> impl Iterator<Item = u16> {
    (0u16..=0xFF).filter(|u| evdev(*u).is_some())
}

/// Keys whose keysym tells an evdev keymap from an older one (the xfree86 "kbd" map moved the arrows
/// and the navigation block): the X keycode on evdev and the keysym it must carry there.
pub const EVDEV_WITNESSES: [(u8, u32); 6] = [
    (38, 0x61),     // a
    (36, 0xff0d),   // Return
    (111, 0xff52),  // Up
    (113, 0xff51),  // Left
    (119, 0xffff),  // Delete
    (67, 0xffbe),   // F1
];

#[cfg(test)]
mod tests {
    use super::*;

    /// The usages KeyStrokes.swift's `virtualKeys` maps on the Mac: every one has a PC key.
    const MAC_USAGES: &[u16] = &[
        0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10, 0x11, 0x12,
        0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F, 0x20, 0x21,
        0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28, 0x29, 0x2A, 0x2B, 0x2C, 0x2D, 0x2E, 0x2F, 0x30,
        0x31, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3A, 0x3B, 0x3C, 0x3D, 0x3E, 0x3F, 0x40,
        0x41, 0x42, 0x43, 0x44, 0x45, 0x4A, 0x4B, 0x4C, 0x4D, 0x4E, 0x4F, 0x50, 0x51, 0x52, 0xE0,
        0xE1, 0xE2, 0xE3, 0xE4, 0xE5, 0xE6, 0xE7,
    ];

    #[test]
    fn every_mac_usage_has_a_key_and_a_keysym() {
        assert_eq!(MAC_USAGES.len(), 82);
        for &u in MAC_USAGES {
            assert!(evdev(u).is_some(), "usage {u:#x} has no evdev code");
            assert!(keysym(u).is_some(), "usage {u:#x} has no keysym");
        }
    }

    #[test]
    fn letters_and_digits_land_where_a_us_keyboard_has_them() {
        // X keycodes on an evdev map (xmodmap -pke on any modern desktop).
        assert_eq!(x_keycode(0x04), Some(38)); // a
        assert_eq!(x_keycode(0x1D), Some(52)); // z
        assert_eq!(x_keycode(0x14), Some(24)); // q
        assert_eq!(x_keycode(0x1E), Some(10)); // 1
        assert_eq!(x_keycode(0x27), Some(19)); // 0
        assert_eq!(x_keycode(0x28), Some(36)); // Return
        assert_eq!(x_keycode(0x2C), Some(65)); // space
        assert_eq!(x_keycode(0x52), Some(111)); // Up
        assert_eq!(x_keycode(0x50), Some(113)); // Left
        assert_eq!(x_keycode(0x4C), Some(119)); // Delete
        assert_eq!(x_keycode(0x3A), Some(67)); // F1
        assert_eq!(x_keycode(0x45), Some(96)); // F12
        // The letter table is a permutation: 26 distinct keys.
        let mut letters: Vec<u16> = (0x04..=0x1D).map(|u| evdev(u).unwrap()).collect();
        letters.sort();
        letters.dedup();
        assert_eq!(letters.len(), 26);
    }

    #[test]
    fn witnesses_agree_with_the_table() {
        for (keycode, sym) in EVDEV_WITNESSES {
            let usage = all_usages().find(|u| x_keycode(*u) == Some(keycode)).unwrap();
            assert_eq!(keysym(usage), Some(sym), "keycode {keycode}");
        }
    }

    #[test]
    fn command_and_control_are_control_option_is_alt() {
        assert_eq!(modifiers(COMMAND_BIT), vec![Modifier::Control]);
        assert_eq!(modifiers(CONTROL_BIT | COMMAND_BIT), vec![Modifier::Control]);
        assert_eq!(modifiers(OPTION_BIT | SHIFT_BIT), vec![Modifier::Shift, Modifier::Alt]);
        assert_eq!(modifiers(1 << 16), vec![]); // caps lock alone holds nothing
        assert_eq!(evdev(0xE3), evdev(0xE0));
        assert_eq!(evdev(0xE6), Some(Modifier::Alt.evdev()));
        for u in 0xE0..=0xE7 {
            assert_eq!(evdev(u).map(|c| c == modifier_of(u).unwrap().evdev() || c == 97 || c == 54), Some(true));
        }
    }
}
