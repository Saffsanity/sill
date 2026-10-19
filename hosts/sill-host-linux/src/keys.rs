//! A device's keys as the X key presses and releases to fake (XTest), by evdev code: the Linux side of
//! KeyStrokes.swift. X keeps modifiers as keys held down, so a chord the device sends as one key
//! carrying modifier bits (the Spotlight key's ⌘Space, the key row's ⌘esc, a latched ⌘S) becomes the
//! modifier keys pressed around the key, as a keyboard would:
//!   - a key's down presses the modifiers its bits ask for that no key down holds yet, then the key;
//!     its up releases the key, then those modifiers, so nothing a chord pressed outlives it (the
//!     Mac's "stuck command after Spotlight");
//!   - a modifier's own key (0xE0–0xE7, a hardware keyboard's or the key row's latch) goes down and
//!     up as it comes;
//!   - a key or text whose bits no longer say a modifier lets go of that modifier's key first (a
//!     device that lost a hardware ⌘'s release);
//!   - `text` lets go of every modifier key (text is typed with none held) and `release_all` of every
//!     key, for a device that leaves and the host's end.
//!
//! Two usages can share a key (⌘ and ⌃ are both Control): a key is pressed once and released only
//! when nothing holds it any more.
//!
//! Pure: no X, compiled and tested on every platform.

use std::collections::{BTreeMap, BTreeSet};

use crate::keymap::{self, Modifier};

/// One fake key event: an evdev code going down or up.
pub type KeyEvent = (u16, bool);

#[derive(Default, Debug)]
pub struct KeyState {
    /// Usages whose down went out and whose up has not.
    usages_down: BTreeSet<u16>,
    /// Each evdev code held down, with how many usages or chords hold it.
    held: BTreeMap<u16, u32>,
    /// The modifier codes pressed for a key's chord (by the key's usage), released with its up.
    chords: BTreeMap<u16, Vec<u16>>,
}

impl KeyState {
    pub fn new() -> Self {
        Self::default()
    }

    /// The modifiers the codes held down give.
    pub fn held_modifiers(&self) -> Vec<Modifier> {
        Modifier::ALL
            .into_iter()
            .filter(|m| self.held.keys().any(|c| code_modifier(*c) == Some(*m)))
            .collect()
    }

    /// Whether any key is down (for the host's end and the tests).
    pub fn any_down(&self) -> bool {
        !self.held.is_empty()
    }

    /// A device's key: the events to fake, in order, or None for a usage no PC key answers to.
    pub fn key(&mut self, usage: u16, down: bool, bits: u64) -> Option<Vec<KeyEvent>> {
        let code = keymap::evdev(usage)?;
        let said = keymap::modifiers(bits);
        let mut out = Vec::new();
        self.let_go(&said, Some(usage), &mut out);
        if keymap::modifier_of(usage).is_some() {
            if down {
                if self.usages_down.insert(usage) {
                    self.press(code, &mut out);
                }
            } else if self.usages_down.remove(&usage) {
                self.release(code, &mut out);
            }
        } else if down {
            if self.usages_down.contains(&usage) {
                // A held key repeating: one more press, as X's autorepeat looks.
                out.push((code, true));
            } else {
                let held = self.held_modifiers();
                let mut chord = Vec::new();
                for m in said.iter().filter(|m| !held.contains(m)) {
                    self.press(m.evdev(), &mut out);
                    chord.push(m.evdev());
                }
                self.chords.insert(usage, chord);
                self.usages_down.insert(usage);
                self.press(code, &mut out);
            }
        } else if self.usages_down.remove(&usage) {
            self.release(code, &mut out);
            for c in self.chords.remove(&usage).unwrap_or_default().into_iter().rev() {
                self.release(c, &mut out);
            }
        }
        Some(out)
    }

    /// Text is about to be typed: every modifier key a device holds goes up first.
    pub fn text(&mut self) -> Vec<KeyEvent> {
        let mut out = Vec::new();
        self.let_go(&[], None, &mut out);
        out
    }

