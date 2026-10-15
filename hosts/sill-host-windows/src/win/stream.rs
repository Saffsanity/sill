//! A running stream: Windows.Graphics.Capture → our own copy of the newest frame → the video
//! processor (BGRA to NV12, scaled) → the HEVC encoder → the core's sink. Plus the cursor's shape,
//! polled beside it.
//!
//! One thread (`sill-stream`) does all the Direct3D work and feeds the encoder; the capture's
//! handler only keeps the newest frame and wakes it, and an asynchronous encoder's own thread
//! hands encoded frames to the sink. Frames are dropped, never queued: a frame that finds the
//! encoder busy waits in the copy, where the next frame replaces it.
//!
//! Keyframes, as the Mac's HEVCEncoder: a request makes the next frame a keyframe; when the
//! source is still (no new frame for 50 ms) the last picture is encoded again so the keyframe
//! goes out anyway. A window that changes size gets a new converter and encoder at its new size
//! once the size holds still for 150 ms (until then the old size is kept, scaled). A hardware
//! encoder that fails or holds a frame for 1.5 s is replaced by the software one once.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Condvar, Mutex};
use std::thread::JoinHandle;
use std::time::{Duration, Instant};

use sill_host_core::platform::{EncodedFrame, Rect, Source, Stream, StreamConfig, StreamSink};
use windows::Win32::Foundation::{HWND, POINT, RECT};
use windows::Win32::Graphics::Direct3D11::{ID3D11Texture2D, D3D11_BOX, D3D11_MAPPED_SUBRESOURCE, D3D11_MAP_READ, D3D11_TEXTURE2D_DESC};
use windows::Win32::Graphics::Dxgi::Common::{DXGI_FORMAT_B8G8R8A8_UNORM, DXGI_FORMAT_NV12};
use windows::Win32::Graphics::Gdi::{GetMonitorInfoW, MonitorFromPoint, HMONITOR, MONITORINFO, MONITOR_DEFAULTTOPRIMARY};
use windows::Win32::Media::{timeBeginPeriod, timeEndPeriod};

use super::capture::{self, Capture, Target};
use super::catalog;
use super::convert::Converter;
use super::cursor::CursorWatcher;
use super::d3d::D3d;
use super::encoder::{self, Candidate, Encoder, Settings};
use super::util::{com_init, log};
use crate::sizing;

const STILL_AFTER: Duration = Duration::from_millis(50);
const RESIZE_SETTLE: Duration = Duration::from_millis(150);
const HANG_AFTER: Duration = Duration::from_millis(1500);
const NUDGE_AFTER: Duration = Duration::from_millis(100);
/// NV12 surfaces the converter writes in turn: more than can be inside the encoder at once.
const SURFACES: usize = 6;

/// What a stream captures, for its rectangle.
#[derive(Clone, Copy)]
enum What {
    Window(HWND),
    Monitor(HMONITOR),
}

unsafe impl Send for What {}
unsafe impl Sync for What {}

impl What {
    fn rect(&self) -> Option<Rect> {
        let r = match *self {
            What::Window(hwnd) => catalog::frame_bounds(hwnd)?,
            What::Monitor(monitor) => monitor_rect(monitor)?,
        };
        Some(Rect {
            x: r.left as f64,
            y: r.top as f64,
            width: (r.right - r.left) as f64,
            height: (r.bottom - r.top) as f64,
        })
    }
}

pub fn primary_monitor() -> HMONITOR {
    unsafe { MonitorFromPoint(POINT { x: 0, y: 0 }, MONITOR_DEFAULTTOPRIMARY) }
}

pub fn monitor_rect(monitor: HMONITOR) -> Option<RECT> {
    let mut info = MONITORINFO { cbSize: std::mem::size_of::<MONITORINFO>() as u32, ..Default::default() };
    unsafe { GetMonitorInfoW(monitor, &mut info).as_bool().then_some(info.rcMonitor) }
}

/// What the stream's threads share.
struct Shared {
    stop: AtomicBool,
    keyframe: AtomicBool,
    closed: AtomicBool,
    ended: AtomicBool,
    wakes: Mutex<u64>,
    wake: Condvar,
    sink: Arc<dyn StreamSink>,
}

impl Shared {
    fn notify(&self) {
        if let Ok(mut n) = self.wakes.lock() {
            *n += 1;
        }
        self.wake.notify_all();
    }

