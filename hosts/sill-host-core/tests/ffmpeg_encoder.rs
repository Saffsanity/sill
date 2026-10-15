//! The FFmpeg encoder against a real ffmpeg with libx265 (skipped when there is none): BGRA and NV12
//! in, an IDR first with its parameter sets, deltas after, a keyframe on request while frames come,
//! and one for a still source (the last frame encoded again).

use sill_host_core::ffmpeg::{FfmpegConfig, FfmpegEncoder, HevcEncoder, PixelFormat};
use sill_host_core::platform::{CursorShape, EncodedFrame, StreamSink};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

#[derive(Default)]
struct Collect {
    frames: Mutex<Vec<(Instant, EncodedFrame)>>,
    ended: Mutex<Option<String>>,
}

impl StreamSink for Collect {
    fn frame(&self, f: EncodedFrame) {
        self.frames.lock().unwrap().push((Instant::now(), f));
    }
    fn cursor(&self, _: CursorShape) {}
    fn ended(&self, reason: String) {
        *self.ended.lock().unwrap() = Some(reason);
    }
}

fn have_libx265() -> bool {
    std::process::Command::new("ffmpeg")
        .args(["-hide_banner", "-encoders"])
        .output()
        .map(|o| String::from_utf8_lossy(&o.stdout).contains("libx265"))
        .unwrap_or(false)
}

fn wait_for(c: &Collect, n: usize, secs: u64) -> bool {
    let until = Instant::now() + Duration::from_secs(secs);
    while Instant::now() < until {
        if c.frames.lock().unwrap().len() >= n {
            return true;
        }
        std::thread::sleep(Duration::from_millis(5));
    }
    false
}

fn frame(fmt: PixelFormat, w: u32, h: u32, shade: u8) -> Vec<u8> {
    let mut v = vec![shade; fmt.frame_len(w, h)];
    if fmt == PixelFormat::Nv12 {
        let y = (w * h) as usize;
        v[y..].fill(128);
    }
    v
}

fn run(fmt: PixelFormat) {
    if !have_libx265() {
        eprintln!("no ffmpeg with libx265: skipped");
        return;
    }
    let (w, h) = (320, 192);
    let sink = Arc::new(Collect::default());
    let enc = FfmpegEncoder::start(FfmpegConfig::new(HevcEncoder::Libx265, fmt, w, h, 30, 2_000_000), sink.clone()).unwrap();
    // A moving picture: one frame in, one frame out, each promptly.
    for i in 0..10u8 {
        let sent = Instant::now();
        enc.submit(frame(fmt, w, h, 20 + i * 20));
        assert!(wait_for(&sink, i as usize + 1, 5), "frame {i} never came out ({:?})", sink.ended.lock().unwrap());
        let latency = sink.frames.lock().unwrap().last().unwrap().0 - sent;
        assert!(latency < Duration::from_millis(if i == 0 { 2000 } else { 500 }), "frame {i} took {latency:?}");
    }
    {
        let f = sink.frames.lock().unwrap();
        assert!(f[0].1.keyframe, "the first frame is a keyframe");
        let ps = f[0].1.parameter_sets.as_ref().expect("parameter sets with the first frame");
        assert_eq!(ps.len(), 3);
        assert_eq!(ps.iter().map(|p| (p[0] >> 1) & 0x3F).collect::<Vec<_>>(), vec![32, 33, 34]);
        assert!(f[1..].iter().all(|(_, x)| !x.keyframe && x.parameter_sets.is_none()), "deltas after it");
        assert!(f.iter().all(|(_, x)| x.width == w && x.height == h && !x.nals.is_empty()));
    }
    // A keyframe asked for while frames come: the next one.
    enc.request_keyframe();
    enc.submit(frame(fmt, w, h, 7));
    assert!(wait_for(&sink, 11, 5));
    assert!(sink.frames.lock().unwrap()[10].1.keyframe, "the requested keyframe");
    // A still source: no new frame; the last one comes again, as a keyframe, about 50 ms later.
    enc.submit(frame(fmt, w, h, 9));
    assert!(wait_for(&sink, 12, 5));
    let asked = Instant::now();
    enc.request_keyframe();
    assert!(wait_for(&sink, 13, 5), "no keyframe for a still source");
    let (at, f) = sink.frames.lock().unwrap()[12].clone();
    assert!(f.keyframe && f.parameter_sets.is_some());
    assert!(at - asked >= Duration::from_millis(40), "re-encoded after the 50 ms wait");
    assert!(sink.ended.lock().unwrap().is_none());
    enc.stop();
}

#[test]
fn libx265_bgra() {
    run(PixelFormat::Bgra);
}

#[test]
fn libx265_nv12() {
    run(PixelFormat::Nv12);
}

/// A keyframe asked for before the encoder's first frame (a device connecting as a stream starts):
/// the first frame is the IDR that answers it, and the frames after it stay deltas until the next
/// request. Before the fix every frame came out an IDR.
#[test]
fn a_request_before_the_first_frame() {
    if !have_libx265() {
        eprintln!("no ffmpeg with libx265: skipped");
        return;
    }
    let (w, h) = (320, 192);
    let fmt = PixelFormat::Nv12;
    let sink = Arc::new(Collect::default());
    let enc = FfmpegEncoder::start(FfmpegConfig::new(HevcEncoder::Libx265, fmt, w, h, 30, 2_000_000), sink.clone()).unwrap();
    enc.request_keyframe();
    for i in 0..12u8 {
        enc.submit(frame(fmt, w, h, 10 + i * 15));
        assert!(wait_for(&sink, i as usize + 1, 5), "frame {i} never came out");
        if i == 7 {
            enc.request_keyframe();
        }
    }
    let keys: Vec<usize> = sink.frames.lock().unwrap().iter().enumerate().filter(|(_, (_, f))| f.keyframe).map(|(i, _)| i).collect();
    assert_eq!(keys, vec![0, 8], "keyframes: the first, and the one requested after frame 7");
    enc.stop();
}
