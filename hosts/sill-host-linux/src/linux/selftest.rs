//! `sill-host-linux --selftest [DIR]`: every part of the backend once, against the X display it runs
//! on, with what it saw written to DIR (default ./selftest): the windows and apps, icons and
//! thumbnails, desktop and window captures (also of a covered window), a stream's loop with the
//! cursor, a few seconds encoded to HEVC files (checked with ffprobe), XTest input observed by an
//! `xev` window (pointer, clicks, wheel, keys and chords, typed text including characters the keymap
//! lacks), typing into an xterm, resize, full screen, minimize, raise, close, launching an app, and
//! the Avahi advertisement (checked with avahi-browse). Meant for the Docker test (NOTES-linux.md);
//! it moves the pointer and types, so never run it on a desktop someone is using.
//!
//! Prints one PASS/FAIL/SKIP line per check and exits with the number that failed.

use std::io::{BufRead, BufReader};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use sill_host_core::platform::{
    Button, CursorShape, EncodedFrame, Input, Platform, ScrollPhase, Source, StreamConfig, StreamSink, WindowCommand,
};

use super::capture::{self, Grab, Grabber, Target};
use super::cursor::CursorWatch;
use super::encoder::{self, FileEncoder};
use super::stream::{Encoder, MakeEncoder};
use super::{windows, LinuxPlatform};

struct Report {
    failed: u32,
    passed: u32,
    skipped: u32,
}

impl Report {
    fn check(&mut self, name: &str, result: Result<String, String>) {
        match result {
            Ok(detail) => {
                self.passed += 1;
                println!("PASS {name}: {detail}");
            }
            Err(detail) if detail.starts_with("skip:") => {
                self.skipped += 1;
                println!("SKIP {name}: {}", detail.trim_start_matches("skip:").trim());
            }
            Err(detail) => {
                self.failed += 1;
                println!("FAIL {name}: {detail}");
            }
        }
    }
}

fn wait_for<T>(timeout: Duration, mut f: impl FnMut() -> Option<T>) -> Option<T> {
    let deadline = Instant::now() + timeout;
    loop {
        if let Some(v) = f() {
            return Some(v);
        }
        if Instant::now() >= deadline {
            return None;
        }
        std::thread::sleep(Duration::from_millis(50));
    }
}

fn save_png(path: &Path, w: u32, h: u32, bgra: &[u8]) -> Result<(), String> {
    let mut rgba = bgra.to_vec();
    for px in rgba.chunks_exact_mut(4) {
        px.swap(0, 2);
        px[3] = 255;
    }
    let img = image::RgbaImage::from_raw(w, h, rgba).ok_or("bad size")?;
    img.save(path).map_err(|e| e.to_string())
}

/// A StreamSink that counts.
#[derive(Default)]
struct CountingSink {
    cursors: Mutex<Vec<CursorShape>>,
    ended: Mutex<Option<String>>,
}

impl StreamSink for CountingSink {
    fn frame(&self, _frame: EncodedFrame) {}
    fn cursor(&self, shape: CursorShape) {
        self.cursors.lock().unwrap().push(shape);
    }
    fn ended(&self, reason: String) {
        *self.ended.lock().unwrap() = Some(reason);
    }
}

/// An encoder that only counts pictures and keyframe requests (the stream loop's test).
struct CountingEncoder {
    pictures: Arc<AtomicU64>,
    keyframes: Arc<AtomicU64>,
}

impl Encoder for CountingEncoder {
    fn frame(&mut self, _bgra: &[u8], _w: u32, _h: u32, keyframe: bool) {
        self.pictures.fetch_add(1, Ordering::SeqCst);
        if keyframe {
            self.keyframes.fetch_add(1, Ordering::SeqCst);
        }
    }
}

/// An `xev` window whose output is collected.
struct Xev {
    child: std::process::Child,
    out: Arc<Mutex<String>>,
    window: u32,
}

impl Xev {
    fn start(platform: &LinuxPlatform) -> Result<Xev, String> {
        let mut child = Command::new("xev")
            .args(["-geometry", "400x300+600+300", "-name", "sill-xev"])
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()
            .map_err(|e| format!("skip: xev: {e}"))?;
        let out = Arc::new(Mutex::new(String::new()));
        let stdout = child.stdout.take().unwrap();
        let o = out.clone();
        std::thread::spawn(move || {
            for line in BufReader::new(stdout).lines().map_while(Result::ok) {
                let mut s = o.lock().unwrap();
                s.push_str(&line);
                s.push('\n');
            }
        });
        let window = wait_for(Duration::from_secs(5), || {
            windows::list(platform.x()).into_iter().find(|w| w.title == "sill-xev" || w.title == "Event Tester").map(|w| w.id)
        })
        .ok_or("xev's window did not appear")?;
        Ok(Xev { child, out, window })
    }

    fn take(&self) -> String {
        std::mem::take(&mut *self.out.lock().unwrap())
    }
}

