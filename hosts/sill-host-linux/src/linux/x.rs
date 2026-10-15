//! One X connection with the atoms the backend uses and helpers for window properties.
//!
//! Each thread that waits for events or does heavy requests (a stream's capture, the cursor) opens a
//! connection of its own; the platform's shared one (`Platform`'s queries, input, raising) is used
//! from any thread (x11rb's RustConnection is Send + Sync).

use std::sync::Arc;

use x11rb::connection::Connection;
use x11rb::protocol::xproto::{AtomEnum, ConnectionExt as _, Window};
use x11rb::rust_connection::RustConnection;

x11rb::atom_manager! {
    pub Atoms: AtomsCookie {
        UTF8_STRING,
        WM_STATE,
        WM_CHANGE_STATE,
        WM_PROTOCOLS,
        WM_DELETE_WINDOW,
        _NET_SUPPORTED,
        _NET_CLIENT_LIST,
        _NET_CLIENT_LIST_STACKING,
        _NET_ACTIVE_WINDOW,
        _NET_CLOSE_WINDOW,
        _NET_MOVERESIZE_WINDOW,
        _NET_CURRENT_DESKTOP,
        _NET_WM_DESKTOP,
        _NET_WM_NAME,
        _NET_WM_PID,
        _NET_WM_ICON,
        _NET_WM_STATE,
        _NET_WM_STATE_HIDDEN,
        _NET_WM_STATE_FULLSCREEN,
        _NET_WM_STATE_MAXIMIZED_VERT,
        _NET_WM_STATE_MAXIMIZED_HORZ,
        _NET_WM_STATE_SKIP_TASKBAR,
        _NET_WM_WINDOW_TYPE,
        _NET_WM_WINDOW_TYPE_NORMAL,
        _NET_WM_WINDOW_TYPE_DIALOG,
        _NET_WM_WINDOW_TYPE_UTILITY,
        _NET_FRAME_EXTENTS,
        _NET_SUPPORTING_WM_CHECK,
    }
}

/// A connection, its screen's root and the atoms.
pub struct X {
    pub conn: RustConnection,
    pub screen: usize,
    pub root: Window,
    pub atoms: Atoms,
}

pub type Result<T> = std::result::Result<T, String>;

pub fn err<E: std::fmt::Display>(what: &str) -> impl Fn(E) -> String + '_ {
    move |e| format!("{what}: {e}")
}

impl X {
    /// Connects to $DISPLAY.
    pub fn connect() -> Result<Arc<X>> {
        let (conn, screen) = x11rb::connect(None).map_err(|e| {
            format!(
                "cannot open the X display {:?}: {e} (sill-host-linux needs an X11 session: Xorg, or XWayland's DISPLAY)",
                std::env::var("DISPLAY").unwrap_or_default()
            )
        })?;
        let root = conn.setup().roots[screen].root;
        let atoms = Atoms::new(&conn).map_err(err("atoms"))?.reply().map_err(err("atoms"))?;
        Ok(Arc::new(X { conn, screen, root, atoms }))
    }

    pub fn screen_size(&self) -> (u16, u16) {
        let s = &self.conn.setup().roots[self.screen];
        (s.width_in_pixels, s.height_in_pixels)
    }

    /// A property's 32-bit values (CARDINAL, WINDOW, ATOM...), empty when it is missing.
    pub fn prop32(&self, window: Window, prop: u32) -> Vec<u32> {
        self.prop32_limited(window, prop, 1 << 16)
    }

    /// At most `max` 32-bit values (a window's icon can be megabytes).
    pub fn prop32_limited(&self, window: Window, prop: u32, max: u32) -> Vec<u32> {
        let Ok(cookie) = self.conn.get_property(false, window, prop, AtomEnum::ANY, 0, max) else { return Vec::new() };
        match cookie.reply() {
            Ok(r) => r.value32().map(|v| v.collect()).unwrap_or_default(),
            Err(_) => Vec::new(),
        }
    }

    /// A property's bytes and type, or None.
    pub fn prop8(&self, window: Window, prop: u32) -> Option<(u32, Vec<u8>)> {
        let r = self.conn.get_property(false, window, prop, AtomEnum::ANY, 0, 1 << 16).ok()?.reply().ok()?;
        if r.format != 8 {
            return None;
        }
        Some((r.type_, r.value))
    }

    /// A window's title: _NET_WM_NAME (UTF-8), else WM_NAME (Latin-1, or UTF-8 when it says so).
    pub fn title(&self, window: Window) -> String {
        if let Some((_, v)) = self.prop8(window, self.atoms._NET_WM_NAME) {
            if !v.is_empty() {
                return String::from_utf8_lossy(&v).into_owned();
            }
        }
        match self.prop8(window, AtomEnum::WM_NAME.into()) {
            Some((t, v)) if t == self.atoms.UTF8_STRING => String::from_utf8_lossy(&v).into_owned(),
            Some((_, v)) => v.iter().map(|b| *b as char).collect(),
            None => String::new(),
        }
    }

    /// WM_CLASS: (instance, class).
    pub fn wm_class(&self, window: Window) -> (String, String) {
        let Some((_, v)) = self.prop8(window, AtomEnum::WM_CLASS.into()) else { return Default::default() };
        let mut parts = v.split(|b| *b == 0).map(|p| String::from_utf8_lossy(p).into_owned());
        (parts.next().unwrap_or_default(), parts.next().unwrap_or_default())
    }

    pub fn pid(&self, window: Window) -> Option<u32> {
        self.prop32(window, self.atoms._NET_WM_PID).first().copied().filter(|p| *p > 0)
    }

    /// Whether an EWMH window manager runs (_NET_SUPPORTING_WM_CHECK names a live window).
    pub fn has_ewmh_wm(&self) -> bool {
        let check = self.prop32(self.root, self.atoms._NET_SUPPORTING_WM_CHECK);
        check.first().is_some_and(|w| *w != 0 && self.conn.get_geometry(*w).ok().and_then(|c| c.reply().ok()).is_some())
    }

    /// The desktop's scale: Xft.dpi (from the RESOURCE_MANAGER property, which desktops set for
    /// HiDPI) over 96, at least 1.
    pub fn ui_scale(&self) -> f64 {
        let Some((_, v)) = self.prop8(self.root, AtomEnum::RESOURCE_MANAGER.into()) else { return 1.0 };
        let text = String::from_utf8_lossy(&v);
        text.lines()
            .find_map(|l| l.strip_prefix("Xft.dpi:").and_then(|d| d.trim().parse::<f64>().ok()))
            .map(|dpi| (dpi / 96.0).max(1.0))
            .unwrap_or(1.0)
    }

    /// Flushes and waits until the server has handled everything sent so far (a round trip, as
    /// Xlib's XSync): a request whose client goes away right after it is otherwise sometimes lost.
    pub fn sync(&self) {
        let _ = self.conn.get_input_focus().map(|c| c.reply());
    }

    pub fn supports(&self, atom: u32) -> bool {
        self.prop32(self.root, self.atoms._NET_SUPPORTED).contains(&atom)
    }
}

/// The process name for a pid (/proc/PID/comm), or None.
pub fn process_name(pid: u32) -> Option<String> {
    std::fs::read_to_string(format!("/proc/{pid}/comm")).ok().map(|s| s.trim().to_string()).filter(|s| !s.is_empty())
}
