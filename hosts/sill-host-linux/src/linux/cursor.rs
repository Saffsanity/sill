//! The pointer's shape (CursorShapeWatcher.swift is the Mac's): XFixes tells this connection when the
//! displayed cursor changes (CursorNotify), and GetCursorImage gives it as premultiplied ARGB with its
//! hotspot; it goes to the device as a straight-alpha RGBA PNG. The X cursor is not in the captured
//! pictures (GetImage never includes it), so the device draws this one.

use std::io::Cursor;

use sill_host_core::platform::CursorShape;
use x11rb::connection::{Connection, RequestConnection};
use x11rb::protocol::xfixes::{ConnectionExt as _, CursorNotifyMask};
use x11rb::protocol::Event;

use super::x::X;

pub struct CursorWatch {
    serial: Option<u32>,
    enabled: bool,
}

impl CursorWatch {
    /// Asks the server for cursor notifications on `x`'s connection (whose events the caller polls).
    pub fn new(x: &X) -> CursorWatch {
        let has = x.conn.extension_information(x11rb::protocol::xfixes::X11_EXTENSION_NAME).ok().flatten().is_some();
        let enabled = has
            && x.conn.xfixes_query_version(5, 0).ok().and_then(|c| c.reply().ok()).is_some()
            && x
                .conn
                .xfixes_select_cursor_input(x.root, CursorNotifyMask::DISPLAY_CURSOR)
                .ok()
                .and_then(|c| c.check().ok())
                .is_some();
        if !enabled {
            eprintln!("Cursor: XFixes unavailable; the device draws its default arrow.");
        }
        CursorWatch { serial: None, enabled }
    }

    /// Drains `x`'s events; the shape when it changed since the last call (the first call always
    /// gives one).
    pub fn poll(&mut self, x: &X) -> Option<CursorShape> {
        let mut changed = self.serial.is_none();
        while let Ok(Some(event)) = x.conn.poll_for_event() {
            if let Event::XfixesCursorNotify(n) = event {
                if Some(n.cursor_serial) != self.serial {
                    changed = true;
                }
            }
        }
        if !self.enabled || !changed {
            return None;
        }
        let image = x.conn.xfixes_get_cursor_image().ok()?.reply().ok()?;
        if Some(image.cursor_serial) == self.serial {
            return None;
        }
        self.serial = Some(image.cursor_serial);
        let (w, h) = (image.width as u32, image.height as u32);
        if w == 0 || h == 0 || image.cursor_image.len() < (w * h) as usize {
            return None;
        }
        let png = png_from_argb(w, h, &image.cursor_image, true)?;
        Some(CursorShape { png, hotspot_x: image.xhot as f64, hotspot_y: image.yhot as f64, width: w as f64, height: h as f64 })
    }
}

/// ARGB pixels (one u32 each, alpha in the top byte) as an RGBA PNG; `premultiplied` undoes XFixes'
/// premultiplied alpha (an icon's _NET_WM_ICON is straight).
pub fn png_from_argb(w: u32, h: u32, argb: &[u32], premultiplied: bool) -> Option<Vec<u8>> {
    let mut rgba = Vec::with_capacity((w * h * 4) as usize);
    for &p in &argb[..(w * h) as usize] {
        let a = (p >> 24) & 0xff;
        let mut c = [(p >> 16) & 0xff, (p >> 8) & 0xff, p & 0xff];
        if premultiplied && a > 0 && a < 255 {
            for v in &mut c {
                *v = (*v * 255 / a).min(255);
            }
        }
        rgba.extend_from_slice(&[c[0] as u8, c[1] as u8, c[2] as u8, a as u8]);
    }
    let img = image::RgbaImage::from_raw(w, h, rgba)?;
    let mut out = Cursor::new(Vec::new());
    img.write_to(&mut out, image::ImageFormat::Png).ok()?;
    Some(out.into_inner())
}
