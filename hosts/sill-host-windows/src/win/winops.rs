//! Doing things to a window: bringing it forward with the keyboard, resizing it, and the
//! thumbnail menu's close, minimize and full screen.
//!
//! Everything that reaches into another process's window is asynchronous (ShowWindowAsync,
//! SetWindowPos with SWP_ASYNCWINDOWPOS, PostMessage), so a hung app never blocks the host.

use std::time::{Duration, Instant};

use sill_host_core::platform::WindowCommand;
use windows::Win32::Foundation::{HWND, LPARAM, RECT, WPARAM};
use windows::Win32::System::Threading::{AttachThreadInput, GetCurrentThreadId};
use windows::Win32::UI::WindowsAndMessaging::{
    BringWindowToTop, GetForegroundWindow, GetWindowRect, GetWindowThreadProcessId, IsIconic, IsZoomed, PostMessageW,
    SetForegroundWindow, SetWindowPos, ShowWindowAsync, SC_CLOSE, SC_MAXIMIZE, SC_MINIMIZE, SC_RESTORE,
    SWP_ASYNCWINDOWPOS, SWP_NOACTIVATE, SWP_NOMOVE, SWP_NOOWNERZORDER, SWP_NOZORDER, SW_RESTORE, WM_SYSCOMMAND,
};

use windows::Win32::UI::HiDpi::GetDpiForWindow;

use super::catalog;

fn size(r: &RECT) -> (i32, i32) {
    (r.right - r.left, r.bottom - r.top)
}

/// Brings a window forward and gives it the keyboard. Windows lets only the process with the last
/// input event take the foreground, so: a do-nothing input event first, then the window; if
/// another app still holds the foreground, its thread's input is joined to this one's for the
/// call (the usual AttachThreadInput way). `may_nudge` is false while Sill holds Alt down.
pub fn raise(hwnd: HWND, may_nudge: bool) {
    unsafe {
        if IsIconic(hwnd).as_bool() {
            let _ = ShowWindowAsync(hwnd, SW_RESTORE);
        }
        if GetForegroundWindow() == hwnd {
            return;
        }
        if may_nudge {
            super::input::nudge_foreground_lock();
        }
        if SetForegroundWindow(hwnd).as_bool() && GetForegroundWindow() == hwnd {
            return;
        }
        let foreground = GetForegroundWindow();
        let theirs = GetWindowThreadProcessId(foreground, None);
        let ours = GetCurrentThreadId();
        let attached = theirs != 0 && theirs != ours && AttachThreadInput(ours, theirs, true).as_bool();
        let _ = BringWindowToTop(hwnd);
        let _ = SetForegroundWindow(hwnd);
        if attached {
            let _ = AttachThreadInput(ours, theirs, false);
        }
        if GetForegroundWindow() != hwnd {
            super::util::log_once(
                "raise-refused",
                "Windows kept another window in front (its foreground lock); the picked window is \
                 streamed but may not have the keyboard until clicked.",
            );
        }
    }
}

/// Resizes a window so its visible frame is `width`×`height` logical points (platform.rs: the
/// core passes points; × the window's DPI ÷ 96 makes physical pixels), its top-left corner where
/// it was; returns the visible size it took (apps have minimum sizes) in points again, once it
/// settles, at most half a second later.
pub fn resize(hwnd: HWND, width: u32, height: u32) -> Option<(u32, u32)> {
    let scale = unsafe { GetDpiForWindow(hwnd) }.max(96) as f64 / 96.0;
    let (pw, ph) = resize_pixels(hwnd, (width as f64 * scale).round() as u32, (height as f64 * scale).round() as u32)?;
    Some(((pw as f64 / scale).round() as u32, (ph as f64 / scale).round() as u32))
}

fn resize_pixels(hwnd: HWND, width: u32, height: u32) -> Option<(u32, u32)> {
    unsafe {
        if IsZoomed(hwnd).as_bool() {
            let _ = ShowWindowAsync(hwnd, SW_RESTORE);
            std::thread::sleep(Duration::from_millis(60));
        }
        let visible = catalog::frame_bounds(hwnd)?;
        let mut outer = RECT::default();
        GetWindowRect(hwnd, &mut outer).ok()?;
        // The invisible resize borders the window rectangle has beyond the visible frame.
        let (border_w, border_h) = (size(&outer).0 - size(&visible).0, size(&outer).1 - size(&visible).1);
        let target = (width as i32, height as i32);
        if size(&visible) == target {
            return Some((width, height));
        }
        SetWindowPos(
            hwnd,
            None,
            0,
            0,
            target.0 + border_w.max(0),
            target.1 + border_h.max(0),
            SWP_NOMOVE | SWP_NOZORDER | SWP_NOOWNERZORDER | SWP_NOACTIVATE | SWP_ASYNCWINDOWPOS,
        )
        .ok()?;
        // Wait for the app to take it: the size reaching the target, or holding still for 100 ms.
        let start = Instant::now();
        let mut last = size(&visible);
        let mut still_since = Instant::now();
        let mut changed = false;
        while start.elapsed() < Duration::from_millis(500) {
            std::thread::sleep(Duration::from_millis(20));
            let now = size(&catalog::frame_bounds(hwnd)?);
            if now == target {
                last = now;
                break;
            }
            if now != last {
                last = now;
                changed = true;
                still_since = Instant::now();
            } else if changed && still_since.elapsed() >= Duration::from_millis(100) {
                break;
            }
        }
        Some((last.0.max(0) as u32, last.1.max(0) as u32))
    }
}

/// The thumbnail menu's commands, as the title bar's own buttons do them (WM_SYSCOMMAND, so an
/// app that asks "Save changes?" still asks).
pub fn command(hwnd: HWND, command: WindowCommand) {
    let sc = match command {
        WindowCommand::Close => SC_CLOSE,
        WindowCommand::Minimize => SC_MINIMIZE,
        WindowCommand::FullScreen => {
            if unsafe { IsZoomed(hwnd).as_bool() } {
                SC_RESTORE
            } else {
                SC_MAXIMIZE
            }
        }
    };
    unsafe {
        let _ = PostMessageW(Some(hwnd), WM_SYSCOMMAND, WPARAM(sc as usize), LPARAM(0));
    }
}
