//! The windows a device may pick (EWMH), and what a device does to one: raise, resize, close,
//! minimize, full screen. WindowCatalog.swift and WindowSizer.swift are the Mac's.
//!
//! A window is the client window (the XID the app made), never the window manager's frame around it:
//! its size is the client's, its capture the client's contents without decorations, and the EWMH
//! requests name it.

use std::time::{Duration, Instant};

use x11rb::protocol::xproto::{
    ClientMessageEvent, ConfigureWindowAux, ConnectionExt as _, EventMask, InputFocus, MapState, StackMode, Window,
};

use super::x::X;

/// One listable window.
#[derive(Clone, Debug, PartialEq)]
pub struct WinInfo {
    pub id: Window,
    pub title: String,
    pub instance: String,
    pub class: String,
    pub pid: Option<u32>,
    pub x: i32,
    pub y: i32,
    pub width: u32,
    pub height: u32,
}

/// Top-level client windows, front to back: _NET_CLIENT_LIST_STACKING (bottom to top, reversed),
/// else _NET_CLIENT_LIST, else (no window manager) the root's mapped children from the top.
pub fn clients_front_to_back(x: &X) -> Vec<Window> {
    let mut list = x.prop32(x.root, x.atoms._NET_CLIENT_LIST_STACKING);
    if list.is_empty() {
        list = x.prop32(x.root, x.atoms._NET_CLIENT_LIST);
    }
    if list.is_empty() {
        if let Ok(Ok(tree)) = x.conn.query_tree(x.root).map(|c| c.reply()) {
            list = tree.children;
        }
    }
    list.reverse();
    list
}

/// The window's rectangle on the root: its top-left in root coordinates and its size.
pub fn geometry(x: &X, w: Window) -> Option<(i32, i32, u32, u32)> {
    let g = x.conn.get_geometry(w).ok()?.reply().ok()?;
    let t = x.conn.translate_coordinates(w, x.root, 0, 0).ok()?.reply().ok()?;
    Some((t.dst_x as i32, t.dst_y as i32, g.width as u32, g.height as u32))
}

pub fn is_viewable(x: &X, w: Window) -> bool {
    x.conn
        .get_window_attributes(w)
        .ok()
        .and_then(|c| c.reply().ok())
        .is_some_and(|a| a.map_state == MapState::VIEWABLE)
}

/// A window a device may pick, or None: mapped and viewable (so on this desktop and not minimized),
/// a normal, dialog or utility window (never a dock, the desktop, a menu, a tooltip or a
/// notification), not hidden, larger than 100×100 (as the Mac's catalog), and not this process's.
pub fn listable(x: &X, w: Window) -> Option<WinInfo> {
    if !is_viewable(x, w) {
        return None;
    }
    let types = x.prop32(w, x.atoms._NET_WM_WINDOW_TYPE);
    let allowed = [x.atoms._NET_WM_WINDOW_TYPE_NORMAL, x.atoms._NET_WM_WINDOW_TYPE_DIALOG, x.atoms._NET_WM_WINDOW_TYPE_UTILITY];
    if !types.is_empty() && !allowed.contains(&types[0]) {
        return None;
    }
    let state = x.prop32(w, x.atoms._NET_WM_STATE);
    if state.contains(&x.atoms._NET_WM_STATE_HIDDEN) {
        return None;
    }
    let (wx, wy, width, height) = geometry(x, w)?;
    if width <= 100 || height <= 100 {
        return None;
    }
    let pid = x.pid(w);
    if pid == Some(std::process::id()) {
        return None;
    }
    let (instance, class) = x.wm_class(w);
    Some(WinInfo { id: w, title: x.title(w), instance, class, pid, x: wx, y: wy, width, height })
}

/// Why a window is not listed (diagnostics).
pub fn why_not_listed(x: &X, w: Window) -> String {
    let in_stacking = clients_front_to_back(x).contains(&w);
    let viewable = is_viewable(x, w);
    let types = x.prop32(w, x.atoms._NET_WM_WINDOW_TYPE);
    let state = x.prop32(w, x.atoms._NET_WM_STATE);
    let geo = geometry(x, w);
    format!(
        "{w:#x}: in client list {in_stacking}, viewable {viewable}, types {types:?}, state {state:?}, geometry {geo:?}, pid {:?} (mine {}), listable {}",
        x.pid(w),
        std::process::id(),
        listable(x, w).is_some()
    )
}

pub fn list(x: &X) -> Vec<WinInfo> {
    clients_front_to_back(x).into_iter().filter_map(|w| listable(x, w)).collect()
}

fn client_message(x: &X, window: Window, type_: u32, data: [u32; 5]) {
    let event = ClientMessageEvent::new(32, window, type_, data);
    let _ = x.conn.send_event(
        false,
        x.root,
        EventMask::SUBSTRUCTURE_REDIRECT | EventMask::SUBSTRUCTURE_NOTIFY,
        event,
    );
}

/// Source indication 2: a pager or other tool acting for the user (EWMH), which window managers
/// honour without focus-stealing prevention.
const SOURCE_PAGER: u32 = 2;

