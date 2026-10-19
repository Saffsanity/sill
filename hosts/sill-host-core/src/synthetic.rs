//! A synthetic platform (SyntheticCapture.swift's idea): a moving test pattern for the Desktop and
//! a couple of fake windows, encoded through FFmpeg, so the core runs anywhere (this Mac included)
//! without capturing or posting anything. Input is only logged ("Test input: …").

use crate::ffmpeg::{FfmpegConfig, FfmpegEncoder, HevcEncoder, PixelFormat};
use crate::log;
use crate::platform::*;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

const DESKTOP: (u32, u32) = (1920, 1200);

struct FakeWindow {
    window: Window,
    x: f64,
    y: f64,
    /// Y, U, V of the window's background.
    color: (u8, u8, u8),
}

pub struct SyntheticPlatform {
    windows: Mutex<Vec<FakeWindow>>,
    encoder: HevcEncoder,
    pointer: Mutex<Option<(f64, f64)>>,
    last_move_log: Mutex<(Instant, u32)>,
}

impl SyntheticPlatform {
    pub fn new(encoder: HevcEncoder) -> SyntheticPlatform {
        let w = |id, title: &str, app: &str, app_id: &str, width, height, x, y, color| FakeWindow {
            window: Window { id, title: title.into(), app_name: app.into(), app_id: app_id.into(), width, height },
            x,
            y,
            color,
        };
        SyntheticPlatform {
            windows: Mutex::new(vec![
                w(101, "Shopping list", "Sill Test Notes", "app.sill.test.notes", 900, 600, 120.0, 90.0, (180, 100, 170)),
                w(102, "Calculator", "Sill Test Calculator", "app.sill.test.calculator", 400, 560, 1200.0, 200.0, (90, 160, 110)),
            ]),
            encoder,
            pointer: Mutex::new(None),
            last_move_log: Mutex::new((Instant::now(), 0)),
        }
    }

    fn app_color(app_id: &str) -> [u8; 3] {
        match app_id {
            "app.sill.test.notes" => [250, 200, 60],
            "app.sill.test.calculator" => [90, 90, 100],
            "app.sill.test.terminal" => [30, 30, 30],
            _ => [80, 120, 220],
        }
    }
}

impl Platform for SyntheticPlatform {
    fn machine_name(&self) -> String {
        let host = std::process::Command::new("hostname")
            .output()
            .ok()
            .and_then(|o| String::from_utf8(o.stdout).ok())
            .map(|s| s.trim().trim_end_matches(".local").to_string())
            .filter(|s| !s.is_empty())
            .unwrap_or_else(|| "this computer".into());
        format!("Test Pattern on {host}")
    }

    fn windows(&self) -> Vec<Window> {
        self.windows.lock().unwrap().iter().map(|w| w.window.clone()).collect()
    }

    fn apps(&self) -> Vec<App> {
        vec![
            App { name: "Sill Test Calculator".into(), app_id: "app.sill.test.calculator".into() },
            App { name: "Sill Test Notes".into(), app_id: "app.sill.test.notes".into() },
            App { name: "Sill Test Terminal".into(), app_id: "app.sill.test.terminal".into() },
        ]
    }

    fn thumbnail(&self, window: u32) -> Option<Vec<u8>> {
        let (w, h, color) = {
            let ws = self.windows.lock().unwrap();
            let f = ws.iter().find(|f| f.window.id == window)?;
            (f.window.width, f.window.height, f.color)
        };
        // About 400 px on the long side, like the Mac's.
        let k = 400.0 / w.max(h) as f64;
        let (tw, th) = (((w as f64 * k) as u32).max(2), ((h as f64 * k) as u32).max(2));
        let (r, g, b) = yuv_to_rgb(color.0, color.1, color.2);
        let mut rgb = vec![0u8; (tw * th * 3) as usize];
        for y in 0..th {
            for x in 0..tw {
                let i = ((y * tw + x) * 3) as usize;
                let title_bar = y < th / 12;
                let stripe = (x / 20 + y / 20) % 2 == 0;
                let px = if title_bar { [230, 230, 230] } else if stripe { [r, g, b] } else { [r / 2, g / 2, b / 2] };
                rgb[i..i + 3].copy_from_slice(&px);
            }
        }
        encode_jpeg(&rgb, tw, th)
    }