impl Drop for Xev {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

fn settle() {
    std::thread::sleep(Duration::from_millis(300));
}

pub fn run(dir: &Path, seconds: u32) -> i32 {
    let _ = std::fs::create_dir_all(dir);
    let mut r = Report { failed: 0, passed: 0, skipped: 0 };
    let kind = encoder::probe();
    let platform = match LinuxPlatform::new(encoder::unavailable()) {
        Ok(p) => p,
        Err(e) => {
            println!("FAIL connect: {e}");
            return 1;
        }
    };
    let x = platform.x().clone();
    let (sw, sh) = x.screen_size();
    r.check("display", Ok(format!("{:?}, screen {sw}x{sh}, machine name {:?}", std::env::var("DISPLAY").unwrap_or_default(), platform.machine_name())));
    r.check("window manager", if x.has_ewmh_wm() { Ok("EWMH".into()) } else { Err("no EWMH window manager".into()) });

    // Windows and apps.
    let list = platform.windows();
    r.check(
        "windows",
        if list.is_empty() {
            Err("none listed".into())
        } else {
            Ok(list.iter().map(|w| format!("\n    {:#x} {:?} app {:?} ({}) {}x{}", w.id, w.title, w.app_name, w.app_id, w.width, w.height)).collect())
        },
    );
    let apps = platform.apps();
    r.check(
        "apps",
        if apps.is_empty() {
            Err("no desktop entries".into())
        } else {
            Ok(format!("{} apps: {}", apps.len(), apps.iter().take(8).map(|a| format!("{} ({})", a.name, a.app_id)).collect::<Vec<_>>().join(", ")))
        },
    );

    // Icons and thumbnails.
    let mut ids: Vec<String> = list.iter().map(|w| w.app_id.clone()).collect();
    ids.extend(apps.iter().take(4).map(|a| a.app_id.clone()));
    ids.sort();
    ids.dedup();
    let mut got = Vec::new();
    let mut missing = Vec::new();
    for id in &ids {
        match platform.icon(id) {
            Some(png) => {
                let _ = std::fs::write(dir.join(format!("icon-{}.png", id.replace('/', "_"))), &png);
                got.push(format!("{id} {}B", png.len()));
            }
            None => missing.push(id.clone()),
        }
    }
    r.check("icons", if got.is_empty() { Err(format!("none for {ids:?}")) } else { Ok(format!("{}; none for {:?}", got.join(", "), missing)) });
    let mut thumbs = Vec::new();
    for w in &list {
        match platform.thumbnail(w.id) {
            Some(jpg) => {
                let _ = std::fs::write(dir.join(format!("thumb-{:x}.jpg", w.id)), &jpg);
                thumbs.push(format!("{:#x} {}B", w.id, jpg.len()));
            }
            None => thumbs.push(format!("{:#x} NONE", w.id)),
        }
    }
    r.check("thumbnails", if thumbs.iter().any(|t| t.contains("NONE")) || thumbs.is_empty() { Err(thumbs.join(", ")) } else { Ok(thumbs.join(", ")) });

    // Captures.
    r.check("capture desktop", capture_test(&x, Target::Desktop, &dir.join("desktop.png")));
    if let Some(w) = list.first() {
        r.check("capture window", capture_test(&x, Target::Window(w.id), &dir.join(format!("window-{:x}.png", w.id))));
    }
    r.check("capture covered window", covered_test(&platform, dir));

    // Cursor.
    r.check("cursor", {
        let mut watch = CursorWatch::new(&x);
        match watch.poll(&x) {
            Some(c) => {
                let _ = std::fs::write(dir.join("cursor.png"), &c.png);
                Ok(format!("{}x{} hotspot {},{} png {}B", c.width, c.height, c.hotspot_x, c.hotspot_y, c.png.len()))
            }
            None => Err("no cursor image".into()),
        }
    });

    // The stream loop: pictures only when something changes, keyframes on request, the cursor.
    r.check("stream loop", stream_loop_test(&platform));

    // Encoding.
    match kind {
        None => r.check("encode", Err("no HEVC encoder (ffmpeg with libx265, VAAPI or NVENC)".into())),
        Some(k) => {
            r.check("encoder", Ok(format!("{} (probed)", k.name())));
            r.check("core encoder, 1280x720 at half scale, 30 fps", core_encoder_test(k, 1280, 720, 0.5, 30, 8_000_000));
            r.check("core encoder, 544x394 at full scale, 30 fps", core_encoder_test(k, 544, 394, 1.0, 30, 8_000_000));
            r.check("core encoder, 544x394 at full scale, 60 fps", core_encoder_test(k, 544, 394, 1.0, 60, 15_000_000));
            r.check("core encoder, a captured xterm at 60 fps", core_encoder_live_test(&platform, k));
            r.check("encode desktop", encode_test(&platform, k, Target::Desktop, 1.0, seconds, &dir.join("desktop.hevc")));
            if let Some(w) = platform.windows().first() {
                r.check("encode window at half scale", encode_test(&platform, k, Target::Window(w.id), 0.5, seconds.min(3), &dir.join("window.hevc")));
            }
        }
    }

    // Input, observed by xev.
    match Xev::start(&platform) {
        Err(e) => r.check("input (xev)", Err(e)),
        Ok(xev) => {
            platform.raise(xev.window);
            settle();
            let (wx, wy, ww, wh) = windows::geometry(&x, xev.window).unwrap_or((600, 300, 400, 300));
            let (cx, cy) = ((wx + ww as i32 / 2) as f64, (wy + wh as i32 / 2) as f64);
            xev.take();
            platform.inject(Input::Move { x: cx, y: cy });
            settle();
            r.check("pointer move", match platform.pointer_location() {
                Some((px, py)) if (px - cx).abs() < 1.0 && (py - cy).abs() < 1.0 => Ok(format!("at {px},{py}")),
                other => Err(format!("asked {cx},{cy}, pointer at {other:?}")),
            });
            platform.inject(Input::ButtonDown { button: Button::Left, x: cx, y: cy });
            platform.inject(Input::ButtonUp { button: Button::Left, x: cx, y: cy });
            platform.inject(Input::ButtonDown { button: Button::Right, x: cx + 5.0, y: cy });
            platform.inject(Input::ButtonUp { button: Button::Right, x: cx + 5.0, y: cy });
            settle();
            let out = xev.take();
            r.check("click", expect(&out, &["ButtonPress", "button 1", "ButtonRelease", "button 3"]));
            platform.inject(Input::ScrollPhase { phase: ScrollPhase::Began, x: cx, y: cy });
            for _ in 0..12 {
                platform.inject(Input::Scroll { x: cx, y: cy, dx: 0.0, dy: 10.0 }); // content down: wheel up
            }
            platform.inject(Input::ScrollPhase { phase: ScrollPhase::Ended, x: cx, y: cy });
            for _ in 0..6 {
                platform.inject(Input::Scroll { x: cx, y: cy, dx: -20.0, dy: -20.0 });
            }
            settle();
            let out = xev.take();
            let ups = out.matches("button 4,").count();
            let downs = out.matches("button 5,").count();
            let rights = out.matches("button 7,").count();
            r.check("wheel", if ups == 4 && downs == 4 && rights == 4 {
                Ok(format!("120 px up = {} clicks of button 4 (press and release), 120 px down-right = button 5 ×{} and 7 ×{}", ups / 2, downs / 2, rights / 2))
            } else {
                Err(format!("button 4 events {ups} (want 4), button 5 {downs} (want 4), button 7 {rights} (want 4)"))
            });
            // Keys: "a", ⇧a, ⌘C (Control+c), ⌥x, Up, F5, then a modifier key held around a key.
            let k = |u: u16, d: bool, m: u64| Input::Key { hid_usage: u, down: d, modifiers: m };
            for e in [
                k(0x04, true, 0), k(0x04, false, 0),
                k(0x04, true, 1 << 17), k(0x04, false, 1 << 17),
                k(0x06, true, 1 << 20), k(0x06, false, 1 << 20),
                k(0x1B, true, 1 << 19), k(0x1B, false, 1 << 19),
                k(0x52, true, 0), k(0x52, false, 0),
                k(0x3E, true, 0), k(0x3E, false, 0),
                k(0xE3, true, 1 << 20), k(0x19, true, 1 << 20), k(0x19, false, 1 << 20), k(0xE3, false, 0),
            ] {
                platform.inject(e);
            }
            settle();
            let out = xev.take();
            r.check("keys", key_check(&out));
            platform.inject(Input::Text("Hi é€ж\n".into()));
            settle();
            let out = xev.take();
            r.check("text", expect(&out, &["keysym 0x48, H", "keysym 0x69, i", "keysym 0xe9, eacute", "keysym 0x10020ac", "keysym 0x1000436", "Return"]));

            // Window commands on xev's window.
            r.check("resize", match platform.resize(xev.window, 520, 410) {
                Some((w, h)) if (w, h) == (520, 410) => Ok("520x410 asked, 520x410 got".into()),
                other => Err(format!("asked 520x410, got {other:?}")),
            });
            r.check("resize to a minimum", match platform.resize(xev.window, 10, 10) {
                Some((w, h)) => Ok(format!("asked 10x10, got {w}x{h} (the window manager's or app's minimum)")),
                None => Err("no size".into()),
            });
            let _ = platform.resize(xev.window, 520, 410); // back above the 100 px listing floor
            platform.window_command(xev.window, WindowCommand::FullScreen);
            let full = wait_for(Duration::from_secs(2), || {
                let state = x.prop32(xev.window, x.atoms._NET_WM_STATE);
                state.contains(&x.atoms._NET_WM_STATE_FULLSCREEN).then(|| windows::geometry(&x, xev.window))
            });
            r.check("full screen", match full {
                Some(Some((_, _, w, h))) => Ok(format!("_NET_WM_STATE_FULLSCREEN set, {w}x{h}")),
                _ => Err("not full screen after 2 s".into()),
            });
            platform.window_command(xev.window, WindowCommand::FullScreen);
            settle();
            platform.window_command(xev.window, WindowCommand::Minimize);
            let gone = wait_for(Duration::from_secs(2), || (!platform.windows().iter().any(|w| w.id == xev.window)).then_some(()));
            r.check("minimize", gone.map(|_| "left the list".to_string()).ok_or("still listed after 2 s".to_string()));
            platform.raise(xev.window);
            let back = wait_for(Duration::from_secs(2), || platform.windows().iter().any(|w| w.id == xev.window).then_some(()));
            r.check("raise a minimized window", back.map(|_| "listed again".to_string()).ok_or_else(|| {
                use x11rb::protocol::xproto::ConnectionExt as _;
                let names = |v: Vec<u32>| v.iter().map(|a| x.conn.get_atom_name(*a).ok().and_then(|c| c.reply().ok()).map(|r| String::from_utf8_lossy(&r.name).into_owned()).unwrap_or_default()).collect::<Vec<_>>();
                format!("not back after 2 s: WM_STATE {:?}, _NET_WM_STATE {:?}, viewable {}", x.prop32(xev.window, x.atoms.WM_STATE), names(x.prop32(xev.window, x.atoms._NET_WM_STATE)), windows::is_viewable(&x, xev.window))
            }));
            platform.window_command(xev.window, WindowCommand::Close);
            let closed = wait_for(Duration::from_secs(3), || (!platform.windows().iter().any(|w| w.id == xev.window)).then_some(()));
            r.check("close", closed.map(|_| "xev closed its window".to_string()).ok_or("still there after 3 s".to_string()));
            platform.release_input();
        }
    }

    // Typing into a terminal: the same input, read back from a file the shell writes.
    r.check("typing into xterm", xterm_test(&platform));

    // Launching.
    r.check("launch", launch_test(&platform));

    // Advertising.
    r.check("advertise", advertise_test(&platform));

    println!("selftest: {} passed, {} failed, {} skipped; files in {}", r.passed, r.failed, r.skipped, dir.display());
    r.failed as i32
}

fn expect(out: &str, wanted: &[&str]) -> Result<String, String> {
    let missing: Vec<&&str> = wanted.iter().filter(|w| !out.contains(**w)).collect();
    if missing.is_empty() {
        Ok(format!("xev saw {}", wanted.join(", ")))
    } else {
        Err(format!("missing {missing:?} in xev's output:\n{}", out.lines().filter(|l| l.contains("Event") || l.contains("keysym") || l.contains("button")).collect::<Vec<_>>().join("\n")))
    }
}

/// The key events in xev's output, as "Press keysym-name" lines.
fn key_lines(out: &str) -> Vec<String> {
    let mut lines = Vec::new();
    let mut kind = "";
    for l in out.lines() {
        if l.starts_with("KeyPress") {
            kind = "Press";
        } else if l.starts_with("KeyRelease") {
            kind = "Release";
        } else if let (Some(i), false) = (l.find("keysym 0x"), kind.is_empty()) {
            let name = l[i..].split(',').nth(1).map(|s| s.trim().trim_end_matches(')')).unwrap_or("");
            lines.push(format!("{kind} {name}"));
            kind = "";
        }
    }
    lines
}

fn key_check(out: &str) -> Result<String, String> {
    let got = key_lines(out);
    let want: Vec<String> = [
        "Press a", "Release a",
        "Press Shift_L", "Press A", "Release A", "Release Shift_L",
        "Press Control_L", "Press c", "Release c", "Release Control_L",
        "Press Alt_L", "Press x", "Release x", "Release Alt_L",
        "Press Up", "Release Up",
        "Press F5", "Release F5",
        "Press Control_L", "Press v", "Release v", "Release Control_L",
    ]
    .iter()
    .map(|s| s.to_string())
    .collect();
    if got == want {
        Ok(format!("a, ⇧a, ⌘C as Control+c, ⌥x as Alt+x, Up, F5, ⌘ held around V: {} events in order, nothing left down", got.len()))
    } else {
        Err(format!("want {want:?}\n     got  {got:?}"))
    }
}

fn capture_test(x: &Arc<super::x::X>, target: Target, png: &Path) -> Result<String, String> {
    let mut g = Grabber::new(x.clone(), target)?;
    let mut last = None;
    let start = Instant::now();
    let n = 30;
    for _ in 0..n {
        match g.grab() {
            Grab::Frame(f) => last = Some(f),
            Grab::Hidden => {}
            Grab::Gone => return Err("gone".into()),
        }
    }
    let per = start.elapsed().as_secs_f64() * 1000.0 / n as f64;
    let f = last.ok_or("no picture")?;
    let nonblack = f.data.chunks_exact(4).filter(|p| p[0] | p[1] | p[2] != 0).count();
    save_png(png, f.width, f.height, &f.data)?;
    Ok(format!(
        "{}x{}, {:.2} ms a read over {n} ({}), {:.0}% of pixels not black, saved {}",
        f.width,
        f.height,
        per,
        if g.uses_shm() { "MIT-SHM" } else { "GetImage" },
        100.0 * nonblack as f64 / (f.width * f.height) as f64,
        png.file_name().unwrap().to_string_lossy()
    ))
}

/// Covers a red xterm with another window and reads both the covered window (its own pixmap) and the
/// screen where it is: the window's capture stays red, the screen there does not.
fn covered_test(platform: &LinuxPlatform, dir: &Path) -> Result<String, String> {
    let x = platform.x();
    let mut child = Command::new("xterm")
        .args(["-title", "sill-covered", "-bg", "#b01818", "-fg", "white", "-geometry", "60x16+700+500", "-e", "sh", "-c", "while true; do date; sleep 0.5; done"])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|e| format!("skip: xterm: {e}"))?;
    let result = (|| {
        let under = wait_for(Duration::from_secs(5), || windows::list(x).into_iter().find(|w| w.title == "sill-covered"))
            .ok_or("the red xterm did not appear")?;
        let over = windows::list(x).into_iter().find(|w| w.id != under.id && w.class != "XTerm").ok_or("skip: nothing to cover it with")?;
        // Start the capture first (it redirects the window), then cover it.
        let mut g = Grabber::new(x.clone(), Target::Window(under.id))?;
        let _ = g.grab();
        let (ux, uy, _, _) = windows::geometry(x, under.id).ok_or("gone")?;
        let _ = windows::resize(x, over.id, under.width + 80, under.height + 80);
        move_window(platform, over.id, ux - 30, uy - 60);
        platform.raise(over.id);
        std::thread::sleep(Duration::from_millis(800));
        let window = match g.grab() {
            Grab::Frame(f) => f,
            _ => return Err("no picture of the covered window".into()),
        };
        let screen = capture::snapshot(x, Target::Desktop).ok_or("no desktop picture")?;
        let red = |p: &[u8]| p[2] > 140 && p[1] < 80 && p[0] < 80; // BGRA
        let mut in_window = 0usize;
        let mut on_screen = 0usize;
        let mut total = 0usize;
        for row in (0..window.height as i32).step_by(3) {
            for col in (0..window.width as i32).step_by(3) {
                let (sx, sy) = (ux + col, uy + row);
                if sx < 0 || sy < 0 || sx >= screen.width as i32 || sy >= screen.height as i32 {
                    continue;
                }
                let a = (row as usize * window.width as usize + col as usize) * 4;
                let b = (sy as usize * screen.width as usize + sx as usize) * 4;
                total += 1;
                in_window += red(&window.data[a..a + 4]) as usize;
                on_screen += red(&screen.data[b..b + 4]) as usize;
            }
        }
        save_png(&dir.join("covered-window.png"), window.width, window.height, &window.data)?;
        save_png(&dir.join("covered-screen.png"), screen.width, screen.height, &screen.data)?;
        let (w_share, s_share) = (in_window as f64 / total.max(1) as f64, on_screen as f64 / total.max(1) as f64);
        let msg = format!(
            "a red xterm under {} ({}): {:.0}% red in its capture, {:.0}% red on the screen there (covered-window.png, covered-screen.png)",
            over.class, over.title, w_share * 100.0, s_share * 100.0
        );
        if w_share > 0.6 && s_share < 0.2 { Ok(msg) } else { Err(msg) }
    })();
    let _ = child.kill();
    let _ = child.wait();
    result
}

