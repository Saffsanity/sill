//! A device's input as XTest's fake events (InputInjector.swift is the Mac's): the pointer moved
//! absolutely on the root, buttons 1 and 3, scrolling as wheel buttons 4–7, keys by their evdev code
//! (keys.rs, keymap.rs) and text by keysym, with a spare keycode remapped for a moment for a character
//! the keymap lacks (as xdotool does).

use std::sync::Arc;
use std::time::Duration;

use sill_host_core::platform::{Button, Input, ScrollPhase};
use x11rb::connection::Connection;
use x11rb::protocol::xproto::{ConnectionExt as _, BUTTON_PRESS_EVENT, BUTTON_RELEASE_EVENT, KEY_PRESS_EVENT, KEY_RELEASE_EVENT, MOTION_NOTIFY_EVENT};
use x11rb::protocol::xtest::ConnectionExt as _;
use x11rb::protocol::Event;

use super::x::X;
use crate::keymap;
use crate::keys::KeyState;
use crate::scroll::ScrollAccumulator;
use crate::text::{self, Typed};

/// The keyboard map as read from the server.
struct Keymap {
    first: u8,
    per: usize,
    syms: Vec<u32>,
    /// The server's keycodes are evdev's (code + 8). Else keys are found by their US keysym.
    evdev: bool,
    spares: Vec<u8>,
}

pub struct Injector {
    x: Arc<X>,
    keys: KeyState,
    scroll: ScrollAccumulator,
    keymap: Option<Keymap>,
    left_down: bool,
    right_down: bool,
    said_keymap: bool,
}

impl Injector {
    pub fn new(x: Arc<X>) -> Injector {
        Injector { x, keys: KeyState::new(), scroll: ScrollAccumulator::new(), keymap: None, left_down: false, right_down: false, said_keymap: false }
    }

    fn keymap(&mut self) -> &Keymap {
        if self.keymap.is_none() {
            let setup = self.x.conn.setup();
            let (first, last) = (setup.min_keycode, setup.max_keycode);
            let reply = self.x.conn.get_keyboard_mapping(first, last - first + 1).ok().and_then(|c| c.reply().ok());
            let (per, syms) = reply.map(|r| (r.keysyms_per_keycode as usize, r.keysyms)).unwrap_or((0, Vec::new()));
            let at = |kc: u8| -> u32 {
                if per == 0 || kc < first {
                    return 0;
                }
                syms.get((kc - first) as usize * per).copied().unwrap_or(0)
            };
            let evdev = keymap::EVDEV_WITNESSES.iter().all(|(kc, sym)| at(*kc) == *sym);
            let spares = text::spare_keycodes(&syms, per, first, 8);
            if !self.said_keymap {
                self.said_keymap = true;
                sill_host_core::log(&format!(
                    "Input: the keymap {} ({} keycodes, {} keysyms each); {} spare keycodes for characters it lacks.",
                    if evdev { "is evdev's (keys by evdev code + 8)" } else { "is not evdev's (keys found by keysym)" },
                    last as u32 - first as u32 + 1,
                    per,
                    spares.len()
                ));
            }
            self.keymap = Some(Keymap { first, per, syms, evdev, spares });
        }
        self.keymap.as_ref().unwrap()
    }

    /// The X keycode for an evdev code: + 8 on an evdev keymap, else where its keysym is.
    fn keycode(&mut self, evdev: u16) -> Option<u8> {
        let km = self.keymap();
        if km.evdev {
            return u8::try_from(evdev + 8).ok();
        }
        let usage = keymap::all_usages().find(|u| keymap::evdev(*u) == Some(evdev))?;
        let sym = keymap::keysym(usage)?;
        text::find(&km.syms, km.per, km.first, sym).map(|(kc, _)| kc)
    }

    fn fake(&self, type_: u8, detail: u8, x: i16, y: i16) {
        let _ = self.x.conn.xtest_fake_input(type_, detail, x11rb::CURRENT_TIME, self.x.root, x, y, 0);
    }

    fn motion(&self, x: f64, y: f64) {
        let (x, y) = (clamp16(x), clamp16(y));
        self.fake(MOTION_NOTIFY_EVENT, 0, x, y);
    }

    fn button(&self, button: u8, down: bool) {
        self.fake(if down { BUTTON_PRESS_EVENT } else { BUTTON_RELEASE_EVENT }, button, 0, 0);
    }

    fn key_events(&mut self, events: Vec<(u16, bool)>) {
        for (code, down) in events {
            if let Some(kc) = self.keycode(code) {
                self.fake(if down { KEY_PRESS_EVENT } else { KEY_RELEASE_EVENT }, kc, 0, 0);
            }
        }
    }

