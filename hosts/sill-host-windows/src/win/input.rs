//! Input from the devices as SendInput events: the pointer at absolute positions on the virtual
//! desktop, buttons, the wheel (both ways), keys by scancode and text as Unicode. What is down
//! because of Sill is tracked, so it can all be let go (a device leaving, the host's end).
//!
//! Double and triple clicks need nothing here: Windows counts them from the timing and place of
//! the downs, as for a real mouse. Scroll phases are ignored (Windows has no phased wheel); a
//! gesture's start drops the wheel's rounding remainder.
//!
//! SendInput cannot reach a window of a process running at a higher integrity level (an elevated
//! app, Task Manager) or the secure desktop (UAC prompts, the lock screen): those events are
//! dropped by Windows (UIPI), and the injector says so once.

use sill_host_core::platform::{Button, Input, ScrollPhase};
use windows::Win32::UI::Input::KeyboardAndMouse::{
    SendInput, INPUT, INPUT_0, INPUT_KEYBOARD, INPUT_MOUSE, KEYBDINPUT, KEYBD_EVENT_FLAGS, KEYEVENTF_EXTENDEDKEY,
    KEYEVENTF_KEYUP, KEYEVENTF_SCANCODE, KEYEVENTF_UNICODE, MOUSEEVENTF_ABSOLUTE, MOUSEEVENTF_HWHEEL,
    MOUSEEVENTF_LEFTDOWN, MOUSEEVENTF_LEFTUP, MOUSEEVENTF_MOVE, MOUSEEVENTF_RIGHTDOWN, MOUSEEVENTF_RIGHTUP,
    MOUSEEVENTF_VIRTUALDESK, MOUSEEVENTF_WHEEL, MOUSEINPUT, MOUSE_EVENT_FLAGS, VIRTUAL_KEY,
};
use windows::Win32::UI::WindowsAndMessaging::{
    GetCursorPos, GetSystemMetrics, SM_CXVIRTUALSCREEN, SM_CYVIRTUALSCREEN, SM_XVIRTUALSCREEN, SM_YVIRTUALSCREEN,
};

use super::util::log_once;
use crate::keymap::Modifier;
use crate::keys::{KeyOp, KeyTracker};
use crate::pointer::{VirtualScreen, WheelAccumulator};

/// dwExtraInfo of every event Sill posts ("SILL"), so a hook could tell them from the PC's own.
pub const SILL_EXTRA_INFO: usize = 0x5349_4C4C;

pub struct Injector {
    keys: KeyTracker,
    wheel: WheelAccumulator,
    left_down: bool,
    right_down: bool,
}

impl Injector {
    pub fn new() -> Self {
        Injector { keys: KeyTracker::new(), wheel: WheelAccumulator::new(), left_down: false, right_down: false }
    }

    pub fn inject(&mut self, input: Input) {
        match input {
            Input::Move { x, y } => self.send(&[mouse_at(x, y, MOUSE_EVENT_FLAGS(0), 0)]),
            Input::ButtonDown { button, x, y } => {
                let flag = match button {
                    Button::Left => {
                        self.left_down = true;
                        MOUSEEVENTF_LEFTDOWN
                    }
                    Button::Right => {
                        self.right_down = true;
                        MOUSEEVENTF_RIGHTDOWN
                    }
                };
                self.send(&[mouse_at(x, y, flag, 0)]);
            }
            Input::ButtonUp { button, x, y } => {
                let flag = match button {
                    Button::Left => {
                        self.left_down = false;
                        MOUSEEVENTF_LEFTUP
                    }
                    Button::Right => {
                        self.right_down = false;
                        MOUSEEVENTF_RIGHTUP
                    }
                };
                self.send(&[mouse_at(x, y, flag, 0)]);
            }
            Input::Scroll { x, y, dx, dy } => {
                let (vertical, horizontal) = self.wheel.take(dx, dy);
                // The wheel goes to the window under the pointer (Windows 10's default), so the
                // pointer goes there first.
                let mut events = vec![mouse_at(x, y, MOUSE_EVENT_FLAGS(0), 0)];
                if vertical != 0 {
                    events.push(mouse(0, 0, MOUSEEVENTF_WHEEL, vertical as u32));
                }
                if horizontal != 0 {
                    events.push(mouse(0, 0, MOUSEEVENTF_HWHEEL, horizontal as u32));
                }
                self.send(&events);
            }
            Input::ScrollPhase { phase, .. } => {
                if matches!(phase, ScrollPhase::Began | ScrollPhase::MomentumBegan) {
                    self.wheel.reset();
                }
            }
            Input::Key { hid_usage, down, modifiers } => {
                if let Some(ops) = self.keys.key(hid_usage, down, modifiers) {
                    self.post_keys(&ops);
                }
            }
            Input::Text(text) => {
                let ops = self.keys.text(&text);
                self.post_keys(&ops);
            }
        }
    }