    /// Waits for a wake after `seen`, or `timeout`.
    fn wait(&self, seen: &mut u64, timeout: Duration) {
        let Ok(guard) = self.wakes.lock() else { return };
        let Ok((guard, _)) = self.wake.wait_timeout_while(guard, timeout, |n| *n == *seen) else { return };
        *seen = *guard;
    }

    /// The stream ended by itself: told to the sink once, and never after `stop`.
    fn end(&self, reason: String) {
        if !self.stop.load(Ordering::SeqCst) && !self.ended.swap(true, Ordering::SeqCst) {
            log(&format!("Stream ended: {reason}"));
            self.sink.ended(reason);
        }
    }
}

pub struct WinStream {
    shared: Arc<Shared>,
    what: What,
    threads: Vec<JoinHandle<()>>,
}

impl Stream for WinStream {
    fn request_keyframe(&self) {
        self.shared.keyframe.store(true, Ordering::SeqCst);
        self.shared.notify();
    }

    fn source_rect(&self) -> Option<Rect> {
        self.what.rect()
    }

    fn stop(mut self: Box<Self>) {
        self.halt();
    }
}

impl WinStream {
    fn halt(&mut self) {
        self.shared.stop.store(true, Ordering::SeqCst);
        self.shared.notify();
        for t in self.threads.drain(..) {
            let _ = t.join();
        }
    }
}

impl Drop for WinStream {
    fn drop(&mut self) {
        self.halt();
    }
}

/// Starts a stream; returns once the capture and the encoder run (or why they could not).
pub fn start(config: StreamConfig, sink: Arc<dyn StreamSink>) -> Result<Box<dyn Stream>, String> {
    let (what, target) = match config.source {
        Source::Desktop => {
            let m = primary_monitor();
            (What::Monitor(m), Target::Monitor(m))
        }
        Source::Window(id) => {
            let hwnd = catalog::listed(id).ok_or_else(|| format!("window {id} is gone or not one a device may pick"))?;
            (What::Window(hwnd), Target::Window(hwnd))
        }
    };
    let shared = Arc::new(Shared {
        stop: AtomicBool::new(false),
        keyframe: AtomicBool::new(true),
        closed: AtomicBool::new(false),
        ended: AtomicBool::new(false),
        wakes: Mutex::new(0),
        wake: Condvar::new(),
        sink: sink.clone(),
    });
    let (ready_tx, ready_rx) = std::sync::mpsc::sync_channel::<Result<(), String>>(1);
    let pipeline = {
        let shared = shared.clone();
        let config = config.clone();
        std::thread::Builder::new()
            .name("sill-stream".into())
            .spawn(move || run(shared, config, target, ready_tx))
            .map_err(|e| format!("stream thread: {e}"))?
    };
    match ready_rx.recv_timeout(Duration::from_secs(10)) {
        Ok(Ok(())) => {}
        Ok(Err(e)) => {
            let _ = pipeline.join();
            return Err(e);
        }
        Err(_) => {
            shared.stop.store(true, Ordering::SeqCst);
            shared.notify();
            return Err("the capture or the encoder did not start within 10 s".into());
        }
    }
    let cursor = {
        let shared = shared.clone();
        std::thread::Builder::new()
            .name("sill-cursor".into())
            .spawn(move || {
                let mut watcher = CursorWatcher::new();
                while !shared.stop.load(Ordering::SeqCst) {
                    if let Some(shape) = watcher.poll() {
                        shared.sink.cursor(shape);
                    }
                    std::thread::sleep(Duration::from_millis(50));
                }
            })
            .map_err(|e| format!("cursor thread: {e}"))?
    };
    Ok(Box::new(WinStream { shared, what, threads: vec![pipeline, cursor] }))
}

/// The converter, its NV12 surfaces and the encoder, for one picture size.
struct Chain {
    converter: Converter,
    surfaces: Vec<ID3D11Texture2D>,
    staging: Option<ID3D11Texture2D>,
    encoder: Encoder,
    input: (u32, u32),
    output: (u32, u32),
    next: usize,
}