fn move_window(platform: &LinuxPlatform, w: u32, x: i32, y: i32) {
    use x11rb::connection::Connection;
    use x11rb::protocol::xproto::{ClientMessageEvent, EventMask};
    use x11rb::protocol::xproto::ConnectionExt as _;
    let xx = platform.x();
    let flags = (1u32 << 8) | (1 << 9) | (2 << 12);
    let ev = ClientMessageEvent::new(32, w, xx.atoms._NET_MOVERESIZE_WINDOW, [flags, x as u32, y as u32, 0, 0]);
    let _ = xx.conn.send_event(false, xx.root, EventMask::SUBSTRUCTURE_REDIRECT | EventMask::SUBSTRUCTURE_NOTIFY, ev);
    let _ = xx.conn.flush();
}

fn stream_loop_test(platform: &LinuxPlatform) -> Result<String, String> {
    let pictures = Arc::new(AtomicU64::new(0));
    let keyframes = Arc::new(AtomicU64::new(0));
    let (p, k) = (pictures.clone(), keyframes.clone());
    let make: MakeEncoder = Arc::new(move |_w, _h, _c: &StreamConfig, _s: Arc<dyn StreamSink>| -> Result<Box<dyn Encoder>, String> {
        Ok(Box::new(CountingEncoder { pictures: p.clone(), keyframes: k.clone() }))
    });
    let sink = Arc::new(CountingSink::default());
    let config = StreamConfig { source: Source::Desktop, fps: 30, bitrate: 8_000_000, scale: 1.0, prioritize_speed: false };
    let stream = super::stream::start(config, sink.clone(), make)?;
    // A still second, then the pointer moving xeyes' eyes for a second, then a keyframe request.
    std::thread::sleep(Duration::from_millis(1000));
    let still = pictures.load(Ordering::SeqCst);
    for i in 0..30 {
        platform.inject(Input::Move { x: 200.0 + i as f64 * 20.0, y: 300.0 + (i % 5) as f64 * 40.0 });
        std::thread::sleep(Duration::from_millis(33));
    }
    let moving = pictures.load(Ordering::SeqCst) - still;
    let before = keyframes.load(Ordering::SeqCst);
    stream.request_keyframe();
    std::thread::sleep(Duration::from_millis(200));
    let keyed = keyframes.load(Ordering::SeqCst) - before;
    let rect = stream.source_rect();
    stream.stop();
    let cursors = sink.cursors.lock().unwrap().len();
    let msg = format!(
        "{still} pictures in a still second (the first, plus any clock tick), {moving} while the pointer moved for 1 s, {keyed} keyframe after a request, {cursors} cursor shape(s), source rect {rect:?}"
    );
    if still <= 5 && moving >= 5 && keyed >= 1 && cursors >= 1 && rect.is_some() { Ok(msg) } else { Err(msg) }
}

