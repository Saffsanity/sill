//! Which windows a device may pick, and what app each belongs to: the windows Alt-Tab shows,
//! front to back, without minimized ones (they show nothing to stream, as a Mac's minimized
//! windows are off the Mac's list) and without this process's own.
//!
//! The Mac's WindowCatalog is the reference: real app windows over 100×100, a title, an app name
//! and an app ID that keys the app's icon.

use std::collections::HashMap;
use std::ffi::c_void;
use std::sync::{Mutex, OnceLock};

use windows::core::{BOOL, PWSTR};
use windows::Win32::Foundation::{CloseHandle, HANDLE, HWND, LPARAM, RECT};
use windows::Win32::Graphics::Dwm::{DwmGetWindowAttribute, DWMWA_CLOAKED, DWMWA_EXTENDED_FRAME_BOUNDS};
use windows::Win32::Storage::FileSystem::{GetFileVersionInfoSizeW, GetFileVersionInfoW, VerQueryValueW};
use windows::Win32::Storage::Packaging::Appx::GetApplicationUserModelId;
use windows::Win32::System::Console::GetConsoleWindow;
use windows::Win32::System::Threading::{
    GetCurrentProcessId, OpenProcess, QueryFullProcessImageNameW, PROCESS_NAME_WIN32,
    PROCESS_QUERY_LIMITED_INFORMATION,
};
use windows::Win32::UI::WindowsAndMessaging::{
    EnumChildWindows, EnumWindows, GetClassNameW, GetWindow, GetWindowLongPtrW, GetWindowRect,
    GetWindowTextLengthW, GetWindowTextW, GetWindowThreadProcessId, IsIconic, IsWindow, IsWindowVisible,
    GWL_EXSTYLE, GW_OWNER, WS_EX_APPWINDOW, WS_EX_NOACTIVATE, WS_EX_TOOLWINDOW,
};

use super::util::{from_wide, window_id};

/// The smallest window listed, each way (the Mac's 100 pt).
const MIN_SIZE: i32 = 100;

/// One listed window, with what the backend needs beyond the wire's WindowInfo.
#[derive(Clone, Debug)]
pub struct Listed {
    pub id: u32,
    pub title: String,
    pub app_name: String,
    pub app_id: String,
    pub bounds: RECT,
}

/// The visible top-level windows a device may pick, front to back (EnumWindows' Z order).
pub fn list() -> Vec<Listed> {
    let mut handles: Vec<HWND> = Vec::new();
    unsafe {
        let _ = EnumWindows(Some(collect), LPARAM(&mut handles as *mut Vec<HWND> as isize));
    }
    let own_pid = unsafe { GetCurrentProcessId() };
    let console = unsafe { GetConsoleWindow() };
    handles
        .into_iter()
        .filter(|h| *h != console)
        .filter_map(|hwnd| describe(hwnd, own_pid))
        .collect()
}

/// The window a device names, only if it is one the list would show (never this process's own,
/// a tool window or a hidden one: a device may send any ID).
pub fn listed(id: u32) -> Option<HWND> {
    let hwnd = super::util::hwnd_from_id(id);
    if id == 0 || !is_window(hwnd) || hwnd == unsafe { GetConsoleWindow() } {
        return None;
    }
    describe(hwnd, unsafe { GetCurrentProcessId() }).map(|_| hwnd)
}

unsafe extern "system" fn collect(hwnd: HWND, lparam: LPARAM) -> BOOL {
    let out = unsafe { &mut *(lparam.0 as *mut Vec<HWND>) };
    out.push(hwnd);
    BOOL(1)
}

