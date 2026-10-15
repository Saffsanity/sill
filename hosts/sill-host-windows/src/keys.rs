//! A device's keys as the PC keyboard events to post, and which keys are down because of Sill.
//!
//! The Mac's KeyStrokes (Sources/SillHost/KeyStrokes.swift) is the reference. A device sends a
//! shortcut either as one key carrying its modifier flags (an older device's ⌘C: C down and up,
//! each with command) or with the modifier's own key pressed around it (newer devices, a hardware
//! keyboard). A PC has no per-event flags: a modifier is a key that is down or up. So:
//!   - a key's down presses first the PC modifiers its flags ask for that no key down holds
//!     ("chord" modifiers, the left Ctrl, Alt or Shift), then the key;
//!   - a key's up lets go of the key, and once no key other than modifiers is down, of the chord
//!     modifiers too, so ⌘C leaves no Ctrl down for the next click;
//!   - a modifier's own key is pressed and released as itself (⌘ and ⌃ both the PC's Ctrl, so a PC
//!     key two device keys hold stays down until both are up);
//!   - a key or text whose flags no longer carry a modifier first lets go of that modifier's keys
//!     (a device from before KeyStrokes never sent a hardware ⌘'s release);
//!   - text lets go of every modifier first (it is typed as Unicode, with no modifier);
//!   - the host's end, and a device asking for it, lets go of everything down.
//!
//! Pure: no OS calls. The Windows injector posts what this returns, in order.

use std::collections::{BTreeMap, BTreeSet};

use crate::keymap::{self, Modifier, ScanKey};

/// One keyboard event to post.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum KeyOp {
    /// A key by scancode.
    Key { key: ScanKey, down: bool },
    /// One UTF-16 code unit of typed text (SendInput's KEYEVENTF_UNICODE).
    Unicode { unit: u16, down: bool },
}

/// Who holds a PC key down.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
enum Holder {
    /// A device's key (its HID usage) whose down went out and whose up has not.
    Usage(u16),
    /// A chord's modifier, pressed for a key that carried it in its flags.
    Chord,
}

#[derive(Default, Debug)]
pub struct KeyTracker {
    /// Each PC key down because of Sill, with what holds it.
    pressed: BTreeMap<ScanKey, BTreeSet<Holder>>,
    /// Device keys (not modifiers) whose down went out and whose up has not.
    keys_down: BTreeSet<u16>,
    /// Device modifier keys (0xE0–0xE7) down.
    modifiers_down: BTreeSet<u16>,
}

impl KeyTracker {
    pub fn new() -> Self {
        Self::default()
    }

    /// Whether anything is down because of Sill.
    #[cfg(test)]
    pub fn is_idle(&self) -> bool {
        self.pressed.is_empty()
    }

    /// Whether a PC modifier of this class is down because of Sill.
    pub fn holds(&self, modifier: Modifier) -> bool {
        self.pressed.keys().any(|k| keymap::modifier_of(*k) == Some(modifier))
    }

    /// A device's key: the events to post, or None for a usage no PC key answers to (nothing
    /// changes; the caller drops it).
    pub fn key(&mut self, usage: u16, down: bool, flags: u64) -> Option<Vec<KeyOp>> {
        let key = keymap::scan_key(usage)?;
        let wanted = keymap::modifiers_from_flags(flags);
        let mut ops = Vec::new();
        self.let_go_unwanted(&wanted, Some(usage), &mut ops);

        if keymap::is_modifier_usage(usage) {
            if down {
                self.modifiers_down.insert(usage);
                self.hold(key, Holder::Usage(usage), &mut ops);
            } else {
                self.modifiers_down.remove(&usage);
                self.release(key, Holder::Usage(usage), &mut ops);
            }
            return Some(ops);
        }

        if down {
            for m in &wanted {
                if !self.holds(*m) {
                    self.hold(m.chord_key(), Holder::Chord, &mut ops);
                }
            }
            self.keys_down.insert(usage);
            // A repeat (the key already down) is a down again, as a held key auto-repeats.
            ops.push(KeyOp::Key { key, down: true });
            self.pressed.entry(key).or_default().insert(Holder::Usage(usage));
        } else {
            self.keys_down.remove(&usage);
            if let Some(holders) = self.pressed.get_mut(&key) {
                holders.remove(&Holder::Usage(usage));
                if holders.is_empty() {
                    self.pressed.remove(&key);
                }
            }
            // The up goes out whether or not its down did (a lost down still leaves no key down).
            ops.push(KeyOp::Key { key, down: false });
            if self.keys_down.is_empty() {
                self.release_chords(&mut ops);
            }
        }
        Some(ops)
    }