/// The core's encoder through this backend's adapter (scaling to half size on the way): 90 frames
/// of a moving pattern at 30 fps. Expects every frame out, one keyframe at the start, and one
/// more after a request.
fn core_encoder_test(kind: encoder::Kind, w: u32, h: u32, scale: f64, fps: u32, bitrate: u32) -> Result<String, String> {
    #[derive(Default)]
    struct Sink {
        frames: AtomicU64,
        keys: Mutex<Vec<u64>>,
        sizes: Mutex<Option<(u32, u32)>>,
        ps: AtomicU64,
    }
    impl StreamSink for Sink {
        fn frame(&self, f: EncodedFrame) {
            let n = self.frames.fetch_add(1, Ordering::SeqCst);
            if f.keyframe {
                self.keys.lock().unwrap().push(n);
            }
            if f.parameter_sets.is_some() {
                self.ps.fetch_add(1, Ordering::SeqCst);
            }
            *self.sizes.lock().unwrap() = Some((f.width, f.height));
        }
        fn cursor(&self, _: CursorShape) {}
        fn ended(&self, _: String) {}
    }
    let sink = Arc::new(Sink::default());
    let config = StreamConfig { source: Source::Desktop, fps, bitrate, scale, prioritize_speed: true };
    let want = encoder::output_size(w, h, scale);
    let mut enc = (encoder::core(kind))(w, h, &config, sink.clone())?;
    let start = Instant::now();
    for i in 0..90u32 {
        let mut f = vec![40u8; (w * h * 4) as usize];
        let bar = (i * 12) % w;
        for y in 0..h {
            for x in bar..(bar + 40).min(w) {
                let p = ((y * w + x) * 4) as usize;
                f[p..p + 4].copy_from_slice(&[255, 255, 255, 255]);
            }
        }
        enc.frame(&f, w, h, i == 60);
        std::thread::sleep(Duration::from_millis(1000 / fps as u64));
    }
    std::thread::sleep(Duration::from_millis(300));
    drop(enc);
    let frames = sink.frames.load(Ordering::SeqCst);
    let keys = sink.keys.lock().unwrap().clone();
    let size = *sink.sizes.lock().unwrap();
    let msg = format!(
        "{frames} frames out of 90 in {:.1} s, keyframes at {:?}, parameter sets {} times, size {size:?}",
        start.elapsed().as_secs_f64(),
        if keys.len() > 12 { keys[..12].to_vec() } else { keys.clone() },
        sink.ps.load(Ordering::SeqCst)
    );
    let ok = frames >= 45 && keys.first() == Some(&0) && keys.len() <= 3 && size == Some(want);
    if ok { Ok(msg) } else { Err(format!("{msg} (want one keyframe at 0, one near 60, the rest deltas, at {want:?})")) }
}