fn build_chain(
    d3d: &D3d,
    candidates: &[Candidate],
    software_only: bool,
    input: (u32, u32),
    config: &StreamConfig,
    shared: &Arc<Shared>,
) -> Result<Chain, String> {
    let output = sizing::output_size(input.0, input.1, config.scale);
    let settings = Settings {
        width: output.0,
        height: output.1,
        fps: config.fps.max(1),
        bitrate: config.bitrate.max(100_000),
        prioritize_speed: config.prioritize_speed,
    };
    let surfaces = (0..SURFACES)
        .map(|_| d3d.texture(output.0, output.1, DXGI_FORMAT_NV12))
        .collect::<windows::core::Result<Vec<_>>>()
        .map_err(|e| format!("NV12 surfaces {}×{}: {e}", output.0, output.1))?;
    let converter = Converter::new(d3d, input.0, input.1, output.0, output.1, settings.fps, &surfaces)
        .map_err(|e| format!("video processor {}×{} → {}×{}: {e}", input.0, input.1, output.0, output.1))?;
    let mut errors = Vec::new();
    for candidate in candidates {
        if software_only && candidate.hardware {
            continue;
        }
        if candidate.hardware && candidate.adapter.is_some_and(|a| a != d3d.adapter) {
            errors.push(format!("{} is on another GPU", candidate.name));
            continue;
        }
        let sink = shared.sink.clone();
        let deliver: Box<dyn Fn(EncodedFrame) + Send + Sync> = Box::new(move |f| sink.frame(f));
        let waker = shared.clone();
        let wake: Arc<dyn Fn() + Send + Sync> = Arc::new(move || waker.notify());
        match Encoder::new(candidate, d3d, settings, deliver, wake) {
            Ok(encoder) => {
                let staging = if encoder.d3d_aware {
                    None
                } else {
                    Some(d3d.staging_nv12(output.0, output.1).map_err(|e| format!("staging surface: {e}"))?)
                };
                log(&format!(
                    "Encoder: {} ({}{}), {}×{} at {} fps, {} Mbps",
                    encoder.name,
                    if encoder.hardware { "hardware" } else { "software" },
                    if encoder.d3d_aware { ", GPU input" } else { ", system-memory input" },
                    output.0,
                    output.1,
                    settings.fps,
                    settings.bitrate / 1_000_000
                ));
                return Ok(Chain { converter, surfaces, staging, encoder, input, output, next: 0 });
            }
            Err(e) => {
                log(&format!("Encoder refused: {e}"));
                errors.push(e);
            }
        }
    }
    if candidates.is_empty() || (software_only && !candidates.iter().any(|c| !c.hardware)) {
        Err(encoder::NO_ENCODER.to_string())
    } else {
        Err(format!("no HEVC encoder would start: {}", errors.join("; ")))
    }
}

/// Our copy of the newest frame (the capture's buffers go back to it at once).
struct Latest {
    texture: ID3D11Texture2D,
    width: u32,
    height: u32,
}

type Ready = Option<std::sync::mpsc::SyncSender<Result<(), String>>>;

fn run(shared: Arc<Shared>, config: StreamConfig, target: Target, ready: std::sync::mpsc::SyncSender<Result<(), String>>) {
    com_init();
    // Windows' timer otherwise ticks every 15.6 ms: too coarse for 60 and 120 fps pacing.
    unsafe { timeBeginPeriod(1) };
    let mut ready: Ready = Some(ready);
    let result = pipeline(&shared, &config, target, &mut ready);
    unsafe { timeEndPeriod(1) };
    if let Err(e) = result {
        // Before the start was answered this is the start's error; after, the stream's end.
        match ready.take() {
            Some(tx) => {
                let _ = tx.send(Err(e));
            }
            None => shared.end(e),
        }
    }
}