    /// A device left, or the host is ending: every key up, other keys first, then modifiers.
    pub fn release_all(&mut self) -> Vec<KeyEvent> {
        let mut out = Vec::new();
        let keys: Vec<u16> = self.usages_down.iter().copied().filter(|u| keymap::modifier_of(*u).is_none()).collect();
        for usage in keys {
            self.usages_down.remove(&usage);
            if let Some(code) = keymap::evdev(usage) {
                self.release(code, &mut out);
            }
            for c in self.chords.remove(&usage).unwrap_or_default().into_iter().rev() {
                self.release(c, &mut out);
            }
        }
        let mods: Vec<u16> = self.usages_down.iter().rev().copied().collect();
        for usage in mods {
            self.usages_down.remove(&usage);
            if let Some(code) = keymap::evdev(usage) {
                self.release(code, &mut out);
            }
        }
        // Anything still counted (it cannot be, but a stuck key is worse than a stray release).
        let rest: Vec<u16> = self.held.keys().copied().collect();
        for code in rest {
            self.held.remove(&code);
            out.push((code, false));
        }
        out
    }

    /// The ups of modifier keys down (but `except`) whose modifier `keeping` lacks.
    fn let_go(&mut self, keeping: &[Modifier], except: Option<u16>, out: &mut Vec<KeyEvent>) {
        let mods: Vec<u16> = self
            .usages_down
            .iter()
            .rev()
            .copied()
            .filter(|u| Some(*u) != except)
            .filter(|u| keymap::modifier_of(*u).is_some_and(|m| !keeping.contains(&m)))
            .collect();
        for usage in mods {
            self.usages_down.remove(&usage);
            if let Some(code) = keymap::evdev(usage) {
                self.release(code, out);
            }
        }
    }

    fn press(&mut self, code: u16, out: &mut Vec<KeyEvent>) {
        let n = self.held.entry(code).or_insert(0);
        if *n == 0 {
            out.push((code, true));
        }
        *n += 1;
    }

    fn release(&mut self, code: u16, out: &mut Vec<KeyEvent>) {
        if let Some(n) = self.held.get_mut(&code) {
            *n -= 1;
            if *n == 0 {
                self.held.remove(&code);
                out.push((code, false));
            }
        }
    }
}