/// Brings the window forward and gives it the keyboard: _NET_ACTIVE_WINDOW (which also un-minimizes
/// it), else (no EWMH window manager) a raise and the input focus.
pub fn raise(x: &X, w: Window) {
    // A minimized window is mapped again first (ICCCM's way out of IconicState), which every window
    // manager honours; _NET_ACTIVE_WINDOW then raises and focuses it.
    if x.prop32(w, x.atoms.WM_STATE).first() == Some(&3) {
        let _ = x.conn.map_window(w);
    }
    if x.has_ewmh_wm() {
        client_message(x, w, x.atoms._NET_ACTIVE_WINDOW, [SOURCE_PAGER, 0, 0, 0, 0]);
    } else {
        let _ = x.conn.configure_window(w, &ConfigureWindowAux::new().stack_mode(StackMode::ABOVE));
        let _ = x.conn.set_input_focus(InputFocus::PARENT, w, x11rb::CURRENT_TIME);
    }
    x.sync();
}

/// Resizes the client window to width×height, keeping its top-left corner: un-maximized first (a
/// maximized window refuses), then _NET_MOVERESIZE_WINDOW with only the size (else a configure the
/// window manager sees as a request). Returns the size it got once it settles (apps have minimums
/// and size increments), within half a second.
pub fn resize(x: &X, w: Window, width: u32, height: u32) -> Option<(u32, u32)> {
    let (_, _, w0, h0) = geometry(x, w)?;
    if (w0, h0) == (width, height) {
        return Some((w0, h0));
    }
    let state = x.prop32(w, x.atoms._NET_WM_STATE);
    let maxed = [x.atoms._NET_WM_STATE_MAXIMIZED_VERT, x.atoms._NET_WM_STATE_MAXIMIZED_HORZ];
    if state.iter().any(|s| maxed.contains(s)) {
        client_message(x, w, x.atoms._NET_WM_STATE, [0, maxed[0], maxed[1], SOURCE_PAGER, 0]);
    }
    if x.has_ewmh_wm() && x.supports(x.atoms._NET_MOVERESIZE_WINDOW) {
        // Gravity 0 (the window's own), width and height only (bits 10, 11), from a pager (bits 12–15).
        let flags = (1 << 10) | (1 << 11) | (SOURCE_PAGER << 12);
        client_message(x, w, x.atoms._NET_MOVERESIZE_WINDOW, [flags, 0, 0, width, height]);
    } else {
        let _ = x.conn.configure_window(w, &ConfigureWindowAux::new().width(width).height(height));
    }
    x.sync();
    let deadline = Instant::now() + Duration::from_millis(500);
    let mut last = (w0, h0);
    let mut stable_since = Instant::now();
    loop {
        std::thread::sleep(Duration::from_millis(20));
        let (_, _, cw, ch) = geometry(x, w)?;
        if (cw, ch) != last {
            last = (cw, ch);
            stable_since = Instant::now();
        }
        let asked = last == (width, height);
        let settled = last != (w0, h0) && stable_since.elapsed() >= Duration::from_millis(60);
        if asked || settled || Instant::now() >= deadline {
            return Some(last);
        }
    }
}

/// Closes the window as its close button would: _NET_CLOSE_WINDOW, else WM_DELETE_WINDOW when the
/// app takes it. Never kills it.
pub fn close(x: &X, w: Window) {
    if x.has_ewmh_wm() && x.supports(x.atoms._NET_CLOSE_WINDOW) {
        client_message(x, w, x.atoms._NET_CLOSE_WINDOW, [0, SOURCE_PAGER, 0, 0, 0]);
    } else if x.prop32(w, x.atoms.WM_PROTOCOLS).contains(&x.atoms.WM_DELETE_WINDOW) {
        let event = ClientMessageEvent::new(32, w, x.atoms.WM_PROTOCOLS, [x.atoms.WM_DELETE_WINDOW, 0, 0, 0, 0]);
        let _ = x.conn.send_event(false, w, EventMask::NO_EVENT, event);
    }
    x.sync();
}

/// Minimizes it (ICCCM WM_CHANGE_STATE to IconicState).
pub fn minimize(x: &X, w: Window) {
    client_message(x, w, x.atoms.WM_CHANGE_STATE, [3, 0, 0, 0, 0]);
    x.sync();
}

/// Toggles full screen (_NET_WM_STATE_FULLSCREEN), as the Mac's green button does.
pub fn toggle_fullscreen(x: &X, w: Window) {
    client_message(x, w, x.atoms._NET_WM_STATE, [2, x.atoms._NET_WM_STATE_FULLSCREEN, 0, SOURCE_PAGER, 0]);
    x.sync();
}

/// The best of a window's _NET_WM_ICON images for `want` pixels: the smallest at least that large,
/// else the largest. Returns (width, height, ARGB pixels).
pub fn net_wm_icon(x: &X, w: Window, want: u32) -> Option<(u32, u32, Vec<u32>)> {
    let data = x.prop32_limited(w, x.atoms._NET_WM_ICON, 4 * 1024 * 1024);
    let mut i = 0;
    let mut best: Option<(u32, u32, usize)> = None;
    while i + 2 <= data.len() {
        let (iw, ih) = (data[i], data[i + 1]);
        let n = (iw as usize).saturating_mul(ih as usize);
        if iw == 0 || ih == 0 || iw > 1024 || ih > 1024 || i + 2 + n > data.len() {
            break;
        }
        let better = match best {
            None => true,
            Some((bw, _, _)) => {
                if bw >= want {
                    iw >= want && iw < bw
                } else {
                    iw > bw
                }
            }
        };
        if better {
            best = Some((iw, ih, i + 2));
        }
        i += 2 + n;
    }
    let (bw, bh, at) = best?;
    Some((bw, bh, data[at..at + (bw * bh) as usize].to_vec()))
}
