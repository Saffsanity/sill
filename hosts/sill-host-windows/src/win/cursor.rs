//! The PC's cursor shape, for the devices that draw the pointer themselves (it is left out of the
//! video). Polled at 20 Hz while a stream runs, as the Mac's CursorShapeWatcher does; the PNG is
//! made only when the shape changes.

use std::hash::{Hash, Hasher};

use sill_host_core::platform::CursorShape;
use windows::Win32::UI::WindowsAndMessaging::{GetCursorInfo, GetIconInfo, CURSORINFO, CURSOR_SHOWING, HICON, ICONINFO};

use super::gdi;
use crate::imaging;

#[derive(Default)]
pub struct CursorWatcher {
    last_handle: usize,
    last_hash: Option<u64>,
}

impl CursorWatcher {
    pub fn new() -> Self {
        Self::default()
    }

    /// The cursor's shape if it changed since the last call (the first call always gives it).
    /// A hidden cursor is no change: devices keep the last shape.
    pub fn poll(&mut self) -> Option<CursorShape> {
        let mut info = CURSORINFO { cbSize: std::mem::size_of::<CURSORINFO>() as u32, ..Default::default() };
        unsafe { GetCursorInfo(&mut info).ok()? };
        if info.flags.0 & CURSOR_SHOWING.0 == 0 || info.hCursor.is_invalid() {
            return None;
        }
        let handle = info.hCursor.0 as usize;
        if handle == self.last_handle && self.last_hash.is_some() {
            return None;
        }
        let (rgba, width, height, hot_x, hot_y) = read_cursor(HICON(info.hCursor.0))?;
        let mut hasher = std::collections::hash_map::DefaultHasher::new();
        (width, height, hot_x, hot_y).hash(&mut hasher);
        rgba.hash(&mut hasher);
        let hash = hasher.finish();
        self.last_handle = handle;
        if self.last_hash == Some(hash) {
            return None;
        }
        let png = imaging::png_rgba(width, height, &rgba)?;
        self.last_hash = Some(hash);
        Some(CursorShape {
            png,
            hotspot_x: hot_x as f64,
            hotspot_y: hot_y as f64,
            width: width as f64,
            height: height as f64,
        })
    }
}

/// A cursor's straight-alpha RGBA pixels, its size and hotspot, in physical pixels.
fn read_cursor(icon: HICON) -> Option<(Vec<u8>, u32, u32, u32, u32)> {
    let mut info = ICONINFO::default();
    unsafe { GetIconInfo(icon, &mut info).ok()? };
    let result = (|| {
        if !info.hbmColor.is_invalid() {
            let color = gdi::read_bitmap(info.hbmColor, 32)?;
            let mask = gdi::read_bitmap(info.hbmMask, 1);
            let rgba = imaging::cursor_from_color(color.bgra(), mask.as_ref().map(|m| m.data.as_slice()))?;
            Some((rgba, color.width, color.height, info.xHotspot, info.yHotspot))
        } else {
            let mask = gdi::read_bitmap(info.hbmMask, 1)?;
            let height = mask.height / 2;
            let rgba = imaging::cursor_from_monochrome(mask.width, height, &mask.data)?;
            Some((rgba, mask.width, height, info.xHotspot, info.yHotspot))
        }
    })();
    gdi::delete_bitmap(info.hbmColor);
    gdi::delete_bitmap(info.hbmMask);
    result
}
