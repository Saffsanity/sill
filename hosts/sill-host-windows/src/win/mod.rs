//! The Windows backend: `WindowsPlatform`, the core's `Platform` for Windows 10 1903+ and 11.

pub mod apps;
pub mod capture;
pub mod catalog;
pub mod convert;
pub mod cursor;
pub mod d3d;
pub mod dnssd;
pub mod encoder;
pub mod gdi;
pub mod input;
pub mod stream;
pub mod util;
pub mod winops;

use std::sync::{Arc, Mutex};

use sill_host_core::platform::{App, Input, Platform, Stream, StreamConfig, StreamSink, Window, WindowCommand};
use windows::Win32::System::SystemInformation::{ComputerNamePhysicalDnsHostname, GetComputerNameExW};
use windows::Win32::UI::HiDpi::{SetProcessDpiAwarenessContext, DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2};

use self::apps::AppIndex;
use self::input::Injector;
use self::util::{com_init, from_wide, log};

/// Physical pixels everywhere: the window list, capture, input and the pointer all speak the same
/// units only in a per-monitor (v2) DPI-aware process. Called first thing in main.
pub fn init_process() {
    static ONCE: std::sync::Once = std::sync::Once::new();
    ONCE.call_once(|| unsafe {
        if SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2).is_err() {
            log("Could not make the process per-monitor DPI aware (already set by a manifest, or Windows before 1703)");
        }
    });
    com_init();
}

pub struct WindowsPlatform {
    injector: Mutex<Injector>,
    apps: Mutex<AppIndex>,
}

impl WindowsPlatform {
    pub fn new() -> Arc<Self> {
        init_process();
        Arc::new(WindowsPlatform { injector: Mutex::new(Injector::new()), apps: Mutex::new(AppIndex::default()) })
    }

    /// Lets go of every key and button Sill holds down (a device left; the host is ending). The
    /// core has no call for it yet (NOTES-windows.md, requests to core); main calls it at exit.
    pub fn release_input(&self) {
        if let Ok(mut i) = self.injector.lock() {
            i.release_all();
        }
    }

    fn listed_hwnd(&self, window: u32) -> Option<windows::Win32::Foundation::HWND> {
        catalog::listed(window)
    }
}

impl Platform for WindowsPlatform {
    fn machine_name(&self) -> String {
        let mut buf = vec![0u16; 256];
        let mut len = buf.len() as u32;
        let ok = unsafe {
            GetComputerNameExW(ComputerNamePhysicalDnsHostname, Some(windows::core::PWSTR(buf.as_mut_ptr())), &mut len)
                .is_ok()
        };
        if ok {
            let name = from_wide(&buf[..len as usize]);
            if !name.is_empty() {
                return name;
            }
        }
        std::env::var("COMPUTERNAME").unwrap_or_else(|_| "Windows PC".into())
    }

    fn windows(&self) -> Vec<Window> {
        com_init();
        catalog::list()
            .into_iter()
            .map(|w| Window {
                id: w.id,
                title: w.title,
                app_name: w.app_name,
                app_id: w.app_id,
                width: (w.bounds.right - w.bounds.left).max(0) as u32,
                height: (w.bounds.bottom - w.bounds.top).max(0) as u32,
            })
            .collect()
    }

    fn apps(&self) -> Vec<App> {
        let installed = apps::scan();
        if let Ok(mut index) = self.apps.lock() {
            index.replace(&installed);
        }
        installed.into_iter().map(|a| App { name: a.name, app_id: a.app_id }).collect()
    }

    fn thumbnail(&self, window: u32) -> Option<Vec<u8>> {
        let hwnd = self.listed_hwnd(window)?;
        let bounds = catalog::frame_bounds(hwnd)?;
        let bits = gdi::print_window(hwnd, bounds)?;
        crate::imaging::thumbnail_jpeg(bits.bgra())
    }

    fn icon(&self, app_id: &str) -> Option<Vec<u8>> {
        apps::icon_png(app_id)
    }

    fn start_stream(&self, config: StreamConfig, sink: Arc<dyn StreamSink>) -> Result<Box<dyn Stream>, String> {
        stream::start(config, sink)
    }

    fn inject(&self, input: Input) {
        if let Ok(mut i) = self.injector.lock() {
            i.inject(input);
        }
    }

    fn raise(&self, window: u32) {
        let Some(hwnd) = self.listed_hwnd(window) else { return };
        let may_nudge = self.injector.lock().map(|i| !i.holds_alt()).unwrap_or(false);
        winops::raise(hwnd, may_nudge);
    }

    fn resize(&self, window: u32, width: u32, height: u32) -> Option<(u32, u32)> {
        let hwnd = self.listed_hwnd(window)?;
        winops::resize(hwnd, width, height)
    }

    fn window_command(&self, window: u32, command: WindowCommand) {
        if let Some(hwnd) = self.listed_hwnd(window) {
            winops::command(hwnd, command);
        }
    }

    fn launch(&self, app_id: &str) -> Result<(), String> {
        // Only what the app list or a listed window names: an ID from a device is never run as a
        // path it made up.
        let known = self.apps.lock().map_err(|_| "app list unavailable".to_string())?.get(app_id);
        let app = match known {
            Some(app) => app,
            None => {
                let rescanned = apps::scan();
                if let Ok(mut index) = self.apps.lock() {
                    index.replace(&rescanned);
                }
                match rescanned.into_iter().find(|a| a.app_id.eq_ignore_ascii_case(app_id)) {
                    Some(app) => app,
                    None => catalog::list()
                        .into_iter()
                        .find(|w| w.app_id.eq_ignore_ascii_case(app_id))
                        .map(|w| apps::Installed {
                            name: w.app_name,
                            app_id: w.app_id.clone(),
                            launch: if apps::is_aumid(&w.app_id) {
                                format!("shell:AppsFolder\\{}", w.app_id)
                            } else {
                                w.app_id
                            },
                        })
                        .ok_or_else(|| format!("no installed app {app_id}"))?,
                }
            }
        };
        apps::launch(&app)
    }

    fn pointer_location(&self) -> Option<(f64, f64)> {
        input::pointer_location()
    }

    fn advertise(&self, instance: &str, port: u16, txt: &[(String, String)]) -> Result<Box<dyn Send>, String> {
        let host = self.machine_name();
        dnssd::advertise(instance, &host, port, txt).map(|a| Box::new(a) as Box<dyn Send>)
    }
}

impl Drop for WindowsPlatform {
    fn drop(&mut self) {
        self.release_input();
    }
}