    /// Typed text: let go of every modifier first, then type it. "\n" (and "\r", "\r\n") is
    /// Return, "\t" Tab, "\u{8}" Backspace, each a key tap; everything else Unicode.
    pub fn text(&mut self, text: &str) -> Vec<KeyOp> {
        let mut ops = Vec::new();
        self.let_go_unwanted(&[], None, &mut ops);
        let mut chars = text.chars().peekable();
        while let Some(c) = chars.next() {
            let tap = match c {
                '\r' => {
                    if chars.peek() == Some(&'\n') {
                        chars.next();
                    }
                    Some(keymap::RETURN)
                }
                '\n' => Some(keymap::RETURN),
                '\t' => Some(keymap::TAB),
                '\u{8}' => Some(keymap::BACKSPACE),
                _ => None,
            };
            if let Some(key) = tap {
                ops.push(KeyOp::Key { key, down: true });
                ops.push(KeyOp::Key { key, down: false });
                continue;
            }
            let mut buf = [0u16; 2];
            for &unit in c.encode_utf16(&mut buf).iter() {
                ops.push(KeyOp::Unicode { unit, down: true });
                ops.push(KeyOp::Unicode { unit, down: false });
            }
        }
        ops
    }

    /// The ups of every key down because of Sill: other keys first, then the modifiers, so no
    /// modifier outlives Sill on the PC.
    pub fn release_all(&mut self) -> Vec<KeyOp> {
        let mut ops = Vec::new();
        let keys: Vec<ScanKey> = self.pressed.keys().copied().collect();
        for key in keys.iter().filter(|k| keymap::modifier_of(**k).is_none()) {
            ops.push(KeyOp::Key { key: *key, down: false });
        }
        for key in keys.iter().filter(|k| keymap::modifier_of(**k).is_some()) {
            ops.push(KeyOp::Key { key: *key, down: false });
        }
        self.pressed.clear();
        self.keys_down.clear();
        self.modifiers_down.clear();
        ops
    }

    /// Lets go of the device's modifier keys and chord modifiers whose class `wanted` lacks
    /// (`except`, the key being handled, left alone).
    fn let_go_unwanted(&mut self, wanted: &[Modifier], except: Option<u16>, ops: &mut Vec<KeyOp>) {
        let stale: Vec<u16> = self
            .modifiers_down
            .iter()
            .rev()
            .copied()
            .filter(|u| Some(*u) != except)
            .filter(|u| {
                let class = keymap::scan_key(*u).and_then(keymap::modifier_of);
                class.is_some_and(|c| !wanted.contains(&c))
            })
            .collect();
        for usage in stale {
            self.modifiers_down.remove(&usage);
            if let Some(key) = keymap::scan_key(usage) {
                self.release(key, Holder::Usage(usage), ops);
            }
        }
        let chords: Vec<ScanKey> = self
            .pressed
            .iter()
            .filter(|(k, holders)| {
                holders.contains(&Holder::Chord)
                    && keymap::modifier_of(**k).is_some_and(|c| !wanted.contains(&c))
            })
            .map(|(k, _)| *k)
            .collect();
        for key in chords {
            self.release(key, Holder::Chord, ops);
        }
    }

