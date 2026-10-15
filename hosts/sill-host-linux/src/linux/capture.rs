//! Pictures of the screen or of one window, as BGRA, through MIT-SHM (a shared memory segment the X
//! server writes into: no copy through the socket), else a plain GetImage.
//!
//! A window is read from its own off-screen pixmap: the window is redirected (Composite, automatic
//! mode, so nothing changes on screen) and NameWindowPixmap names its backing pixmap, which holds the
//! whole window even where other windows cover it. The pixmap is named again before every read: a
//! window that is resized, or unmapped and mapped again, gets a new one, and an old name would keep
//! the old picture.

use std::sync::Arc;

use x11rb::connection::{Connection, RequestConnection};
use x11rb::protocol::composite::{ConnectionExt as _, Redirect};
use x11rb::protocol::randr::ConnectionExt as _;
use x11rb::protocol::shm::ConnectionExt as _;
use x11rb::protocol::xproto::{ConnectionExt as _, ImageFormat, ImageOrder, Window};

use super::windows;
use super::x::X;

/// One picture: BGRA (the fourth byte padding or alpha), `width * 4` bytes a row.
#[derive(Clone)]
pub struct Frame {
    pub width: u32,
    pub height: u32,
    pub data: Vec<u8>,
}

/// What a read found.
pub enum Grab {
    Frame(Frame),
    /// The window is there but shows nothing now (minimized, on another desktop): no new picture.
    Hidden,
    /// The window is gone (closed, destroyed).
    Gone,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Target {
    /// The primary output's rectangle of the root window.
    Desktop,
    Window(Window),
}

/// The primary output's rectangle on the root (RandR), else the whole root.
pub fn desktop_rect(x: &X) -> (i32, i32, u32, u32) {
    let (sw, sh) = x.screen_size();
    let whole = (0, 0, sw as u32, sh as u32);
    let primary = (|| {
        let out = x.conn.randr_get_output_primary(x.root).ok()?.reply().ok()?.output;
        let out = if out == 0 {
            let res = x.conn.randr_get_screen_resources_current(x.root).ok()?.reply().ok()?;
            *res.outputs.iter().find(|o| {
                x.conn.randr_get_output_info(**o, 0).ok().and_then(|c| c.reply().ok()).is_some_and(|i| i.crtc != 0)
            })?
        } else {
            out
        };
        let info = x.conn.randr_get_output_info(out, 0).ok()?.reply().ok()?;
        if info.crtc == 0 {
            return None;
        }
        let crtc = x.conn.randr_get_crtc_info(info.crtc, 0).ok()?.reply().ok()?;
        (crtc.width > 0 && crtc.height > 0).then_some((crtc.x as i32, crtc.y as i32, crtc.width as u32, crtc.height as u32))
    })();
    primary.unwrap_or(whole)
}

/// A System V shared memory segment attached to the X server.
struct Shm {
    seg: u32,
    addr: *mut u8,
    size: usize,
}

// The segment is only touched by the thread that owns its Grabber.
unsafe impl Send for Shm {}

impl Shm {
    fn new(x: &X, size: usize) -> Option<Shm> {
        unsafe {
            let id = libc::shmget(libc::IPC_PRIVATE, size, libc::IPC_CREAT | 0o600);
            if id < 0 {
                return None;
            }
            let addr = libc::shmat(id, std::ptr::null(), 0);
            if addr as isize == -1 {
                libc::shmctl(id, libc::IPC_RMID, std::ptr::null_mut());
                return None;
            }
            let seg = x.conn.generate_id().ok();
            let attached = seg.and_then(|seg| x.conn.shm_attach(seg, id as u32, false).ok()?.check().ok());
            // Marked for removal now: it goes when both sides have detached (or died).
            libc::shmctl(id, libc::IPC_RMID, std::ptr::null_mut());
            if attached.is_none() {
                libc::shmdt(addr);
                return None;
            }
            Some(Shm { seg: seg.unwrap(), addr: addr as *mut u8, size })
        }
    }