/// The window as listed, if Alt-Tab would show it.
fn describe(hwnd: HWND, own_pid: u32) -> Option<Listed> {
    unsafe {
        if !IsWindowVisible(hwnd).as_bool() || IsIconic(hwnd).as_bool() {
            return None;
        }
        if GetWindow(hwnd, GW_OWNER).is_ok_and(|owner| !owner.is_invalid()) {
            return None;
        }
        let ex = GetWindowLongPtrW(hwnd, GWL_EXSTYLE) as u32;
        let app_window = ex & WS_EX_APPWINDOW.0 != 0;
        if !app_window && (ex & WS_EX_TOOLWINDOW.0 != 0 || ex & WS_EX_NOACTIVATE.0 != 0) {
            return None;
        }
        if is_cloaked(hwnd) {
            return None;
        }
        let class = class_name(hwnd);
        if matches!(class.as_str(), "Progman" | "WorkerW" | "Shell_TrayWnd" | "Shell_SecondaryTrayWnd") {
            return None;
        }
        let title = title(hwnd);
        if title.trim().is_empty() {
            return None;
        }
        let bounds = frame_bounds(hwnd)?;
        if bounds.right - bounds.left < MIN_SIZE || bounds.bottom - bounds.top < MIN_SIZE {
            return None;
        }
        let mut pid = 0u32;
        GetWindowThreadProcessId(hwnd, Some(&mut pid));
        if pid == own_pid || pid == 0 {
            return None;
        }
        // A UWP app's frame belongs to ApplicationFrameHost; its content (a CoreWindow child)
        // belongs to the app. A suspended app's frame may have none: then the frame's own process.
        let app_pid = if class == "ApplicationFrameWindow" { uwp_child_pid(hwnd, pid).unwrap_or(pid) } else { pid };
        let app = app_info(app_pid).unwrap_or_else(|| AppInfo { name: title.clone(), id: format!("pid:{app_pid}") });
        let id = window_id(hwnd);
        if id == 0 {
            return None;
        }
        Some(Listed { id, title, app_name: app.name, app_id: app.id, bounds })
    }
}

/// Whether DWM hides the window (another virtual desktop, a suspended UWP app, a shell surface).
pub fn is_cloaked(hwnd: HWND) -> bool {
    let mut cloaked: u32 = 0;
    unsafe {
        DwmGetWindowAttribute(hwnd, DWMWA_CLOAKED, &mut cloaked as *mut u32 as *mut c_void, 4).is_ok() && cloaked != 0
    }
}

/// The window's visible rectangle (without the invisible resize borders), physical pixels.
pub fn frame_bounds(hwnd: HWND) -> Option<RECT> {
    let mut rect = RECT::default();
    unsafe {
        if DwmGetWindowAttribute(
            hwnd,
            DWMWA_EXTENDED_FRAME_BOUNDS,
            &mut rect as *mut RECT as *mut c_void,
            std::mem::size_of::<RECT>() as u32,
        )
        .is_err()
        {
            GetWindowRect(hwnd, &mut rect).ok()?;
        }
    }
    (rect.right > rect.left && rect.bottom > rect.top).then_some(rect)
}

pub fn is_window(hwnd: HWND) -> bool {
    unsafe { IsWindow(Some(hwnd)).as_bool() }
}

pub fn title(hwnd: HWND) -> String {
    unsafe {
        let len = GetWindowTextLengthW(hwnd);
        if len <= 0 {
            return String::new();
        }
        let mut buf = vec![0u16; len as usize + 1];
        let n = GetWindowTextW(hwnd, &mut buf);
        from_wide(&buf[..n.max(0) as usize])
    }
}

pub fn class_name(hwnd: HWND) -> String {
    let mut buf = [0u16; 256];
    let n = unsafe { GetClassNameW(hwnd, &mut buf) };
    from_wide(&buf[..n.max(0) as usize])
}

fn uwp_child_pid(frame: HWND, frame_pid: u32) -> Option<u32> {
    struct Search {
        frame_pid: u32,
        found: Option<u32>,
    }
    unsafe extern "system" fn visit(child: HWND, lparam: LPARAM) -> BOOL {
        let search = unsafe { &mut *(lparam.0 as *mut Search) };
        let mut pid = 0u32;
        unsafe { GetWindowThreadProcessId(child, Some(&mut pid)) };
        if pid != 0 && pid != search.frame_pid && class_name(child) == "Windows.UI.Core.CoreWindow" {
            search.found = Some(pid);
            return BOOL(0);
        }
        BOOL(1)
    }
    let mut search = Search { frame_pid, found: None };
    unsafe {
        let _ = EnumChildWindows(Some(frame), Some(visit), LPARAM(&mut search as *mut Search as isize));
    }
    search.found
}

/// An app as the catalog names it.
#[derive(Clone, Debug)]
pub struct AppInfo {
    pub name: String,
    /// The AppUserModelID of a packaged app, else the executable's full path.
    pub id: String,
}