fn pipeline(shared: &Arc<Shared>, config: &StreamConfig, target: Target, ready: &mut Ready) -> Result<(), String> {
    encoder::startup()?;
    let candidates = encoder::candidates();
    if candidates.is_empty() {
        return Err(encoder::NO_ENCODER.to_string());
    }
    // The device goes on the first hardware encoder's GPU, so it reads our surfaces directly.
    let adapter = candidates.iter().find(|c| c.hardware).and_then(|c| c.adapter);
    let d3d = D3d::new(adapter).or_else(|_| D3d::new(None)).map_err(|e| format!("Direct3D 11: {e}"))?;
    let fps = config.fps.max(1);
    let waker = shared.clone();
    let closer = shared.clone();
    let mut capture = Capture::start(
        &d3d,
        target,
        fps,
        Arc::new(move || waker.notify()),
        Arc::new(move || {
            closer.closed.store(true, Ordering::SeqCst);
            closer.notify();
        }),
    )
    .map_err(|e| format!("capture: {e}"))?;
    let size = capture.item_size().ok_or("the capture has no size")?;
    let initial = (size.Width.max(1) as u32, size.Height.max(1) as u32);
    let mut software_only = false;
    let mut chain = build_chain(&d3d, &candidates, software_only, initial, config, shared)?;
    if let Some(tx) = ready.take() {
        let _ = tx.send(Ok(()));
    }
    log(&format!("Stream started: {:?}, {}×{} captured", config.source, initial.0, initial.1));

    let start = Instant::now();
    let interval = Duration::from_secs_f64(1.0 / fps as f64);
    let mut latest: Option<Latest> = None;
    let mut fresh = false;
    let mut last_frame_at = Instant::now();
    let mut last_submit: Option<Instant> = None;
    let mut last_time: i64 = -1;
    let mut pending_size: Option<((u32, u32), Instant)> = None;
    let mut seen = 0u64;
    let mut nudged = false;
    let mut blocked_since: Option<Instant> = None;

    while !shared.stop.load(Ordering::SeqCst) {
        if shared.closed.load(Ordering::SeqCst) {
            return Err("The window closed.".into());
        }
        // A failed or hung hardware encoder: the software one, once. Hung: full with nothing back
        // for 1.5 s, or new frames kept out for 1.5 s by an encoder that never asks for input.
        let failure = chain
            .encoder
            .error()
            .or_else(|| {
                chain
                    .encoder
                    .hung_for()
                    .filter(|d| *d > HANG_AFTER)
                    .map(|d| format!("nothing came back for {} ms", d.as_millis()))
            })
            .or_else(|| {
                blocked_since
                    .filter(|t| t.elapsed() > HANG_AFTER)
                    .map(|t| format!("it took no frame for {} ms", t.elapsed().as_millis()))
            });
        if let Some(why) = failure {
            if chain.encoder.hardware && !software_only {
                log(&format!("Hardware encoder {} failed ({why}); switching to the software encoder", chain.encoder.name));
                software_only = true;
                blocked_since = None;
                let input = chain.input;
                // A hung driver can block its own teardown: that happens off this thread.
                let Chain { encoder: hung, .. } = chain;
                let _ = std::thread::Builder::new().name("sill-encoder-teardown".into()).spawn(move || drop(hung));
                chain = build_chain(&d3d, &candidates, true, input, config, shared)?;
                shared.keyframe.store(true, Ordering::SeqCst);
            } else {
                return Err(format!("the encoder failed: {why}"));
            }
        }

        // The newest frame, copied out of the capture's buffer.
        if let Some(frame) = capture.take() {
            let content = frame.ContentSize().map_err(|e| format!("capture: {e}"))?;
            let _ = capture.fit_pool(&d3d, content);
            let texture = capture::frame_texture(&frame).map_err(|e| format!("capture surface: {e}"))?;
            let (w, h) = clamp_to_texture(&texture, content.Width, content.Height);
            if w > 0 && h > 0 {
                if latest.as_ref().is_none_or(|l| (l.width, l.height) != (w, h)) {
                    let t = d3d.texture(w, h, DXGI_FORMAT_B8G8R8A8_UNORM).map_err(|e| format!("frame copy: {e}"))?;
                    latest = Some(Latest { texture: t, width: w, height: h });
                }
                if let Some(l) = &latest {
                    let region = D3D11_BOX { left: 0, top: 0, front: 0, right: w, bottom: h, back: 1 };
                    unsafe { d3d.context.CopySubresourceRegion(&l.texture, 0, 0, 0, 0, &texture, 0, Some(&region)) };
                }
                fresh = true;
                nudged = false;
                last_frame_at = Instant::now();
                if (w, h) != chain.input {
                    if pending_size.is_none_or(|(s, _)| s != (w, h)) {
                        pending_size = Some(((w, h), Instant::now()));
                    }
                } else {
                    pending_size = None;
                }
            }
            let _ = frame.Close();
        }

        // A new size that held still: a converter and an encoder for it.
        if let Some((size, since)) = pending_size {
            if since.elapsed() >= RESIZE_SETTLE {
                drop(chain);
                chain = build_chain(&d3d, &candidates, software_only, size, config, shared)?;
                shared.keyframe.store(true, Ordering::SeqCst);
                pending_size = None;
                log(&format!("Source resized: {}×{} captured, {}×{} encoded", size.0, size.1, chain.output.0, chain.output.1));
            }
        }

        // Into the encoder: a fresh frame when the encoder has room and the frame rate allows,
        // or the last picture again for a keyframe the still source would never carry.
        let paced = last_submit.is_none_or(|t| t.elapsed() >= interval.mul_f64(0.9));
        let keyframe_wanted = shared.keyframe.load(Ordering::SeqCst);
        let still = last_frame_at.elapsed() >= STILL_AFTER;
        // An encoder that keeps a frame back (or dropped one) while the source is still would
        // keep the last change from the devices: the last picture once more pushes it out.
        let nudge = still
            && !nudged
            && chain.encoder.stalled_for().is_some_and(|d| d > NUDGE_AFTER);
        if let Some(l) = &latest {
            let wanted = fresh || (keyframe_wanted && still) || nudge;
            if wanted && paced {
                if chain.encoder.accepts() {
                    let keyframe = shared.keyframe.swap(false, Ordering::SeqCst);
                    let now = start.elapsed().as_nanos() as i64 / 100;
                    last_time = now.max(last_time + 1);
                    submit(&d3d, &mut chain, l, last_time, keyframe)?;
                    nudged = !fresh && nudge;
                    fresh = false;
                    blocked_since = None;
                    last_submit = Some(Instant::now());
                } else if chain.encoder.stalled_for().is_none() {
                    // Nothing inside and still no room: the encoder is not asking for input.
                    blocked_since.get_or_insert_with(Instant::now);
                }
            }
        }

        // Sleep until something can happen: a frame, the encoder asking for input, a keyframe
        // request, the frame interval, a still source, a size settling.
        let mut timeout = Duration::from_millis(250);
        if fresh {
            if let Some(t) = last_submit {
                timeout = timeout.min(interval.saturating_sub(t.elapsed()).max(Duration::from_millis(1)));
            }
        }
        if shared.keyframe.load(Ordering::SeqCst) && latest.is_some() {
            timeout = timeout.min(STILL_AFTER.saturating_sub(last_frame_at.elapsed()).max(Duration::from_millis(1)));
        }
        if let Some((_, since)) = pending_size {
            timeout = timeout.min(RESIZE_SETTLE.saturating_sub(since.elapsed()).max(Duration::from_millis(1)));
        }
        if chain.encoder.stalled_for().is_some() || blocked_since.is_some() {
            timeout = timeout.min(Duration::from_millis(100));
        }
        shared.wait(&mut seen, timeout);
    }
    Ok(())
}

