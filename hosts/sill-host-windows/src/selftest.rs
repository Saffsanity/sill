//! `--selftest` and `--list`: the backend on its own, for whoever runs it on a Windows PC before
//! the core serves devices. Nothing here posts input.

use std::io::Write;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use sill_host_core::platform::{CursorShape, EncodedFrame, Platform, Source, StreamConfig, StreamSink};

use crate::annexb;
use crate::win::{self, encoder};

pub fn list() -> i32 {
    let platform = win::WindowsPlatform::new();
    println!("Machine: {}", platform.machine_name());
    print_windows(&platform);
    let apps = platform.apps();
    println!("\nInstalled apps: {}", apps.len());
    for a in &apps {
        println!("  {}  [{}]", a.name, a.app_id);
    }
    print_encoders();
    0
}

fn print_windows(platform: &win::WindowsPlatform) {
    let windows = platform.windows();
    println!("\nWindows, front to back: {}", windows.len());
    for w in &windows {
        println!("  {:>10}  {:>5}×{:<5}  {}  — {}  [{}]", w.id, w.width, w.height, w.app_name, w.title, w.app_id);
    }
}

fn print_encoders() {
    let candidates = encoder::candidates();
    println!("\nHEVC encoders (in the order tried): {}", candidates.len());
    for c in &candidates {
        let adapter = c.adapter.map(|l| format!(" on adapter {:08x}:{:08x}", l.HighPart, l.LowPart)).unwrap_or_default();
        println!("  {} ({}){}", c.name, if c.hardware { "hardware" } else { "software" }, adapter);
    }
    if candidates.is_empty() {
        println!("  {}", encoder::NO_ENCODER);
    }
}

/// Collects what a stream delivers.
struct Collector {
    file: Mutex<std::fs::File>,
    frames: AtomicU64,
    keyframes: AtomicU64,
    bytes: AtomicU64,
    cursors: AtomicU64,
    ended: AtomicBool,
    started: Instant,
}

impl StreamSink for Collector {
    fn frame(&self, frame: EncodedFrame) {
        let n = self.frames.fetch_add(1, Ordering::SeqCst) + 1;
        let data = annexb::to_annexb(&frame);
        self.bytes.fetch_add(data.len() as u64, Ordering::SeqCst);
        if frame.keyframe {
            self.keyframes.fetch_add(1, Ordering::SeqCst);
        }
        println!(
            "  frame {n:>4} at {:>6} ms: {:>8} bytes, {} NAL units{}{}, {}×{}",
            self.started.elapsed().as_millis(),
            data.len(),
            frame.nals.len(),
            if frame.keyframe { ", keyframe" } else { "" },
            if frame.parameter_sets.is_some() { " with VPS/SPS/PPS" } else { "" },
            frame.width,
            frame.height
        );
        if let Ok(mut f) = self.file.lock() {
            let _ = f.write_all(&data);
        }
    }

    fn cursor(&self, shape: CursorShape) {
        self.cursors.fetch_add(1, Ordering::SeqCst);
        println!(
            "  cursor: {}×{} hotspot ({}, {}), PNG {} bytes",
            shape.width,
            shape.height,
            shape.hotspot_x,
            shape.hotspot_y,
            shape.png.len()
        );
    }

    fn ended(&self, reason: String) {
        self.ended.store(true, Ordering::SeqCst);
        println!("  stream ended: {reason}");
    }
}