    pub fn inject(&mut self, input: Input) {
        // The shared connection's events (it selects none, but every client gets MappingNotify): a
        // keymap change (a layout switch, or this injector's own spare key) is read again.
        while let Ok(Some(event)) = self.x.conn.poll_for_event() {
            if let Event::MappingNotify(_) = event {
                self.keymap = None;
            }
        }
        match input {
            Input::Move { x, y } => self.motion(x, y),
            Input::ButtonDown { button, x, y } => {
                self.motion(x, y);
                self.button(button_number(button), true);
                *self.held(button) = true;
            }
            Input::ButtonUp { button, x, y } => {
                self.motion(x, y);
                self.button(button_number(button), false);
                *self.held(button) = false;
            }
            Input::Scroll { x, y, dx, dy } => {
                let clicks = self.scroll.add(dx, dy);
                if !clicks.is_empty() {
                    self.motion(x, y);
                    for b in clicks {
                        self.button(b, true);
                        self.button(b, false);
                    }
                }
            }
            Input::ScrollPhase { phase, .. } => match phase {
                ScrollPhase::Began | ScrollPhase::Ended | ScrollPhase::MomentumEnded => self.scroll.reset(),
                ScrollPhase::MomentumBegan => {}
            },
            Input::Key { hid_usage, down, modifiers } => {
                if let Some(events) = self.keys.key(hid_usage, down, modifiers) {
                    self.key_events(events);
                }
            }
            Input::Text(s) => self.type_text(&s),
        }
        let _ = self.x.conn.flush();
    }

    fn held(&mut self, button: Button) -> &mut bool {
        match button {
            Button::Left => &mut self.left_down,
            Button::Right => &mut self.right_down,
        }
    }

    fn type_text(&mut self, s: &str) {
        let release = self.keys.text();
        self.key_events(release);
        let syms: Vec<u32> = s.chars().filter_map(text::keysym).map(|t| match t {
            Typed::Key(sym) | Typed::Sym(sym) => sym,
        }).collect();
        let shift = self.keycode(keymap::Modifier::Shift.evdev());
        let km = self.keymap();
        let (first, per) = (km.first, km.per);
        let found: Vec<Option<(u8, bool)>> = syms.iter().map(|sym| text::find(&km.syms, per, first, *sym)).collect();
        let spares = km.spares.clone();
        let steps = text::plan(&syms, &spares, |sym| syms.iter().position(|s| *s == sym).is_some_and(|i| found[i].is_some()));
        // Characters not on the keymap go through spare keycodes, given their keysym (at both
        // levels, so a Shift held somewhere does not change it) and back to NoSymbol afterwards.
        // Clients read the new mapping from the MappingNotify the server queues ahead of the key
        // events, so the order holds; the mapping goes back only after they had time to read the keys.
        let width = per.max(2);
        let mut remapped = false;
        for step in steps {
            match step {
                text::Step::Type(sym) => {
                    let i = syms.iter().position(|s| *s == sym).unwrap();
                    if let Some((kc, shifted)) = found[i] {
                        let shift = shift.filter(|_| shifted);
                        if let Some(s) = shift {
                            self.fake(KEY_PRESS_EVENT, s, 0, 0);
                        }
                        self.fake(KEY_PRESS_EVENT, kc, 0, 0);
                        self.fake(KEY_RELEASE_EVENT, kc, 0, 0);
                        if let Some(s) = shift {
                            self.fake(KEY_RELEASE_EVENT, s, 0, 0);
                        }
                    }
                }
                text::Step::Assign(kc, sym) => {
                    let mut row = vec![sym; 2];
                    row.resize(width, 0);
                    let _ = self.x.conn.change_keyboard_mapping(1, kc, width as u8, &row);
                    let _ = self.x.conn.flush();
                    remapped = true;
                    std::thread::sleep(Duration::from_millis(5));
                }
                text::Step::TypeSpare(kc) => {
                    self.fake(KEY_PRESS_EVENT, kc, 0, 0);
                    self.fake(KEY_RELEASE_EVENT, kc, 0, 0);
                }
                text::Step::Restore => {
                    let _ = self.x.conn.flush();
                    std::thread::sleep(Duration::from_millis(40));
                    for kc in &spares {
                        let _ = self.x.conn.change_keyboard_mapping(1, *kc, width as u8, &vec![0; width]);
                    }
                    let _ = self.x.conn.flush();
                }
            }
        }
        if remapped {
            self.keymap = None; // read again: our own changes went by
        }
    }

    /// A device left, or the host is ending: every key and button it holds goes up.
    pub fn release_all(&mut self) {
        let events = self.keys.release_all();
        self.key_events(events);
        if self.left_down {
            self.button(1, false);
            self.left_down = false;
        }
        if self.right_down {
            self.button(3, false);
            self.right_down = false;
        }
        let _ = self.x.conn.flush();
    }

}

/// The pointer on the root.
pub fn pointer(x: &X) -> Option<(f64, f64)> {
    let r = x.conn.query_pointer(x.root).ok()?.reply().ok()?;
    Some((r.root_x as f64, r.root_y as f64))
}

fn button_number(b: Button) -> u8 {
    match b {
        Button::Left => 1,
        Button::Right => 3,
    }
}

fn clamp16(v: f64) -> i16 {
    if !v.is_finite() {
        return 0;
    }
    v.round().clamp(i16::MIN as f64, i16::MAX as f64) as i16
}