/// The modifier an evdev code holds (either side's key).
fn code_modifier(code: u16) -> Option<Modifier> {
    match code {
        29 | 97 => Some(Modifier::Control),
        42 | 54 => Some(Modifier::Shift),
        56 | 100 => Some(Modifier::Alt),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::keymap::{COMMAND_BIT, CONTROL_BIT, OPTION_BIT, SHIFT_BIT};

    const CTRL: u16 = 29;
    const SHIFT: u16 = 42;
    const ALT: u16 = 56;
    const SPACE: u16 = 57;
    const C: u16 = 46;

    #[test]
    fn a_chord_presses_its_modifiers_around_the_key_and_leaves_nothing() {
        let mut k = KeyState::new();
        // The Spotlight key as an older device sends it: ⌘Space down and up, each carrying ⌘.
        assert_eq!(k.key(0x2C, true, COMMAND_BIT).unwrap(), vec![(CTRL, true), (SPACE, true)]);
        assert_eq!(k.key(0x2C, false, COMMAND_BIT).unwrap(), vec![(SPACE, false), (CTRL, false)]);
        assert!(!k.any_down());
    }

    #[test]
    fn a_held_modifier_key_is_not_pressed_again_nor_released_by_the_chord() {
        let mut k = KeyState::new();
        assert_eq!(k.key(0xE3, true, COMMAND_BIT).unwrap(), vec![(CTRL, true)]); // ⌘ down
        assert_eq!(k.key(0x06, true, COMMAND_BIT).unwrap(), vec![(C, true)]); // C with ⌘
        assert_eq!(k.key(0x06, false, COMMAND_BIT).unwrap(), vec![(C, false)]);
        assert_eq!(k.held_modifiers(), vec![Modifier::Control]);
        assert_eq!(k.key(0xE3, false, 0).unwrap(), vec![(CTRL, false)]);
        assert!(!k.any_down());
    }

    #[test]
    fn command_and_control_share_one_key() {
        let mut k = KeyState::new();
        assert_eq!(k.key(0xE0, true, CONTROL_BIT).unwrap(), vec![(CTRL, true)]);
        assert_eq!(k.key(0xE3, true, CONTROL_BIT | COMMAND_BIT).unwrap(), vec![]);
        assert_eq!(k.key(0xE3, false, CONTROL_BIT).unwrap(), vec![]); // ⌃ still holds it
        assert_eq!(k.key(0xE0, false, 0).unwrap(), vec![(CTRL, false)]);
    }

    #[test]
    fn a_key_saying_a_modifier_is_gone_lets_go_of_it_first() {
        let mut k = KeyState::new();
        k.key(0xE1, true, SHIFT_BIT).unwrap(); // ⇧ down, its up lost
        assert_eq!(k.key(0x04, true, 0).unwrap(), vec![(SHIFT, false), (30, true)]);
        assert_eq!(k.key(0x04, false, 0).unwrap(), vec![(30, false)]);
        assert!(!k.any_down());
    }

    #[test]
    fn option_shift_chord_and_text_and_release_all() {
        let mut k = KeyState::new();
        assert_eq!(
            k.key(0x04, true, OPTION_BIT | SHIFT_BIT).unwrap(),
            vec![(SHIFT, true), (ALT, true), (30, true)]
        );
        // Left down (the device left): release_all lets go of the key, then its chord.
        assert_eq!(k.release_all(), vec![(30, false), (ALT, false), (SHIFT, false)]);
        assert!(!k.any_down());
        k.key(0xE2, true, OPTION_BIT).unwrap();
        assert_eq!(k.text(), vec![(ALT, false)]);
        assert!(!k.any_down());
    }

    #[test]
    fn repeats_unknown_usages_and_stray_ups() {
        let mut k = KeyState::new();
        assert_eq!(k.key(0x04, true, 0).unwrap(), vec![(30, true)]);
        assert_eq!(k.key(0x04, true, 0).unwrap(), vec![(30, true)]); // a repeat
        assert_eq!(k.key(0x04, false, 0).unwrap(), vec![(30, false)]);
        assert_eq!(k.key(0x05, false, 0).unwrap(), vec![]); // an up whose down never went
        assert!(k.key(0x01, true, 0).is_none()); // no key for usage 1
        assert!(!k.any_down());
    }

    #[test]
    fn random_sessions_never_leave_a_key_down() {
        // A small LCG so the test needs no crate: 20,000 random events, then release_all, every key up.
        let mut seed: u64 = 0x5111_c0de;
        let mut next = || {
            seed = seed.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
            (seed >> 33) as u32
        };
        let usages: Vec<u16> = vec![0x04, 0x06, 0x2C, 0x29, 0x52, 0xE0, 0xE1, 0xE2, 0xE3, 0xE7];
        let mut k = KeyState::new();
        let mut down: BTreeMap<u16, u32> = BTreeMap::new();
        for _ in 0..20_000 {
            let usage = usages[next() as usize % usages.len()];
            let bits = [0, COMMAND_BIT, SHIFT_BIT, OPTION_BIT, CONTROL_BIT | SHIFT_BIT][next() as usize % 5];
            let events = if next() % 13 == 0 { k.text() } else { k.key(usage, next() % 2 == 0, bits).unwrap() };
            for (code, d) in events {
                let n = down.entry(code).or_insert(0);
                if d {
                    *n += 1;
                } else {
                    assert!(*n > 0, "released {code} that was not down");
                    *n = 0;
                }
            }
        }
        for (code, d) in k.release_all() {
            assert!(!d);
            down.insert(code, 0);
        }
        assert!(down.values().all(|n| *n == 0));
        assert!(!k.any_down());
    }
}
