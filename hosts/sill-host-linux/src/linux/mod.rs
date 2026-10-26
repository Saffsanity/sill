//! The X11 backend: `LinuxPlatform` implements the core's `Platform` trait.

pub mod avahi;
pub mod capture;
pub mod cursor;
pub mod encoder;
pub mod icons;
pub mod input;
pub mod selftest;
pub mod stream;
pub mod windows;
pub mod x;

use std::collections::HashMap;
use std::process::{Command, Stdio};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use sill_host_core::platform::{App, Input, Platform, Source, Stream, StreamConfig, StreamSink, Window, WindowCommand};

use crate::desktop::{self, Index};
use x::X;

/// How long the desktop entries are trusted before they are read again (a newly installed app shows
/// up within this).
const INDEX_AGE: Duration = Duration::from_secs(30);

pub struct LinuxPlatform {
    x: Arc<X>,
    input: Mutex<input::Injector>,
    index: Mutex<Option<(Instant, Arc<Index>)>>,
    themes: Mutex<Option<Arc<icons::ThemeIndex>>>,
    icon_cache: Mutex<HashMap<String, Option<Vec<u8>>>>,
    /// Windows redirected for thumbnails on `x`'s connection (capture::window_picture).
    redirected: Mutex<std::collections::HashSet<u32>>,
    make_encoder: stream::MakeEncoder,
}

impl LinuxPlatform {
    /// Connects to $DISPLAY. `make_encoder` makes each stream's encoder (encoder.rs).
    pub fn new(make_encoder: stream::MakeEncoder) -> Result<LinuxPlatform, String> {
        let x = X::connect()?;
        let input = Mutex::new(input::Injector::new(x.clone()));
        Ok(LinuxPlatform {
            x,
            input,
            index: Mutex::new(None),
            themes: Mutex::new(None),
            icon_cache: Mutex::new(HashMap::new()),
            redirected: Mutex::new(std::collections::HashSet::new()),
            make_encoder,
        })
    }

    pub fn x(&self) -> &Arc<X> {
        &self.x
    }

    fn index(&self) -> Arc<Index> {
        let mut slot = self.index.lock().unwrap();
        if let Some((at, index)) = slot.as_ref() {
            if at.elapsed() < INDEX_AGE {
                return index.clone();
            }
        }
        let index = Arc::new(Index::new(desktop::scan(&desktop::data_dirs())));
        *slot = Some((Instant::now(), index.clone()));
        index
    }

    fn themes(&self) -> Arc<icons::ThemeIndex> {
        let mut slot = self.themes.lock().unwrap();
        slot.get_or_insert_with(|| Arc::new(icons::ThemeIndex::build(&desktop::data_dirs()))).clone()
    }

    /// A window as the protocol lists it: its app id the desktop entry's when one claims it (by
    /// WM_CLASS), else the WM_CLASS class; its app name the entry's Name, else the process's name, else
    /// the class.
    fn describe(&self, index: &Index, w: &windows::WinInfo) -> Window {
        let entry = index.for_window(&w.instance, &w.class);
        // A window without WM_CLASS (xev, some toolkits' utility windows) goes by its process's name.
        let process = w.pid.and_then(x::process_name);
        let class = [&w.class, &w.instance]
            .into_iter()
            .find(|c| !c.is_empty())
            .cloned()
            .or_else(|| process.clone())
            .unwrap_or_else(|| "X11".to_string());
        let app_id = entry.map(|e| e.id.clone()).unwrap_or_else(|| class.clone());
        let app_name = entry
            .map(|e| e.name.clone())
            .or(process)
            .unwrap_or_else(|| class.clone());
        Window { id: w.id, title: w.title.clone(), app_name, app_id, width: w.width, height: w.height }
    }

    fn icon_uncached(&self, app_id: &str) -> Option<Vec<u8>> {
        let index = self.index();
        let entry = index.by_id(app_id).or_else(|| index.for_window(app_id, app_id));
        if let Some(icon) = entry.and_then(|e| e.icon.clone()) {
            let path = std::path::Path::new(&icon);
            if path.is_absolute() {
                if let Some(png) = icons::load_png(path) {
                    return Some(png);
                }
            } else if let Some(p) = self.themes().find(&icon) {
                if let Some(png) = icons::load_png(p) {
                    return Some(png);
                }
            }
        }
        // A window of this app that draws its own icon.
        for w in windows::list(&self.x) {
            let matches = self.describe(&index, &w).app_id == app_id;
            if matches {
                if let Some((iw, ih, argb)) = windows::net_wm_icon(&self.x, w.id, icons::SIZE) {
                    if let Some(png) = icons::png_from_argb_scaled(iw, ih, &argb) {
                        return Some(png);
                    }
                }
            }
        }
        // The class's own name in a theme ("xterm", "firefox").
        self.themes().find(&app_id.to_lowercase()).and_then(icons::load_png)
    }
}

impl Platform for LinuxPlatform {
    fn machine_name(&self) -> String {
        machine_name()
    }

    fn windows(&self) -> Vec<Window> {
        let index = self.index();
        windows::list(&self.x).iter().map(|w| self.describe(&index, w)).collect()
    }

    fn apps(&self) -> Vec<App> {
        self.index().listed().map(|e| App { name: e.name.clone(), app_id: e.id.clone() }).collect()
    }