/// The core's encoder fed by captured pictures of a busy xterm, as a stream does.
fn core_encoder_live_test(platform: &LinuxPlatform, kind: encoder::Kind) -> Result<String, String> {
    #[derive(Default)]
    struct Sink {
        frames: AtomicU64,
        keys: AtomicU64,
    }
    impl StreamSink for Sink {
        fn frame(&self, f: EncodedFrame) {
            self.frames.fetch_add(1, Ordering::SeqCst);
            if f.keyframe {
                self.keys.fetch_add(1, Ordering::SeqCst);
            }
        }
        fn cursor(&self, _: CursorShape) {}
        fn ended(&self, _: String) {}
    }
    let mut child = Command::new("xterm")
        .args(["-title", "sill-busy", "-geometry", "90x30+300+400", "-e", "sh", "-c", "while true; do date +%s.%N; sleep 0.01; done"])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|e| format!("skip: xterm: {e}"))?;
    let result = (|| {
        let w = wait_for(Duration::from_secs(5), || platform.windows().into_iter().find(|w| w.title == "sill-busy"))
            .ok_or("the busy xterm did not appear")?;
        let sink = Arc::new(Sink::default());
        let config = StreamConfig { source: Source::Window(w.id), fps: 60, bitrate: 15_000_000, scale: 1.0, prioritize_speed: false };
        use std::sync::atomic::Ordering::Relaxed;
        let (s0, k0, n0) = (encoder::STARTED.load(Relaxed), encoder::KEYS_ASKED.load(Relaxed), encoder::SUBMITTED.load(Relaxed));
        let stream = super::stream::start(config.clone(), sink.clone(), encoder::core(kind))?;
        std::thread::sleep(Duration::from_secs(3));
        stream.stop();
        let counters = format!(
            "encoders started {}, keyframes asked {}, pictures submitted {}",
            encoder::STARTED.load(Relaxed) - s0,
            encoder::KEYS_ASKED.load(Relaxed) - k0,
            encoder::SUBMITTED.load(Relaxed) - n0
        );
        let (frames, keys) = (sink.frames.load(Ordering::SeqCst), sink.keys.load(Ordering::SeqCst));
        // The same pictures without the stream loop: grabbed here, given to the encoder directly,
        // once with the padding byte as captured and once with it set to 255.
        let mut direct = Vec::new();
        for opaque in [false, true] {
            let sink2 = Arc::new(Sink::default());
            let mut enc = (encoder::core(kind))(w.width & !1, w.height & !1, &config, sink2.clone())?;
            let mut g = Grabber::new(platform.x().clone(), Target::Window(w.id))?;
            let t0 = Instant::now();
            while t0.elapsed() < Duration::from_secs(2) {
                if let Grab::Frame(mut f) = g.grab() {
                    if opaque {
                        f.data.chunks_exact_mut(4).for_each(|p| p[3] = 255);
                    }
                    let alpha = f.data.get(3).copied().unwrap_or(0);
                    enc.frame(&f.data, f.width, f.height, false);
                    if direct.len() < 2 && t0.elapsed() < Duration::from_millis(20) {
                        direct.push(format!("padding byte {alpha}"));
                    }
                }
                std::thread::sleep(Duration::from_millis(16));
            }
            std::thread::sleep(Duration::from_millis(200));
            drop(enc);
            direct.push(format!("{}: {} frames, {} keyframes", if opaque { "opaque" } else { "as captured" }, sink2.frames.load(Ordering::SeqCst), sink2.keys.load(Ordering::SeqCst)));
        }
        let msg = format!("{frames} frames, {keys} keyframes in 3 s ({}x{}; {counters}); directly: {}", w.width, w.height, direct.join(", "));
        if frames > 30 && keys <= 2 { Ok(msg) } else { Err(msg) }
    })();
    let _ = child.kill();
    let _ = child.wait();
    result
}