    fn icon(&self, app_id: &str) -> Option<Vec<u8>> {
        let c = Self::app_color(app_id);
        let n = 128u32;
        let mut rgba = vec![0u8; (n * n * 4) as usize];
        for y in 0..n {
            for x in 0..n {
                // A rounded square.
                let (dx, dy) = ((x as i32 - 63).abs().max(36) - 36, (y as i32 - 63).abs().max(36) - 36);
                let inside = dx * dx + dy * dy <= 28 * 28;
                let i = ((y * n + x) * 4) as usize;
                if inside {
                    let shade = if (x + y) % 32 < 16 { 0 } else { 20 };
                    rgba[i..i + 4].copy_from_slice(&[c[0].saturating_sub(shade), c[1].saturating_sub(shade), c[2].saturating_sub(shade), 255]);
                }
            }
        }
        encode_png(&rgba, n, n)
    }

    fn start_stream(&self, config: StreamConfig, sink: Arc<dyn StreamSink>) -> Result<Box<dyn Stream>, String> {
        let (base, rect, color) = match config.source {
            Source::Desktop => (DESKTOP, Rect { x: 0.0, y: 0.0, width: DESKTOP.0 as f64, height: DESKTOP.1 as f64 }, (90, 140, 120)),
            Source::Window(id) => {
                let ws = self.windows.lock().unwrap();
                let f = ws.iter().find(|f| f.window.id == id).ok_or_else(|| format!("window {id} is gone"))?;
                (
                    (f.window.width, f.window.height),
                    Rect { x: f.x, y: f.y, width: f.window.width as f64, height: f.window.height as f64 },
                    f.color,
                )
            }
        };
        let width = ((base.0 as f64 * config.scale) as u32).max(16) & !1;
        let height = ((base.1 as f64 * config.scale) as u32).max(16) & !1;
        let mut cfg = FfmpegConfig::new(self.encoder.clone(), PixelFormat::Nv12, width, height, config.fps, config.bitrate);
        cfg.prioritize_speed = config.prioritize_speed;
        let noise = std::env::var("SILL_TEST_PATTERN").as_deref() == Ok("noise");
        log(&format!(
            "Synthetic capture: {width}×{height} @{} fps ({}){}",
            config.fps,
            cfg.encoder.name(),
            if noise { ", a square of noise (SILL_TEST_PATTERN)" } else { "" }
        ));
        let encoder = Arc::new(FfmpegEncoder::start(cfg, sink.clone())?);
        sink.cursor(arrow_cursor());
        let stop = Arc::new(AtomicBool::new(false));
        let (e, s) = (encoder.clone(), stop.clone());
        let fps = config.fps.max(1);
        let thread = std::thread::Builder::new()
            .name("sill-synthetic".into())
            .spawn(move || generate(e, s, width, height, fps, color))
            .map_err(|e| e.to_string())?;
        Ok(Box::new(SyntheticStream { encoder: Some(encoder), stop, thread: Some(thread), rect }))
    }

    fn inject(&self, input: Input) {
        if let Input::Move { x, y } = input {
            *self.pointer.lock().unwrap() = Some((x, y));
            // Moves come at the device's rate: one line every half second with the count.
            let mut l = self.last_move_log.lock().unwrap();
            l.1 += 1;
            if l.0.elapsed() >= Duration::from_millis(500) {
                log(&format!("Test input: move to {x:.0},{y:.0} ({} moves)", l.1));
                *l = (Instant::now(), 0);
            }
            return;
        }
        if let Input::ButtonDown { x, y, .. } | Input::ButtonUp { x, y, .. } = input {
            *self.pointer.lock().unwrap() = Some((x, y));
        }
        let line = match &input {
            Input::ButtonDown { button, x, y } => format!("{button:?} down at {x:.0},{y:.0}"),
            Input::ButtonUp { button, x, y } => format!("{button:?} up at {x:.0},{y:.0}"),
            Input::Scroll { x, y, dx, dy } => format!("scroll {dx:.1},{dy:.1} at {x:.0},{y:.0}"),
            Input::ScrollPhase { phase, x, y } => format!("scroll {phase:?} at {x:.0},{y:.0}"),
            Input::Key { hid_usage, down, modifiers } => {
                format!("key {hid_usage} {} (modifiers {modifiers:#x})", if *down { "down" } else { "up" })
            }
            Input::Text(t) => format!("text {t:?}"),
            Input::Move { .. } => unreachable!(),
        };
        log(&format!("Test input: {line} (not posted: a synthetic host)"));
    }

    fn raise(&self, window: u32) {
        log(&format!("Test window {window}: raised (synthetic)"));
    }

