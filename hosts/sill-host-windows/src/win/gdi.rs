//! GDI bitmaps as bytes: a window drawn by PrintWindow (thumbnails), the shell's icon bitmaps,
//! and the cursor's colour and mask bitmaps.

use std::ffi::c_void;

use windows::Win32::Foundation::HWND;
use windows::Win32::Graphics::Gdi::{
    CreateCompatibleDC, CreateDIBSection, DeleteDC, DeleteObject, GetDC, GetDIBits, GetObjectW, ReleaseDC,
    SelectObject, BITMAP, BITMAPINFO, BITMAPINFOHEADER, BI_RGB, DIB_RGB_COLORS, HBITMAP, HGDIOBJ, RGBQUAD,
};
use windows::Win32::Storage::Xps::{PrintWindow, PRINT_WINDOW_FLAGS};
use windows::Win32::UI::WindowsAndMessaging::{GetWindowRect, IsHungAppWindow};

use crate::imaging::{self, Bgra};

/// Pixels read from a bitmap: top-down rows of `stride` bytes.
pub struct Bits {
    pub width: u32,
    pub height: u32,
    pub stride: usize,
    pub data: Vec<u8>,
}

impl Bits {
    pub fn bgra(&self) -> Bgra<'_> {
        Bgra { width: self.width, height: self.height, stride: self.stride, data: &self.data }
    }
}

/// A bitmap's size.
pub fn bitmap_size(hbm: HBITMAP) -> Option<(u32, u32)> {
    let mut bm = BITMAP::default();
    let n = unsafe {
        GetObjectW(HGDIOBJ(hbm.0), std::mem::size_of::<BITMAP>() as i32, Some(&mut bm as *mut BITMAP as *mut c_void))
    };
    (n != 0 && bm.bmWidth > 0 && bm.bmHeight != 0).then_some((bm.bmWidth as u32, bm.bmHeight.unsigned_abs()))
}

/// A bitmap's pixels at 32 bits (BGRA) or 1 bit (a mask), top-down.
pub fn read_bitmap(hbm: HBITMAP, bits_per_pixel: u16) -> Option<Bits> {
    let (width, height) = bitmap_size(hbm)?;
    let stride = if bits_per_pixel == 32 { width as usize * 4 } else { imaging::mask_stride(width) };
    let mut data = vec![0u8; stride * height as usize];
    // BITMAPINFO with room for a 1-bit bitmap's two colours.
    #[repr(C)]
    struct Info {
        header: BITMAPINFOHEADER,
        colors: [RGBQUAD; 2],
    }
    let mut info = Info {
        header: BITMAPINFOHEADER {
            biSize: std::mem::size_of::<BITMAPINFOHEADER>() as u32,
            biWidth: width as i32,
            biHeight: -(height as i32), // top-down
            biPlanes: 1,
            biBitCount: bits_per_pixel,
            biCompression: BI_RGB.0,
            ..Default::default()
        },
        colors: [RGBQUAD::default(); 2],
    };
    unsafe {
        let screen = GetDC(None);
        let lines = GetDIBits(
            screen,
            hbm,
            0,
            height,
            Some(data.as_mut_ptr() as *mut c_void),
            &mut info as *mut Info as *mut BITMAPINFO,
            DIB_RGB_COLORS,
        );
        ReleaseDC(None, screen);
        if lines == 0 {
            return None;
        }
    }
    Some(Bits { width, height, stride, data })
}

/// Deletes a bitmap the caller owns.
pub fn delete_bitmap(hbm: HBITMAP) {
    if !hbm.is_invalid() {
        unsafe {
            let _ = DeleteObject(HGDIOBJ(hbm.0));
        }
    }
}

/// The window as it looks, drawn by DWM through PrintWindow(PW_RENDERFULLCONTENT), cropped to
/// `visible` (its frame bounds; the window rectangle includes invisible resize borders). None for
/// a hung window (PrintWindow would wait on it) and for one that draws nothing.
pub fn print_window(hwnd: HWND, visible: windows::Win32::Foundation::RECT) -> Option<Bits> {
    const PW_RENDERFULLCONTENT: u32 = 2;
    const MAX_SIDE: i32 = 8192;
    unsafe {
        if IsHungAppWindow(hwnd).as_bool() {
            return None;
        }
        let mut wr = Default::default();
        GetWindowRect(hwnd, &mut wr).ok()?;
        let (w, h) = (wr.right - wr.left, wr.bottom - wr.top);
        if w <= 0 || h <= 0 || w > MAX_SIDE || h > MAX_SIDE {
            return None;
        }
        let screen = GetDC(None);
        let dc = CreateCompatibleDC(Some(screen));
        ReleaseDC(None, screen);
        let info = BITMAPINFO {
            bmiHeader: BITMAPINFOHEADER {
                biSize: std::mem::size_of::<BITMAPINFOHEADER>() as u32,
                biWidth: w,
                biHeight: -h,
                biPlanes: 1,
                biBitCount: 32,
                biCompression: BI_RGB.0,
                ..Default::default()
            },
            ..Default::default()
        };
        let mut bits: *mut c_void = std::ptr::null_mut();
        let Ok(dib) = CreateDIBSection(Some(dc), &info, DIB_RGB_COLORS, &mut bits, None, 0) else {
            let _ = DeleteDC(dc);
            return None;
        };
        let old = SelectObject(dc, HGDIOBJ(dib.0));
        let ok = PrintWindow(hwnd, dc, PRINT_WINDOW_FLAGS(PW_RENDERFULLCONTENT)).as_bool();
        let stride = w as usize * 4;
        let mut result = None;
        if ok && !bits.is_null() {
            let all = std::slice::from_raw_parts(bits as *const u8, stride * h as usize);
            // Crop to the visible frame.
            let x0 = (visible.left - wr.left).clamp(0, w) as usize;
            let y0 = (visible.top - wr.top).clamp(0, h) as usize;
            let x1 = (visible.right - wr.left).clamp(0, w) as usize;
            let y1 = (visible.bottom - wr.top).clamp(0, h) as usize;
            if x1 > x0 && y1 > y0 {
                let cw = x1 - x0;
                let mut data = Vec::with_capacity(cw * 4 * (y1 - y0));
                for y in y0..y1 {
                    data.extend_from_slice(&all[y * stride + x0 * 4..y * stride + x1 * 4]);
                }
                // A window that drew nothing (all black and transparent) is no thumbnail.
                if data.chunks_exact(4).any(|p| p[0] | p[1] | p[2] != 0) {
                    result = Some(Bits { width: cw as u32, height: (y1 - y0) as u32, stride: cw * 4, data });
                }
            }
        }
        SelectObject(dc, old);
        let _ = DeleteObject(HGDIOBJ(dib.0));
        let _ = DeleteDC(dc);
        result
    }
}
