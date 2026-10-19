//! Small helpers every Windows module uses: wide strings, COM on the calling thread, a wrapper that
//! lets free-threaded COM objects cross threads, and logging.

use std::ffi::c_void;

use windows::core::PCWSTR;
use windows::Win32::Foundation::{HWND, RPC_E_CHANGED_MODE};
use windows::Win32::System::Com::{CoInitializeEx, COINIT_MULTITHREADED};

/// A NUL-terminated UTF-16 copy of `s`, for PCWSTR parameters. Keep it alive while the pointer
/// is used.
pub fn wide(s: &str) -> Vec<u16> {
    s.encode_utf16().chain(std::iter::once(0)).collect()
}

/// A PCWSTR into a buffer from `wide`.
pub fn pcwstr(buf: &[u16]) -> PCWSTR {
    PCWSTR(buf.as_ptr())
}

/// A UTF-16 buffer up to its first NUL (or all of it) as a String.
pub fn from_wide(buf: &[u16]) -> String {
    let end = buf.iter().position(|&c| c == 0).unwrap_or(buf.len());
    String::from_utf16_lossy(&buf[..end])
}

/// Joins the calling thread to the multithreaded apartment (COM and WinRT), once per thread. A
/// thread that is already in a single-threaded apartment (RPC_E_CHANGED_MODE) keeps it: COM still
/// works there. Never uninitialised: the core's threads live as long as the process.
pub fn com_init() {
    thread_local! {
        static DONE: std::cell::Cell<bool> = const { std::cell::Cell::new(false) };
    }
    DONE.with(|done| {
        if done.get() {
            return;
        }
        let hr = unsafe { CoInitializeEx(None, COINIT_MULTITHREADED) };
        if hr.is_err() && hr != RPC_E_CHANGED_MODE {
            log(&format!("COM: CoInitializeEx failed on this thread: {hr:?}"));
        }
        done.set(true);
    });
}

/// A COM object Media Foundation, Direct3D 11 (with multithread protection on) or the shell
/// makes free-threaded in the MTA, moved or shared across threads. windows-rs marks only agile
/// WinRT types Send and Sync; these are used from the threads that made them or under a lock.
pub struct Shared<T>(pub T);
unsafe impl<T> Send for Shared<T> {}
unsafe impl<T> Sync for Shared<T> {}

impl<T> std::ops::Deref for Shared<T> {
    type Target = T;
    fn deref(&self) -> &T {
        &self.0
    }
}

/// A window's ID on the wire: its handle's value truncated to 32 bits. Windows keeps window
/// handles 32-bit significant (WOW64 shares them), so this is unique while the window lives.
pub fn window_id(hwnd: HWND) -> u32 {
    hwnd.0 as usize as u32
}

/// The handle for a wire ID: sign-extended back, as Microsoft documents for 32-bit handles in a
/// 64-bit process. The caller checks it is still a window (IsWindow).
pub fn hwnd_from_id(id: u32) -> HWND {
    HWND(id as i32 as isize as *mut c_void)
}

/// One line in the host's log (the core's: stdout, flushed), prefixed. The backend's lines are few
/// (a stream's start and end, the encoder it chose, failures).
pub fn log(line: &str) {
    sill_host_core::log(&format!("Windows: {line}"));
}

/// Logs a failure once per `key` for the process's life (a blocked SendInput, a missing API), so a
/// repeated failure does not flood the log.
pub fn log_once(key: &str, line: &str) {
    use std::collections::HashSet;
    use std::sync::{Mutex, OnceLock};
    static SEEN: OnceLock<Mutex<HashSet<String>>> = OnceLock::new();
    let seen = SEEN.get_or_init(|| Mutex::new(HashSet::new()));
    if seen.lock().map(|mut s| s.insert(key.to_string())).unwrap_or(false) {
        log(line);
    }
}