fn encode_test(platform: &LinuxPlatform, kind: encoder::Kind, target: Target, scale: f64, seconds: u32, path: &Path) -> Result<String, String> {
    let x = platform.x();
    let mut g = Grabber::new(x.clone(), target)?;
    let first = match g.grab() {
        Grab::Frame(f) => f,
        _ => return Err("no picture".into()),
    };
    let (w, h) = (first.width & !1, first.height & !1);
    let fps = 30;
    let config = StreamConfig { source: Source::Desktop, fps, bitrate: 10_000_000, scale, prioritize_speed: true };
    let mut enc = FileEncoder::new(kind, w, h, &config, &path.to_string_lossy())?;
    let start = Instant::now();
    let interval = Duration::from_secs_f64(1.0 / fps as f64);
    let mut i = 0u32;
    let mut read_ms = 0.0;
    while start.elapsed() < Duration::from_secs(seconds as u64) {
        let tick = Instant::now();
        platform.inject(Input::Move { x: 300.0 + (i % 60) as f64 * 15.0, y: 400.0 + (i % 20) as f64 * 10.0 });
        let t = Instant::now();
        let f = match g.grab() {
            Grab::Frame(f) => f,
            _ => continue,
        };
        read_ms += t.elapsed().as_secs_f64() * 1000.0;
        if f.width & !1 != w || f.height & !1 != h {
            break;
        }
        let mut data = Vec::with_capacity((w * h * 4) as usize);
        for row in 0..h as usize {
            let s = row * f.width as usize * 4;
            data.extend_from_slice(&f.data[s..s + w as usize * 4]);
        }
        enc.frame(&data, w, h, false);
        i += 1;
        if let Some(rest) = interval.checked_sub(tick.elapsed()) {
            std::thread::sleep(rest);
        }
    }
    let wrote = enc.frames;
    let took = start.elapsed().as_secs_f64();
    enc.finish()?;
    let probe = Command::new("ffprobe")
        .args(["-v", "error", "-count_frames", "-select_streams", "v:0", "-show_entries", "stream=codec_name,width,height,nb_read_frames", "-of", "csv=p=0"])
        .arg(path)
        .output()
        .map_err(|e| format!("ffprobe: {e}"))?;
    let probed = String::from_utf8_lossy(&probe.stdout).trim().to_string();
    let parts: Vec<&str> = probed.split(',').collect();
    let (ow, oh) = encoder::output_size(w, h, scale);
    let ok = parts.first() == Some(&"hevc")
        && parts.get(1) == Some(&ow.to_string().as_str())
        && parts.get(2) == Some(&oh.to_string().as_str())
        && parts.get(3).and_then(|n| n.parse::<u64>().ok()) == Some(wrote);
    let size = std::fs::metadata(path).map(|m| m.len()).unwrap_or(0);
    let msg = format!(
        "{wrote} pictures of {w}x{h} in {took:.1} s ({:.1} fps, {:.1} ms a read) to {} {ow}x{oh}: ffprobe says {probed:?}, {} kB ({})",
        wrote as f64 / took,
        read_ms / wrote.max(1) as f64,
        kind.name(),
        size / 1000,
        path.file_name().unwrap().to_string_lossy()
    );
    if ok { Ok(msg) } else { Err(msg) }
}