    fn free(&self, x: &X) {
        let _ = x.conn.shm_detach(self.seg);
        let _ = x.conn.flush();
        unsafe {
            libc::shmdt(self.addr as *const libc::c_void);
        }
    }
}

/// Reads one target over and over, on the thread that owns it.
pub struct Grabber {
    x: Arc<X>,
    target: Target,
    shm: Option<Shm>,
    /// MIT-SHM failed once (a server on another machine, a container without shared IPC): plain
    /// GetImage from then on.
    no_shm: bool,
    /// The window is redirected (by this connection), so its pixmap can be named.
    redirected: bool,
    /// The id the window's pixmap is named under, and whether it is named now.
    pixmap: u32,
    named: bool,
    swap: bool,
}

impl Grabber {
    pub fn new(x: Arc<X>, target: Target) -> Result<Grabber, String> {
        let pixmap = x.conn.generate_id().map_err(|e| format!("X ids: {e}"))?;
        let swap = x.conn.setup().image_byte_order != ImageOrder::LSB_FIRST;
        let has_shm = x.conn.extension_information(x11rb::protocol::shm::X11_EXTENSION_NAME).ok().flatten().is_some();
        let mut g = Grabber { x, target, shm: None, no_shm: !has_shm, redirected: false, pixmap, named: false, swap };
        if let Target::Window(w) = target {
            let has_composite = g
                .x
                .conn
                .extension_information(x11rb::protocol::composite::X11_EXTENSION_NAME)
                .ok()
                .flatten()
                .is_some();
            if has_composite {
                let _ = g.x.conn.composite_query_version(0, 4).map(|c| c.reply());
                g.redirected = g
                    .x
                    .conn
                    .composite_redirect_window(w, Redirect::AUTOMATIC)
                    .ok()
                    .and_then(|c| c.check().ok())
                    .is_some();
            }
            if !g.redirected {
                eprintln!("Capture: window {w:#x} could not be redirected (no Composite?); reading it as it shows on screen.");
            }
        }
        Ok(g)
    }

    pub fn uses_shm(&self) -> bool {
        !self.no_shm
    }

    /// The target's rectangle on the root now (for input), or None when the window is gone.
    pub fn rect(&self) -> Option<(i32, i32, u32, u32)> {
        match self.target {
            Target::Desktop => Some(desktop_rect(&self.x)),
            Target::Window(w) => windows::geometry(&self.x, w),
        }
    }

    pub fn grab(&mut self) -> Grab {
        let (drawable, sx, sy, w, h) = match self.target {
            Target::Desktop => {
                let (x, y, w, h) = desktop_rect(&self.x);
                (self.x.root, x, y, w, h)
            }
            Target::Window(win) => {
                let Ok(Ok(g)) = self.x.conn.get_geometry(win).map(|c| c.reply()) else { return Grab::Gone };
                if !windows::is_viewable(&self.x, win) {
                    return Grab::Hidden;
                }
                let drawable = if self.redirected {
                    if self.named {
                        let _ = self.x.conn.free_pixmap(self.pixmap);
                        self.named = false;
                    }
                    match self.x.conn.composite_name_window_pixmap(win, self.pixmap).map(|c| c.check()) {
                        Ok(Ok(())) => {
                            self.named = true;
                            self.pixmap
                        }
                        _ => return Grab::Hidden,
                    }
                } else {
                    win
                };
                (drawable, 0, 0, g.width as u32, g.height as u32)
            }
        };
        if w == 0 || h == 0 {
            return Grab::Hidden;
        }
        match self.read(drawable, sx, sy, w, h) {
            Some(data) => Grab::Frame(Frame { width: w, height: h, data }),
            None => Grab::Hidden,
        }
    }