    fn thumbnail(&self, window: u32) -> Option<Vec<u8>> {
        let frame = capture::window_picture(&self.x, window, &self.redirected)?;
        // As the Mac: fitted in 208×132 (twice the device's tile), JPEG quality 0.6.
        icons::jpeg_thumbnail(frame.width, frame.height, &frame.data, 208, 132, 60)
    }

    fn icon(&self, app_id: &str) -> Option<Vec<u8>> {
        if let Some(hit) = self.icon_cache.lock().unwrap().get(app_id) {
            return hit.clone();
        }
        let png = self.icon_uncached(app_id);
        self.icon_cache.lock().unwrap().insert(app_id.to_string(), png.clone());
        png
    }

    fn start_stream(&self, config: StreamConfig, sink: Arc<dyn StreamSink>) -> Result<Box<dyn Stream>, String> {
        if let Source::Window(id) = config.source {
            if windows::geometry(&self.x, id).is_none() {
                return Err(format!("window {id:#x} is gone"));
            }
        }
        stream::start(config, sink, self.make_encoder.clone())
    }

    fn inject(&self, input: Input) {
        self.input.lock().unwrap().inject(input);
    }

    fn raise(&self, window: u32) {
        windows::raise(&self.x, window);
    }

    /// `width`×`height` are logical points (NOTES-core.md): on a HiDPI X screen (Xft.dpi above 96)
    /// they are made pixels, and the size it got is given back in points.
    fn resize(&self, window: u32, width: u32, height: u32) -> Option<(u32, u32)> {
        let s = self.x.ui_scale();
        let px = |v: u32| ((v as f64) * s).round() as u32;
        let (w, h) = windows::resize(&self.x, window, px(width), px(height))?;
        Some((((w as f64) / s).round() as u32, ((h as f64) / s).round() as u32))
    }

    fn window_command(&self, window: u32, command: WindowCommand) {
        match command {
            WindowCommand::Close => windows::close(&self.x, window),
            WindowCommand::Minimize => windows::minimize(&self.x, window),
            WindowCommand::FullScreen => windows::toggle_fullscreen(&self.x, window),
        }
    }

    fn launch(&self, app_id: &str) -> Result<(), String> {
        let index = self.index();
        let entry = index.by_id(app_id).ok_or_else(|| format!("no app {app_id:?}"))?;
        launch(entry)
    }

    fn pointer_location(&self) -> Option<(f64, f64)> {
        input::pointer(&self.x)
    }

    fn release_all_input(&self) {
        self.release_input();
    }

    fn advertise(&self, instance: &str, port: u16, txt: &[(String, String)]) -> Result<Box<dyn Send>, String> {
        let ad = avahi::advertise(instance, port, txt)?;
        if ad.name != instance {
            println!("Advertising as {:?} ({:?} is taken on this network).", ad.name, instance);
        }
        Ok(Box::new(ad))
    }
}

impl Drop for LinuxPlatform {
    fn drop(&mut self) {
        if let Ok(mut input) = self.input.lock() {
            input.release_all();
        }
    }
}

impl LinuxPlatform {
    /// Every key and button a device holds goes up (a device left, or the host is ending).
    pub fn release_input(&self) {
        self.input.lock().unwrap().release_all();
    }
}

/// The name devices list: /etc/machine-info's PRETTY_HOSTNAME (what GNOME's Settings calls the
/// device name), else the hostname.
pub fn machine_name() -> String {
    if let Ok(info) = std::fs::read_to_string("/etc/machine-info") {
        for line in info.lines() {
            if let Some(v) = line.strip_prefix("PRETTY_HOSTNAME=") {
                let v = v.trim().trim_matches('"').trim_matches('\'');
                if !v.is_empty() {
                    return v.to_string();
                }
            }
        }
    }
    let mut buf = [0u8; 256];
    let ok = unsafe { libc::gethostname(buf.as_mut_ptr() as *mut libc::c_char, buf.len()) } == 0;
    let name = if ok {
        let end = buf.iter().position(|b| *b == 0).unwrap_or(buf.len());
        String::from_utf8_lossy(&buf[..end]).into_owned()
    } else {
        String::new()
    };
    let name = name.split('.').next().unwrap_or("").to_string();
    if name.is_empty() {
        "Linux".into()
    } else {
        name
    }
}

/// Launches a desktop entry: its Exec with no files, in a terminal when Terminal=true, detached from
/// this process (its own session, stdio to /dev/null, reaped by a thread so it leaves no zombie).
pub fn launch(entry: &desktop::Entry) -> Result<(), String> {
    let mut argv = desktop::exec_argv(entry).ok_or_else(|| format!("{} has no command to run", entry.name))?;
    if entry.terminal {
        let term = ["x-terminal-emulator", "xfce4-terminal", "gnome-terminal", "konsole", "xterm"]
            .iter()
            .find(|t| desktop::find_program(t).is_some())
            .ok_or("it runs in a terminal, and no terminal is installed")?;
        let mut wrapped = vec![term.to_string(), "-e".to_string()];
        wrapped.extend(argv);
        argv = wrapped;
    }
    let mut cmd = Command::new(&argv[0]);
    cmd.args(&argv[1..]).stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null());
    if let Some(home) = std::env::var_os("HOME") {
        cmd.current_dir(home);
    }
    unsafe {
        use std::os::unix::process::CommandExt;
        cmd.pre_exec(|| {
            libc::setsid();
            Ok(())
        });
    }
    let mut child = cmd.spawn().map_err(|e| format!("{}: {e}", argv[0]))?;
    std::thread::spawn(move || {
        let _ = child.wait();
    });
    Ok(())
}