/// The content size, never past the texture (a frame can arrive before the pool is recreated).
fn clamp_to_texture(texture: &ID3D11Texture2D, w: i32, h: i32) -> (u32, u32) {
    let mut desc = D3D11_TEXTURE2D_DESC::default();
    unsafe { texture.GetDesc(&mut desc) };
    ((w.max(0) as u32).min(desc.Width), (h.max(0) as u32).min(desc.Height))
}

fn submit(d3d: &D3d, chain: &mut Chain, latest: &Latest, time: i64, keyframe: bool) -> Result<(), String> {
    let index = chain.next;
    chain.next = (chain.next + 1) % chain.surfaces.len().min(chain.converter.targets());
    let content = RECT { left: 0, top: 0, right: latest.width as i32, bottom: latest.height as i32 };
    chain
        .converter
        .convert(&latest.texture, content, index)
        .map_err(|e| format!("video processor: {e}"))?;
    let surface = &chain.surfaces[index];
    let input = match &chain.staging {
        None => encoder::Input::Texture(surface.clone()),
        Some(staging) => encoder::Input::Bytes(read_nv12(d3d, surface, staging, chain.output)?),
    };
    chain.encoder.submit(input, time, keyframe)
}

/// An NV12 surface's bytes (the Y plane, then the interleaved UV plane, rows packed), for an
/// encoder that reads system memory.
fn read_nv12(d3d: &D3d, surface: &ID3D11Texture2D, staging: &ID3D11Texture2D, (w, h): (u32, u32)) -> Result<Vec<u8>, String> {
    unsafe {
        d3d.context.CopyResource(staging, surface);
        let mut mapped = D3D11_MAPPED_SUBRESOURCE::default();
        d3d.context
            .Map(staging, 0, D3D11_MAP_READ, 0, Some(&mut mapped))
            .map_err(|e| format!("map: {e}"))?;
        let pitch = mapped.RowPitch as usize;
        let base = mapped.pData as *const u8;
        let (w, h) = (w as usize, h as usize);
        let mut out = Vec::with_capacity(w * h * 3 / 2);
        for row in 0..h {
            out.extend_from_slice(std::slice::from_raw_parts(base.add(row * pitch), w));
        }
        let uv = base.add(pitch * h);
        for row in 0..h / 2 {
            out.extend_from_slice(std::slice::from_raw_parts(uv.add(row * pitch), w));
        }
        d3d.context.Unmap(staging, 0);
        Ok(out)
    }
}