    /// Lets go of every key and button down because of Sill (a device left, the host is ending).
    pub fn release_all(&mut self) {
        let ops = self.keys.release_all();
        self.post_keys(&ops);
        let mut ups = Vec::new();
        if std::mem::take(&mut self.left_down) {
            ups.push(mouse(0, 0, MOUSEEVENTF_LEFTUP, 0));
        }
        if std::mem::take(&mut self.right_down) {
            ups.push(mouse(0, 0, MOUSEEVENTF_RIGHTUP, 0));
        }
        if !ups.is_empty() {
            self.send(&ups);
        }
        self.wheel.reset();
    }

    /// Whether Sill holds Alt down (raise's foreground nudge must not touch it then).
    pub fn holds_alt(&self) -> bool {
        self.keys.holds(Modifier::Alt)
    }

    fn post_keys(&self, ops: &[KeyOp]) {
        if ops.is_empty() {
            return;
        }
        let events: Vec<INPUT> = ops.iter().map(key_input).collect();
        self.send(&events);
    }

    fn send(&self, events: &[INPUT]) {
        let sent = unsafe { SendInput(events, std::mem::size_of::<INPUT>() as i32) };
        if (sent as usize) < events.len() {
            log_once(
                "sendinput-blocked",
                "SendInput was refused (an elevated window or the secure desktop has the focus, or this \
                 session is locked); input goes nowhere until that changes. Run the host as administrator \
                 to control elevated windows.",
            );
        }
    }
}

impl Drop for Injector {
    fn drop(&mut self) {
        self.release_all();
    }
}

fn virtual_screen() -> VirtualScreen {
    unsafe {
        VirtualScreen {
            left: GetSystemMetrics(SM_XVIRTUALSCREEN),
            top: GetSystemMetrics(SM_YVIRTUALSCREEN),
            width: GetSystemMetrics(SM_CXVIRTUALSCREEN),
            height: GetSystemMetrics(SM_CYVIRTUALSCREEN),
        }
    }
}

/// A mouse event at a desktop position: the move and `flags` in one event.
fn mouse_at(x: f64, y: f64, flags: MOUSE_EVENT_FLAGS, data: u32) -> INPUT {
    let (nx, ny) = virtual_screen().normalize(x, y);
    mouse(nx, ny, MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK | flags, data)
}

fn mouse(dx: i32, dy: i32, flags: MOUSE_EVENT_FLAGS, data: u32) -> INPUT {
    INPUT {
        r#type: INPUT_MOUSE,
        Anonymous: INPUT_0 {
            mi: MOUSEINPUT { dx, dy, mouseData: data, dwFlags: flags, time: 0, dwExtraInfo: SILL_EXTRA_INFO },
        },
    }
}

fn key_input(op: &KeyOp) -> INPUT {
    let (scan, flags) = match *op {
        KeyOp::Key { key, down } => {
            let mut flags = KEYEVENTF_SCANCODE;
            if key.extended {
                flags |= KEYEVENTF_EXTENDEDKEY;
            }
            if !down {
                flags |= KEYEVENTF_KEYUP;
            }
            (key.code as u16, flags)
        }
        KeyOp::Unicode { unit, down } => {
            let mut flags = KEYEVENTF_UNICODE;
            if !down {
                flags |= KEYEVENTF_KEYUP;
            }
            (unit, flags)
        }
    };
    keyboard(scan, flags)
}

fn keyboard(scan: u16, flags: KEYBD_EVENT_FLAGS) -> INPUT {
    INPUT {
        r#type: INPUT_KEYBOARD,
        Anonymous: INPUT_0 {
            ki: KEYBDINPUT { wVk: VIRTUAL_KEY(0), wScan: scan, dwFlags: flags, time: 0, dwExtraInfo: SILL_EXTRA_INFO },
        },
    }
}

/// An input event that does nothing (a mouse event with no movement and no buttons). Sent before
/// SetForegroundWindow: the foreground lock lets the process that sent the last input event
/// change the foreground window (PowerToys does the same).
pub fn nudge_foreground_lock() {
    let event = mouse(0, 0, MOUSE_EVENT_FLAGS(0), 0);
    unsafe {
        SendInput(&[event], std::mem::size_of::<INPUT>() as i32);
    }
}

/// Where the pointer is, in desktop pixels.
pub fn pointer_location() -> Option<(f64, f64)> {
    let mut p = Default::default();
    unsafe { GetCursorPos(&mut p).ok()? };
    Some((p.x as f64, p.y as f64))
}