    fn resize(&self, window: u32, width: u32, height: u32) -> Option<(u32, u32)> {
        let mut ws = self.windows.lock().unwrap();
        let f = ws.iter_mut().find(|f| f.window.id == window)?;
        // Apps have minimum sizes.
        f.window.width = width.max(300);
        f.window.height = height.max(200);
        Some((f.window.width, f.window.height))
    }

    fn window_command(&self, window: u32, command: WindowCommand) {
        let mut ws = self.windows.lock().unwrap();
        match command {
            WindowCommand::Close | WindowCommand::Minimize => ws.retain(|f| f.window.id != window),
            WindowCommand::FullScreen => {
                if let Some(f) = ws.iter_mut().find(|f| f.window.id == window) {
                    f.window.width = DESKTOP.0;
                    f.window.height = DESKTOP.1;
                    f.x = 0.0;
                    f.y = 0.0;
                }
            }
        }
    }

    fn launch(&self, app_id: &str) -> Result<(), String> {
        let (title, app, id, size, color) = match app_id {
            "app.sill.test.terminal" => ("bash", "Sill Test Terminal", 103, (800, 500), (40, 128, 128)),
            "app.sill.test.notes" => ("New note", "Sill Test Notes", 104, (700, 500), (180, 100, 170)),
            "app.sill.test.calculator" => ("Calculator", "Sill Test Calculator", 105, (400, 560), (90, 160, 110)),
            _ => return Err(format!("no such app: {app_id}")),
        };
        let mut ws = self.windows.lock().unwrap();
        if !ws.iter().any(|f| f.window.id == id) {
            ws.push(FakeWindow {
                window: Window { id, title: title.into(), app_name: app.into(), app_id: app_id.into(), width: size.0, height: size.1 },
                x: 300.0,
                y: 300.0,
                color,
            });
        }
        Ok(())
    }

    fn pointer_location(&self) -> Option<(f64, f64)> {
        *self.pointer.lock().unwrap()
    }

    fn advertise(&self, _instance: &str, _port: u16, _txt: &[(String, String)]) -> Result<Box<dyn Send>, String> {
        Err("a synthetic host never advertises (devices would find a test pattern)".into())
    }
}

struct SyntheticStream {
    encoder: Option<Arc<FfmpegEncoder>>,
    stop: Arc<AtomicBool>,
    thread: Option<std::thread::JoinHandle<()>>,
    rect: Rect,
}

impl Stream for SyntheticStream {
    fn request_keyframe(&self) {
        if let Some(e) = &self.encoder {
            e.request_keyframe();
        }
    }

    fn source_rect(&self) -> Option<Rect> {
        Some(self.rect)
    }

    fn stop(mut self: Box<Self>) {
        self.stop.store(true, Ordering::Release);
        if let Some(t) = self.thread.take() {
            let _ = t.join();
        }
        if let Some(e) = self.encoder.take() {
            if let Ok(e) = Arc::try_unwrap(e) {
                e.stop();
            }
        }
    }
}