pub fn run(args: &[String]) -> i32 {
    let mut frames = 120u64;
    let mut window: Option<u32> = None;
    let mut out = PathBuf::from(".");
    let mut i = 0;
    while i < args.len() {
        let value = args.get(i + 1);
        match (args[i].as_str(), value) {
            ("--frames", Some(v)) => frames = v.parse().unwrap_or(frames),
            ("--window", Some(v)) => window = v.parse().ok(),
            ("--out", Some(v)) => out = PathBuf::from(v),
            (other, _) => {
                eprintln!("selftest: unknown argument {other}");
                return 2;
            }
        }
        i += 2;
    }
    let platform = win::WindowsPlatform::new();
    let mut failures = 0;
    println!("Sill Windows backend self-test");
    println!("Machine: {}", platform.machine_name());
    print_windows(&platform);

    let windows = platform.windows();
    if let Some(first) = windows.first() {
        match platform.thumbnail(first.id) {
            Some(jpeg) => {
                let path = out.join("selftest-thumbnail.jpg");
                let _ = std::fs::write(&path, &jpeg);
                println!("\nThumbnail of {} ({}): {} bytes → {}", first.id, first.title, jpeg.len(), path.display());
            }
            None => {
                println!("\nThumbnail of {}: none", first.id);
                failures += 1;
            }
        }
        match platform.icon(&first.app_id) {
            Some(png) => {
                let path = out.join("selftest-icon.png");
                let _ = std::fs::write(&path, &png);
                println!("Icon of {}: {} bytes → {}", first.app_id, png.len(), path.display());
            }
            None => {
                println!("Icon of {}: none", first.app_id);
                failures += 1;
            }
        }
    }
    let t = Instant::now();
    let apps = platform.apps();
    println!("Installed apps: {} in {} ms", apps.len(), t.elapsed().as_millis());
    for a in apps.iter().take(10) {
        println!("  {}  [{}]", a.name, a.app_id);
    }
    if let Some((x, y)) = platform.pointer_location() {
        println!("Pointer at {x}, {y}");
    }
    print_encoders();

    let source = window.map(Source::Window).unwrap_or(Source::Desktop);
    let path = out.join("selftest.h265");
    let file = match std::fs::File::create(&path) {
        Ok(f) => f,
        Err(e) => {
            eprintln!("cannot write {}: {e}", path.display());
            return 1;
        }
    };
    let collector = Arc::new(Collector {
        file: Mutex::new(file),
        frames: AtomicU64::new(0),
        keyframes: AtomicU64::new(0),
        bytes: AtomicU64::new(0),
        cursors: AtomicU64::new(0),
        ended: AtomicBool::new(false),
        started: Instant::now(),
    });
    let config = StreamConfig { source, fps: 60, bitrate: 15_000_000, scale: 1.0, prioritize_speed: false };
    println!("\nStreaming {source:?} for {frames} frames (60 fps, 15 Mbps) → {}", path.display());
    let stream = match platform.start_stream(config, collector.clone()) {
        Ok(s) => s,
        Err(e) => {
            println!("  could not start: {e}");
            return 1;
        }
    };
    if let Some(r) = stream.source_rect() {
        println!("  source rectangle: {}, {} {}×{}", r.x, r.y, r.width, r.height);
    }
    let deadline = Instant::now() + Duration::from_secs(30);
    let mut asked = false;
    while collector.frames.load(Ordering::SeqCst) < frames && !collector.ended.load(Ordering::SeqCst) && Instant::now() < deadline {
        std::thread::sleep(Duration::from_millis(20));
        if !asked && collector.frames.load(Ordering::SeqCst) >= frames / 2 {
            println!("  (asking for a keyframe)");
            stream.request_keyframe();
            asked = true;
        }
    }
    // A still screen gives few frames; the keyframe request must still produce one.
    if collector.frames.load(Ordering::SeqCst) < frames {
        println!("  (fewer frames than asked within 30 s: the screen was mostly still; asking for a keyframe)");
        let before = collector.keyframes.load(Ordering::SeqCst);
        stream.request_keyframe();
        std::thread::sleep(Duration::from_millis(500));
        if collector.keyframes.load(Ordering::SeqCst) == before {
            println!("  no keyframe came for a still source: FAIL");
            failures += 1;
        }
    }
    let elapsed = collector.started.elapsed().as_secs_f64();
    stream.stop();
    let n = collector.frames.load(Ordering::SeqCst);
    let bytes = collector.bytes.load(Ordering::SeqCst);
    println!(
        "\n{} frames ({} keyframes) in {:.1} s, {:.1} fps, {:.2} Mbit/s; {} cursor shapes; {}",
        n,
        collector.keyframes.load(Ordering::SeqCst),
        elapsed,
        n as f64 / elapsed.max(0.001),
        bytes as f64 * 8.0 / elapsed.max(0.001) / 1e6,
        collector.cursors.load(Ordering::SeqCst),
        path.display()
    );
    println!("Play it with: ffplay -f hevc {}", path.display());
    if n == 0 {
        failures += 1;
    }
    platform.release_input();
    if failures == 0 {
        println!("Self-test passed.");
        0
    } else {
        println!("Self-test: {failures} problem(s).");
        1
    }
}