/// The app a process runs: its package's AppUserModelID and display name, or its executable's
/// path and FileDescription (else the file's name).
pub fn app_info(pid: u32) -> Option<AppInfo> {
    let process = Process::open(pid)?;
    let path = process.image_path();
    if let Some(aumid) = process.aumid() {
        let name = super::apps::packaged_display_name(&aumid)
            .or_else(|| path.as_deref().and_then(exe_display_name))
            .unwrap_or_else(|| aumid.clone());
        return Some(AppInfo { name, id: aumid });
    }
    let path = path?;
    let name = exe_display_name(&path).unwrap_or_else(|| file_stem(&path));
    Some(AppInfo { name, id: path })
}

/// The executable's own name for itself (its version resource's FileDescription), cached by path.
pub fn exe_display_name(path: &str) -> Option<String> {
    static CACHE: OnceLock<Mutex<HashMap<String, Option<String>>>> = OnceLock::new();
    let cache = CACHE.get_or_init(|| Mutex::new(HashMap::new()));
    if let Some(hit) = cache.lock().ok()?.get(path) {
        return hit.clone();
    }
    let name = file_description(path);
    if let Ok(mut c) = cache.lock() {
        c.insert(path.to_string(), name.clone());
    }
    name
}

pub fn file_stem(path: &str) -> String {
    std::path::Path::new(path)
        .file_stem()
        .map(|s| s.to_string_lossy().into_owned())
        .unwrap_or_else(|| path.to_string())
}

fn file_description(path: &str) -> Option<String> {
    let wpath = super::util::wide(path);
    unsafe {
        let size = GetFileVersionInfoSizeW(super::util::pcwstr(&wpath), None);
        if size == 0 {
            return None;
        }
        let mut data = vec![0u8; size as usize];
        GetFileVersionInfoW(super::util::pcwstr(&wpath), None, size, data.as_mut_ptr() as *mut c_void).ok()?;
        // The first language and code page the resource lists.
        let mut ptr: *mut c_void = std::ptr::null_mut();
        let mut len: u32 = 0;
        let query = super::util::wide("\\VarFileInfo\\Translation");
        let mut lang_cp = (0x0409u16, 0x04B0u16);
        if VerQueryValueW(data.as_ptr() as *const c_void, super::util::pcwstr(&query), &mut ptr, &mut len).as_bool()
            && len >= 4
            && !ptr.is_null()
        {
            let pair = ptr as *const u16;
            lang_cp = (*pair, *pair.add(1));
        }
        let query = super::util::wide(&format!(
            "\\StringFileInfo\\{:04x}{:04x}\\FileDescription",
            lang_cp.0, lang_cp.1
        ));
        if !VerQueryValueW(data.as_ptr() as *const c_void, super::util::pcwstr(&query), &mut ptr, &mut len).as_bool()
            || ptr.is_null()
            || len == 0
        {
            return None;
        }
        let text = std::slice::from_raw_parts(ptr as *const u16, len as usize);
        let name = from_wide(text).trim().to_string();
        (!name.is_empty()).then_some(name)
    }
}

/// A process opened for queries only.
struct Process(HANDLE);

impl Process {
    fn open(pid: u32) -> Option<Self> {
        unsafe { OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid).ok().map(Process) }
    }

    fn image_path(&self) -> Option<String> {
        let mut buf = vec![0u16; 1024];
        let mut len = buf.len() as u32;
        unsafe {
            QueryFullProcessImageNameW(self.0, PROCESS_NAME_WIN32, PWSTR(buf.as_mut_ptr()), &mut len).ok()?;
        }
        Some(String::from_utf16_lossy(&buf[..len as usize]))
    }

    fn aumid(&self) -> Option<String> {
        let mut buf = vec![0u16; 512];
        let mut len = buf.len() as u32;
        let status = unsafe { GetApplicationUserModelId(self.0, &mut len, Some(PWSTR(buf.as_mut_ptr()))) };
        if status.0 != 0 {
            return None;
        }
        let s = from_wide(&buf[..(len as usize).min(buf.len())]);
        (!s.is_empty()).then_some(s)
    }
}

impl Drop for Process {
    fn drop(&mut self) {
        unsafe {
            let _ = CloseHandle(self.0);
        }
    }
}