    fn read(&mut self, drawable: u32, sx: i32, sy: i32, w: u32, h: u32) -> Option<Vec<u8>> {
        let size = (w as usize) * (h as usize) * 4;
        if !self.no_shm {
            if self.shm.as_ref().is_none_or(|s| s.size < size) {
                if let Some(old) = self.shm.take() {
                    old.free(&self.x);
                }
                // Room to grow a little without a new segment for every resize.
                self.shm = Shm::new(&self.x, size + size / 4);
                if self.shm.is_none() {
                    eprintln!("Capture: MIT-SHM unavailable; using plain GetImage (slower).");
                    self.no_shm = true;
                }
            }
            if let Some(shm) = &self.shm {
                let reply = self
                    .x
                    .conn
                    .shm_get_image(drawable, sx as i16, sy as i16, w as u16, h as u16, !0, ImageFormat::Z_PIXMAP.into(), shm.seg, 0)
                    .ok()?
                    .reply()
                    .ok()?;
                if reply.depth < 24 {
                    return None;
                }
                let mut data = unsafe { std::slice::from_raw_parts(shm.addr, size) }.to_vec();
                self.fix_order(&mut data);
                return Some(data);
            }
        }
        let reply = self
            .x
            .conn
            .get_image(ImageFormat::Z_PIXMAP, drawable, sx as i16, sy as i16, w as u16, h as u16, !0)
            .ok()?
            .reply()
            .ok()?;
        if reply.depth < 24 || reply.data.len() < size {
            return None;
        }
        let mut data = reply.data;
        data.truncate(size);
        self.fix_order(&mut data);
        Some(data)
    }

    /// A big-endian server sends XRGB; turn it into BGRX.
    fn fix_order(&self, data: &mut [u8]) {
        if self.swap {
            for px in data.chunks_exact_mut(4) {
                px.reverse();
            }
        }
    }
}

impl Drop for Grabber {
    fn drop(&mut self) {
        if self.named {
            let _ = self.x.conn.free_pixmap(self.pixmap);
        }
        if let (true, Target::Window(w)) = (self.redirected, self.target) {
            let _ = self.x.conn.composite_unredirect_window(w, Redirect::AUTOMATIC);
        }
        if let Some(shm) = self.shm.take() {
            shm.free(&self.x);
        }
        let _ = self.x.conn.flush();
    }
}

/// One picture of a window from its own pixmap (thumbnails, every 2 s for every window while a
/// device is connected). The window is redirected once, on `x`'s connection, and stays so until it
/// is destroyed or the host ends: redirecting and unredirecting on every read would make the app
/// repaint each time. `redirected` remembers which.
pub fn window_picture(x: &X, w: Window, redirected: &std::sync::Mutex<std::collections::HashSet<Window>>) -> Option<Frame> {
    let g = x.conn.get_geometry(w).ok()?.reply().ok()?;
    if !windows::is_viewable(x, w) || g.width == 0 || g.height == 0 {
        return None;
    }
    let pixmap = x.conn.generate_id().ok()?;
    let mut set = redirected.lock().unwrap();
    if set.len() > 4096 {
        set.clear(); // windows come and go; a redirect of a destroyed window is gone with it
    }
    let named = |x: &X| x.conn.composite_name_window_pixmap(w, pixmap).ok().and_then(|c| c.check().ok()).is_some();
    let ok = if set.contains(&w) && named(x) {
        true
    } else {
        let _ = x.conn.composite_redirect_window(w, Redirect::AUTOMATIC).map(|c| c.check());
        set.insert(w);
        named(x)
    };
    drop(set);
    let drawable = if ok { pixmap } else { w };
    let reply = x
        .conn
        .get_image(ImageFormat::Z_PIXMAP, drawable, 0, 0, g.width, g.height, !0)
        .ok()
        .and_then(|c| c.reply().ok());
    if ok {
        let _ = x.conn.free_pixmap(pixmap);
    }
    let reply = reply?;
    let size = g.width as usize * g.height as usize * 4;
    if reply.depth < 24 || reply.data.len() < size {
        return None;
    }
    let mut data = reply.data;
    data.truncate(size);
    if x.conn.setup().image_byte_order != ImageOrder::LSB_FIRST {
        for px in data.chunks_exact_mut(4) {
            px.reverse();
        }
    }
    Some(Frame { width: g.width as u32, height: g.height as u32, data })
}

/// One picture of a window or the desktop, on its own connection's terms.
pub fn snapshot(x: &Arc<X>, target: Target) -> Option<Frame> {
    let mut g = Grabber::new(x.clone(), target).ok()?;
    g.no_shm = true; // one read: a segment is not worth it
    match g.grab() {
        Grab::Frame(f) => Some(f),
        _ => None,
    }
}