/// NV12 frames at `fps`: a static gradient with a sweeping bar, a bouncing square and a binary
/// frame counter, so every frame differs and a stall is visible.
fn generate(enc: Arc<FfmpegEncoder>, stop: Arc<AtomicBool>, w: u32, h: u32, fps: u32, color: (u8, u8, u8)) {
    let (wu, hu) = (w as usize, h as usize);
    let mut base = vec![0u8; wu * hu * 3 / 2];
    for y in 0..hu {
        for x in 0..wu {
            base[y * wu + x] = (color.0 as usize / 2 + (x * 100 / wu) + (y * 40 / hu)).min(235) as u8;
        }
    }
    for y in 0..hu / 2 {
        for x in 0..wu / 2 {
            let i = wu * hu + y * wu + x * 2;
            base[i] = color.1;
            base[i + 1] = color.2;
        }
    }
    let noise = std::env::var("SILL_TEST_PATTERN").as_deref() == Ok("noise");
    let mut seed: u64 = 0x9E37_79B9_7F4A_7C15;
    let interval = Duration::from_secs_f64(1.0 / fps as f64);
    let start = Instant::now();
    let mut n: u64 = 0;
    while !stop.load(Ordering::Acquire) && !enc.is_dead() {
        let mut f = base.clone();
        let t = start.elapsed().as_secs_f64();
        // A vertical bar sweeping across in 2 s.
        let bar_w = (wu / 40).max(2);
        let bx = ((t / 2.0).fract() * (wu - bar_w) as f64) as usize;
        for y in 0..hu {
            let row = &mut f[y * wu..(y + 1) * wu];
            row[bx..bx + bar_w].fill(235);
        }
        // A square bouncing up and down.
        let sq = (hu / 6).max(4);
        let phase = (t * 0.7).fract();
        let sy = ((if phase < 0.5 { phase * 2.0 } else { 2.0 - phase * 2.0 }) * (hu - sq) as f64) as usize;
        let sx = wu / 2 - sq / 2;
        for y in sy..sy + sq {
            f[y * wu + sx..y * wu + sx + sq].fill(30);
        }
        // The frame number in binary along the top.
        let cell = (wu / 48).max(2);
        for bit in 0..32 {
            let on = (n >> (31 - bit)) & 1 == 1;
            let x0 = cell + bit * cell;
            if x0 + cell >= wu || cell * 2 >= hu {
                break;
            }
            for y in cell / 2..cell + cell / 2 {
                f[y * wu + x0..y * wu + x0 + cell - 1].fill(if on { 235 } else { 16 });
            }
        }
        // SILL_TEST_PATTERN=noise: a square of noise, new every frame, so the stream's size follows
        // its bitrate (tests of slow links and eviction), as the Swift synthetic host has it.
        if noise {
            let (nw, nh) = (wu / 4, hu / 4);
            for y in hu / 2..hu / 2 + nh {
                for px in f[y * wu + wu / 8..y * wu + wu / 8 + nw].iter_mut() {
                    seed ^= seed << 13;
                    seed ^= seed >> 7;
                    seed ^= seed << 17;
                    *px = (seed >> 24) as u8;
                }
            }
        }
        enc.submit(f);
        n += 1;
        let next = start + interval * n as u32;
        let now = Instant::now();
        if next > now {
            std::thread::sleep(next - now);
        } else if now - next > interval * 4 {
            // Fell behind (a slow machine): skip ahead rather than catch up in a burst.
            n = (start.elapsed().as_secs_f64() * fps as f64) as u64;
        }
    }
}

fn yuv_to_rgb(y: u8, u: u8, v: u8) -> (u8, u8, u8) {
    let (y, u, v) = (y as f64 - 16.0, u as f64 - 128.0, v as f64 - 128.0);
    let c = |x: f64| x.clamp(0.0, 255.0) as u8;
    (c(1.164 * y + 1.596 * v), c(1.164 * y - 0.392 * u - 0.813 * v), c(1.164 * y + 2.017 * u))
}

/// A black arrow with a white edge, 16×24, its hotspot at the tip.
fn arrow_cursor() -> CursorShape {
    let (w, h) = (16u32, 24u32);
    let mut rgba = vec![0u8; (w * h * 4) as usize];
    for y in 0..h {
        for x in 0..w {
            // The arrow: inside the triangle x <= y*0.6, y < 18, plus a tail.
            let inside = (x as f64) <= (y as f64) * 0.62 && y < 17 || ((5..=7).contains(&x) && (14..22).contains(&y));
            let edge = (x as f64) <= (y as f64) * 0.62 + 1.5 && y < 18 || ((4..=8).contains(&x) && (13..23).contains(&y));
            let i = ((y * w + x) * 4) as usize;
            if inside {
                rgba[i..i + 4].copy_from_slice(&[0, 0, 0, 255]);
            } else if edge {
                rgba[i..i + 4].copy_from_slice(&[255, 255, 255, 255]);
            }
        }
    }
    CursorShape { png: encode_png(&rgba, w, h).unwrap_or_default(), hotspot_x: 1.0, hotspot_y: 1.0, width: w as f64, height: h as f64 }
}

/// RGBA → PNG.
pub fn encode_png(rgba: &[u8], width: u32, height: u32) -> Option<Vec<u8>> {
    let mut out = Vec::new();
    {
        let mut e = png::Encoder::new(&mut out, width, height);
        e.set_color(png::ColorType::Rgba);
        e.set_depth(png::BitDepth::Eight);
        let mut w = e.write_header().ok()?;
        w.write_image_data(rgba).ok()?;
    }
    Some(out)
}

/// RGB → JPEG (quality 70).
pub fn encode_jpeg(rgb: &[u8], width: u32, height: u32) -> Option<Vec<u8>> {
    let mut out = Vec::new();
    let e = jpeg_encoder::Encoder::new(&mut out, 70);
    e.encode(rgb, width as u16, height as u16, jpeg_encoder::ColorType::Rgb).ok()?;
    Some(out)
}