fn xterm_test(platform: &LinuxPlatform) -> Result<String, String> {
    let file = PathBuf::from(format!("/tmp/sill-selftest-{}.txt", std::process::id()));
    let _ = std::fs::remove_file(&file);
    let mut child = Command::new("xterm")
        .args(["-title", "sill-typing", "-geometry", "80x10+100+100", "-e", "sh"])
        .env("PS1", "$ ")
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|e| format!("skip: xterm: {e}"))?;
    let result = (|| {
        let w = wait_for(Duration::from_secs(5), || platform.windows().into_iter().find(|w| w.title == "sill-typing").map(|w| w.id))
            .ok_or("xterm's window did not appear")?;
        platform.raise(w);
        std::thread::sleep(Duration::from_millis(500));
        // Keys for "echo ", then text for the rest (with characters not on a US keymap).
        let k = |u: u16, d: bool| Input::Key { hid_usage: u, down: d, modifiers: 0 };
        for u in [0x08u16, 0x06, 0x0B, 0x12, 0x2C] {
            platform.inject(k(u, true));
            platform.inject(k(u, false));
        }
        platform.inject(Input::Text(format!("Sill-Ä€ > {}\n", file.display())));
        let text = wait_for(Duration::from_secs(3), || std::fs::read_to_string(&file).ok().filter(|s| !s.is_empty()))
            .ok_or("the shell wrote nothing")?;
        if text.trim() == "Sill-Ä€" {
            Ok(format!("keys \"echo \" and text \"Sill-Ä€ > …\" ran: the file says {:?}", text.trim()))
        } else {
            Err(format!("the file says {:?}", text.trim()))
        }
    })();
    let _ = child.kill();
    let _ = child.wait();
    let _ = std::fs::remove_file(&file);
    platform.release_input();
    result
}

