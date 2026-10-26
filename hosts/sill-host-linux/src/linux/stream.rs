//! A running stream: a thread with its own X connection reads the source at the stream's frame rate
//! and hands every changed picture to an encoder; it also sends the cursor's shape when it changes.
//!
//! Latency beats quality: a picture is read only when the tick comes, nothing is queued here (the
//! encoder drops what it cannot take), and an unchanged picture is not encoded again (a still
//! window costs a memcmp a tick), except when a keyframe is asked for.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread::JoinHandle;
use std::time::{Duration, Instant};

use sill_host_core::platform::{Rect, Source, Stream, StreamConfig, StreamSink};
use sill_host_core::stats::bump;

use super::capture::{Frame, Grab, Grabber, Target};
use super::cursor::CursorWatch;
use super::x::X;

/// What takes the pictures. One per size: a new size makes a new encoder (its first frame a keyframe
/// with the stream's parameter sets).
pub trait Encoder: Send {
    /// One picture, BGRA, `width * 4` bytes a row. `keyframe`: this one must be a keyframe (never
    /// set on an encoder's first picture, which is one anyway).
    fn frame(&mut self, bgra: &[u8], width: u32, height: u32, keyframe: bool);
}

/// Makes an encoder for pictures of width×height (even), for `config`, delivering to `sink`.
pub type MakeEncoder =
    Arc<dyn Fn(u32, u32, &StreamConfig, Arc<dyn StreamSink>) -> Result<Box<dyn Encoder>, String> + Send + Sync>;

struct Shared {
    stop: AtomicBool,
    keyframe: AtomicBool,
    rect: Mutex<Option<Rect>>,
}

pub struct LinuxStream {
    shared: Arc<Shared>,
    thread: Option<JoinHandle<()>>,
}

impl Stream for LinuxStream {
    fn request_keyframe(&self) {
        self.shared.keyframe.store(true, Ordering::SeqCst);
    }

    fn source_rect(&self) -> Option<Rect> {
        *self.shared.rect.lock().unwrap()
    }

    fn stop(mut self: Box<Self>) {
        self.halt();
    }
}

impl LinuxStream {
    fn halt(&mut self) {
        self.shared.stop.store(true, Ordering::SeqCst);
        if let Some(t) = self.thread.take() {
            let _ = t.join();
        }
    }
}

impl Drop for LinuxStream {
    fn drop(&mut self) {
        self.halt();
    }
}

fn to_rect((x, y, w, h): (i32, i32, u32, u32)) -> Rect {
    Rect { x: x as f64, y: y as f64, width: w as f64, height: h as f64 }
}

pub fn start(config: StreamConfig, sink: Arc<dyn StreamSink>, make: MakeEncoder) -> Result<Box<dyn Stream>, String> {
    let x = X::connect()?;
    let target = match config.source {
        Source::Desktop => Target::Desktop,
        Source::Window(id) => Target::Window(id),
    };
    let grabber = Grabber::new(x.clone(), target)?;
    let first_rect = grabber.rect().ok_or_else(|| format!("window {:#x} is gone", match target {
        Target::Window(w) => w,
        Target::Desktop => 0,
    }))?;
    let shared = Arc::new(Shared {
        stop: AtomicBool::new(false),
        keyframe: AtomicBool::new(false),
        rect: Mutex::new(Some(to_rect(first_rect))),
    });
    let s = shared.clone();
    let thread = std::thread::Builder::new()
        .name("sill-capture".into())
        .spawn(move || run(x, grabber, config, sink, make, s))
        .map_err(|e| format!("capture thread: {e}"))?;
    Ok(Box::new(LinuxStream { shared, thread: Some(thread) }))
}

fn run(x: Arc<X>, mut grabber: Grabber, config: StreamConfig, sink: Arc<dyn StreamSink>, make: MakeEncoder, shared: Arc<Shared>) {
    let fps = config.fps.clamp(1, 240);
    let interval = Duration::from_secs_f64(1.0 / fps as f64);
    let mut cursor = CursorWatch::new(&x);
    let mut encoder: Option<(u32, u32, Box<dyn Encoder>)> = None;
    let mut last: Option<Frame> = None;
    let mut next = Instant::now();
    let mut ended = false;
    let mut rect_tick = 0u32;
    while !shared.stop.load(Ordering::SeqCst) {
        let now = Instant::now();
        if next > now {
            std::thread::sleep(next - now);
        }
        // A late tick is skipped, not made up: never two reads back to back.
        next = (next + interval).max(Instant::now());
        if let Some(shape) = cursor.poll(&x) {
            sink.cursor(shape);
        }
        // The rectangle every few ticks (a moved window), and at once for the Desktop's first.
        if rect_tick.is_multiple_of(4) {
            let r = grabber.rect();
            *shared.rect.lock().unwrap() = r.map(to_rect);
        }
        rect_tick = rect_tick.wrapping_add(1);
        let want_key = shared.keyframe.swap(false, Ordering::SeqCst);
        if want_key {
            bump("cap.keyRequest");
        }
        let read_at = Instant::now();
        let grabbed = grabber.grab();
        if read_at.elapsed() > interval {
            bump("cap.slowRead");
        }
        let fresh = match grabbed {
            Grab::Gone => {
                *shared.rect.lock().unwrap() = None;
                sink.ended("The window closed.".into());
                ended = true;
                break;
            }
            Grab::Hidden => {
                bump("cap.hidden");
                None
            }
            Grab::Frame(f) => Some(even(f)),
        };
        let (frame, changed) = match (fresh, last.take()) {
            (Some(f), Some(old)) => {
                let changed = f.width != old.width || f.height != old.height || f.data != old.data;
                (f, changed)
            }
            (Some(f), None) => (f, true),
            (None, Some(old)) => (old, false),
            (None, None) => {
                if want_key {
                    shared.keyframe.store(true, Ordering::SeqCst); // nothing to show yet: ask again next tick
                }
                continue;
            }
        };
        bump(if changed { "cap.changed" } else { "cap.same" });
        if changed || want_key {
            let (w, h) = (frame.width, frame.height);
            let new_size = encoder.as_ref().is_none_or(|(ew, eh, _)| (*ew, *eh) != (w, h));
            if new_size {
                encoder = None;
                match make(w, h, &config, sink.clone()) {
                    Ok(e) => encoder = Some((w, h, e)),
                    Err(e) => {
                        sink.ended(format!("The encoder did not start: {e}"));
                        ended = true;
                        break;
                    }
                }
            }
            if let Some((_, _, e)) = encoder.as_mut() {
                // A new encoder's first frame is a keyframe by itself, and is never asked for one:
                // the core's encoder marks a keyframe by an odd timestamp, and FFmpeg shifts every
                // timestamp by the first one, so an odd first one turned every frame after it into
                // a keyframe (NOTES-linux.md, "Requests to core").
                e.frame(&frame.data, w, h, want_key && !new_size);
            }
        }
        last = Some(frame);
    }
    drop(encoder);
    drop(grabber);
    let _ = ended;
}

/// The picture cropped to even sizes (4:2:0 video needs them): the last column and row go.
fn even(f: Frame) -> Frame {
    let (w, h) = (f.width & !1, f.height & !1);
    if (w, h) == (f.width, f.height) {
        return f;
    }
    let mut data = Vec::with_capacity((w * h * 4) as usize);
    for row in 0..h as usize {
        let start = row * f.width as usize * 4;
        data.extend_from_slice(&f.data[start..start + w as usize * 4]);
    }
    Frame { width: w, height: h, data }
}