    fn release_chords(&mut self, ops: &mut Vec<KeyOp>) {
        let chords: Vec<ScanKey> = self
            .pressed
            .iter()
            .filter(|(_, holders)| holders.contains(&Holder::Chord))
            .map(|(k, _)| *k)
            .collect();
        for key in chords {
            self.release(key, Holder::Chord, ops);
        }
    }

    /// `holder` holds `key`; its down goes out if nothing held it before.
    fn hold(&mut self, key: ScanKey, holder: Holder, ops: &mut Vec<KeyOp>) {
        let holders = self.pressed.entry(key).or_default();
        let was_up = holders.is_empty();
        holders.insert(holder);
        if was_up {
            ops.push(KeyOp::Key { key, down: true });
        }
    }

    /// `holder` lets go of `key`; its up goes out once nothing holds it.
    fn release(&mut self, key: ScanKey, holder: Holder, ops: &mut Vec<KeyOp>) {
        let Some(holders) = self.pressed.get_mut(&key) else { return };
        holders.remove(&holder);
        if holders.is_empty() {
            self.pressed.remove(&key);
            ops.push(KeyOp::Key { key, down: false });
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::keymap::*;

    const C: u16 = 0x06;
    const V: u16 = 0x19;
    const SPACE: u16 = 0x2C;
    const L_CMD: u16 = 0xE3;
    const L_CTRL: u16 = 0xE0;
    const L_SHIFT: u16 = 0xE1;
    const L_OPT: u16 = 0xE2;
    const R_CMD: u16 = 0xE7;

    fn d(key: ScanKey) -> KeyOp {
        KeyOp::Key { key, down: true }
    }
    fn u(key: ScanKey) -> KeyOp {
        KeyOp::Key { key, down: false }
    }
    fn k(usage: u16) -> ScanKey {
        scan_key(usage).unwrap()
    }

    #[test]
    fn plain_key() {
        let mut t = KeyTracker::new();
        assert_eq!(t.key(C, true, 0).unwrap(), vec![d(k(C))]);
        assert_eq!(t.key(C, false, 0).unwrap(), vec![u(k(C))]);
        assert!(t.is_idle());
    }

    #[test]
    fn an_older_devices_command_c_presses_ctrl_around_it() {
        let mut t = KeyTracker::new();
        assert_eq!(t.key(C, true, FLAG_COMMAND).unwrap(), vec![d(LEFT_CTRL), d(k(C))]);
        assert_eq!(t.key(C, false, FLAG_COMMAND).unwrap(), vec![u(k(C)), u(LEFT_CTRL)]);
        assert!(t.is_idle());
    }

    #[test]
    fn spotlight_key_leaves_nothing_held() {
        // ⌘Space as one key with the flag, then a plain click must find no Ctrl down.
        let mut t = KeyTracker::new();
        t.key(SPACE, true, FLAG_COMMAND).unwrap();
        t.key(SPACE, false, FLAG_COMMAND).unwrap();
        assert!(t.is_idle());
        assert!(!t.holds(Modifier::Ctrl));
    }

    #[test]
    fn a_newer_devices_shortcut_with_its_modifier_key() {
        let mut t = KeyTracker::new();
        assert_eq!(t.key(L_CMD, true, FLAG_COMMAND).unwrap(), vec![d(LEFT_CTRL)]);
        // The chord's flags ask for Ctrl, which the ⌘ key already holds: no second press.
        assert_eq!(t.key(C, true, FLAG_COMMAND).unwrap(), vec![d(k(C))]);
        assert_eq!(t.key(C, false, FLAG_COMMAND).unwrap(), vec![u(k(C))]);
        assert!(t.holds(Modifier::Ctrl));
        assert_eq!(t.key(L_CMD, false, 0).unwrap(), vec![u(LEFT_CTRL)]);
        assert!(t.is_idle());
    }

    #[test]
    fn command_and_control_share_the_pcs_ctrl() {
        let mut t = KeyTracker::new();
        assert_eq!(t.key(L_CMD, true, FLAG_COMMAND).unwrap(), vec![d(LEFT_CTRL)]);
        assert_eq!(t.key(L_CTRL, true, FLAG_COMMAND | FLAG_CONTROL).unwrap(), vec![]);
        // ⌘ up: Ctrl stays down, ⌃ still holds it.
        assert_eq!(t.key(L_CMD, false, FLAG_CONTROL).unwrap(), vec![]);
        assert!(t.holds(Modifier::Ctrl));
        assert_eq!(t.key(L_CTRL, false, 0).unwrap(), vec![u(LEFT_CTRL)]);
        assert!(t.is_idle());
    }

    #[test]
    fn a_key_without_the_flag_lets_go_of_a_stale_modifier() {
        // A device from before KeyStrokes never sent the hardware ⌘'s release.
        let mut t = KeyTracker::new();
        t.key(L_CMD, true, FLAG_COMMAND).unwrap();
        assert_eq!(t.key(V, true, 0).unwrap(), vec![u(LEFT_CTRL), d(k(V))]);
        assert_eq!(t.key(V, false, 0).unwrap(), vec![u(k(V))]);
        assert!(t.is_idle());
    }

    #[test]
    fn shift_option_command_chord() {
        let mut t = KeyTracker::new();
        let ops = t.key(C, true, FLAG_COMMAND | FLAG_SHIFT | FLAG_OPTION).unwrap();
        assert_eq!(ops, vec![d(LEFT_CTRL), d(LEFT_SHIFT), d(LEFT_ALT), d(k(C))]);
        let ops = t.key(C, false, FLAG_COMMAND | FLAG_SHIFT | FLAG_OPTION).unwrap();
        assert_eq!(ops[0], u(k(C)));
        assert_eq!(ops.len(), 4);
        assert!(t.is_idle());
    }

    #[test]
    fn next_chord_drops_modifiers_the_last_one_needed() {
        let mut t = KeyTracker::new();
        t.key(C, true, FLAG_COMMAND | FLAG_SHIFT).unwrap();
        // V comes down with ⌘ alone while C is still down: Shift goes, Ctrl stays.
        assert_eq!(t.key(V, true, FLAG_COMMAND).unwrap(), vec![u(LEFT_SHIFT), d(k(V))]);
        t.key(C, false, FLAG_COMMAND).unwrap();
        assert!(t.holds(Modifier::Ctrl));
        assert_eq!(t.key(V, false, FLAG_COMMAND).unwrap(), vec![u(k(V)), u(LEFT_CTRL)]);
        assert!(t.is_idle());
    }

    #[test]
    fn right_command_is_right_ctrl() {
        let mut t = KeyTracker::new();
        assert_eq!(t.key(R_CMD, true, FLAG_COMMAND).unwrap(), vec![d(RIGHT_CTRL)]);
        assert_eq!(t.key(C, true, FLAG_COMMAND).unwrap(), vec![d(k(C))]);
    }

    #[test]
    fn unknown_usage_changes_nothing() {
        let mut t = KeyTracker::new();
        t.key(L_SHIFT, true, FLAG_SHIFT).unwrap();
        assert_eq!(t.key(0x00, true, 0), None);
        assert!(t.holds(Modifier::Shift));
    }

    #[test]
    fn text_lets_go_of_modifiers_and_types_unicode() {
        let mut t = KeyTracker::new();
        t.key(L_OPT, true, FLAG_OPTION).unwrap();
        let ops = t.text("aé\n😀\u{8}\t");
        assert_eq!(ops[0], u(LEFT_ALT));
        let rest = &ops[1..];
        let want = vec![
            KeyOp::Unicode { unit: 'a' as u16, down: true },
            KeyOp::Unicode { unit: 'a' as u16, down: false },
            KeyOp::Unicode { unit: 0xE9, down: true },
            KeyOp::Unicode { unit: 0xE9, down: false },
            d(RETURN),
            u(RETURN),
            KeyOp::Unicode { unit: 0xD83D, down: true },
            KeyOp::Unicode { unit: 0xD83D, down: false },
            KeyOp::Unicode { unit: 0xDE00, down: true },
            KeyOp::Unicode { unit: 0xDE00, down: false },
            d(BACKSPACE),
            u(BACKSPACE),
            d(TAB),
            u(TAB),
        ];
        assert_eq!(rest, &want[..]);
        assert!(t.is_idle());
    }

    #[test]
    fn crlf_is_one_return() {
        let mut t = KeyTracker::new();
        assert_eq!(t.text("\r\n"), vec![d(RETURN), u(RETURN)]);
    }

    #[test]
    fn release_all_lets_go_of_keys_then_modifiers() {
        let mut t = KeyTracker::new();
        t.key(L_SHIFT, true, FLAG_SHIFT).unwrap();
        t.key(C, true, FLAG_SHIFT | FLAG_COMMAND).unwrap();
        t.key(V, true, FLAG_SHIFT | FLAG_COMMAND).unwrap();
        let ops = t.release_all();
        let first_modifier = ops.iter().position(|op| match op {
            KeyOp::Key { key, .. } => modifier_of(*key).is_some(),
            _ => false,
        });
        assert_eq!(first_modifier, Some(2));
        assert_eq!(ops.len(), 4); // C, V, Ctrl, Shift
        assert!(ops.iter().all(|op| matches!(op, KeyOp::Key { down: false, .. })));
        assert!(t.is_idle());
        assert!(t.release_all().is_empty());
    }

    /// Random sessions: whatever a device sends, once every key it pressed came up (and its
    /// modifiers too), nothing is left down, and every up the tracker posts follows a down.
    #[test]
    fn random_sessions_never_leave_a_key_down() {
        let usages = [C, V, SPACE, L_CMD, L_CTRL, L_SHIFT, L_OPT, R_CMD, 0x04, 0x52];
        let flag_sets = [0, FLAG_COMMAND, FLAG_SHIFT, FLAG_OPTION, FLAG_COMMAND | FLAG_SHIFT, FLAG_CONTROL];
        let mut seed: u64 = 0x5eed;
        let mut next = move |n: usize| {
            seed ^= seed << 13;
            seed ^= seed >> 7;
            seed ^= seed << 17;
            (seed % n as u64) as usize
        };
        for _ in 0..2000 {
            let mut t = KeyTracker::new();
            let mut model: BTreeMap<ScanKey, i32> = BTreeMap::new();
            let mut device_down: BTreeSet<u16> = BTreeSet::new();
            let apply = |ops: &[KeyOp], model: &mut BTreeMap<ScanKey, i32>| {
                for op in ops {
                    if let KeyOp::Key { key, down } = op {
                        let e = model.entry(*key).or_insert(0);
                        if *down {
                            *e = 1;
                        } else {
                            *e = 0;
                        }
                    }
                }
            };
            for _ in 0..30 {
                let usage = usages[next(usages.len())];
                let flags = flag_sets[next(flag_sets.len())];
                let down = next(2) == 0;
                if down {
                    device_down.insert(usage);
                } else {
                    device_down.remove(&usage);
                }
                let ops = t.key(usage, down, flags).unwrap();
                apply(&ops, &mut model);
                if next(10) == 0 {
                    let ops = t.text("x");
                    apply(&ops, &mut model);
                    device_down.retain(|u| !is_modifier_usage(*u));
                }
            }
            for usage in device_down.clone() {
                let ops = t.key(usage, false, 0).unwrap();
                apply(&ops, &mut model);
            }
            assert!(model.values().all(|v| *v == 0), "left down: {model:?}");
            assert!(t.is_idle(), "tracker not idle: {t:?}");
        }
    }
}