fn launch_test(platform: &LinuxPlatform) -> Result<String, String> {
    let apps = platform.apps();
    let app = apps
        .iter()
        .find(|a| a.app_id.contains("xterm") && !a.app_id.contains("uxterm"))
        .or_else(|| apps.iter().find(|a| a.app_id.contains("xterm")))
        .ok_or("skip: no xterm desktop entry")?;
    let x = platform.x();
    // Windows by id and process: a new client can get the id of one that just closed (X reuses a
    // gone client's id range), which the window manager may still list for a moment.
    let clients = || -> Vec<(u32, Option<u32>)> { windows::clients_front_to_back(x).into_iter().map(|w| (w, x.pid(w))).collect() };
    let before = clients();
    platform.launch(&app.app_id)?;
    let new = wait_for(Duration::from_secs(10), || clients().into_iter().find(|c| !before.contains(c)).map(|c| c.0))
        .ok_or_else(|| format!("{} launched, no new client window in 10 s", app.app_id))?;
    let listed = wait_for(Duration::from_secs(3), || platform.windows().into_iter().find(|w| w.id == new));
    let detail = match &listed {
        Some(w) => format!("listed as {:?} with app id {:?}", w.title, w.app_id),
        None => format!("not listed: {}", windows::why_not_listed(x, new)),
    };
    platform.window_command(new, WindowCommand::Close);
    Ok(format!("{} ({}) opened {new:#x}, {detail}; closed it", app.name, app.app_id))
}

fn advertise_test(platform: &LinuxPlatform) -> Result<String, String> {
    let name = format!("Sill selftest {}", std::process::id());
    let txt = vec![("p".to_string(), "1".to_string()), ("r".to_string(), "c2lsbA".to_string())];
    let guard = platform.advertise(&name, 47_999, &txt).map_err(|e| format!("skip: {e}"))?;
    let browse = || -> String {
        Command::new("avahi-browse")
            .args(["-rpt", "_sill._tcp"])
            .output()
            .map(|o| String::from_utf8_lossy(&o.stdout).into_owned())
            .unwrap_or_default()
    };
    let seen = wait_for(Duration::from_secs(5), || {
        let out = browse();
        out.lines().find(|l| l.starts_with('=') && l.contains(&name.replace(' ', "\\032")) || l.starts_with('=') && l.contains(&name)).map(|l| l.to_string())
    });
    drop(guard);
    let gone = wait_for(Duration::from_secs(5), || (!browse().contains(&name.replace(' ', "\\032")) && !browse().contains(&name)).then_some(()));
    match seen {
        Some(line) if line.contains("47999") && line.contains("\"p=1\"") => {
            Ok(format!("avahi-browse saw it ({}), {} once the guard dropped", line.split(';').skip(3).take(1).collect::<String>(), if gone.is_some() { "gone" } else { "STILL THERE" }))
        }
        Some(line) => Err(format!("listed without the port or TXT: {line}")),
        None => Err("avahi-browse did not list it".into()),
    }
}
