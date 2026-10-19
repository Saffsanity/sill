//! HEVC through FFmpeg, run as a subprocess (never linked: x265 inside it is GPL). Which encoder a
//! machine has (`probe`): hevc_vaapi (Intel and AMD, through /dev/dri) or hevc_nvenc (NVIDIA) when a
//! one-frame test encode works, else libx265 on the CPU.
//!
//! Streams use the core's FFmpeg encoder (`sill_host_core::ffmpeg::FfmpegEncoder`: BGRA in through
//! Matroska, HEVC access units out through NUT, one frame in flight, keyframes on request), fed by
//! `core`, which scales each picture to the stream's size first. `FileEncoder` (the self-test's)
//! writes a stream to a file with `args`, this module's own command line.

use std::io::Write;
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::{Arc, OnceLock};

use sill_host_core::platform::{StreamConfig, StreamSink};

use super::stream::{Encoder, MakeEncoder};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Kind {
    Vaapi,
    Nvenc,
    X265,
}

impl Kind {
    pub fn name(self) -> &'static str {
        match self {
            Kind::Vaapi => "hevc_vaapi",
            Kind::Nvenc => "hevc_nvenc",
            Kind::X265 => "libx265",
        }
    }
}

/// The render node VAAPI uses ($SILL_VAAPI_DEVICE, else the first one).
pub fn vaapi_device() -> String {
    std::env::var("SILL_VAAPI_DEVICE").unwrap_or_else(|_| "/dev/dri/renderD128".into())
}

/// The encoder this machine has, decided once: $SILL_ENCODER (a Kind's name) if set, else the first
/// that encodes a test frame of hevc_vaapi, hevc_nvenc, libx265. None without ffmpeg or any of them.
pub fn probe() -> Option<Kind> {
    static PROBED: OnceLock<Option<Kind>> = OnceLock::new();
    *PROBED.get_or_init(|| {
        let listed = Command::new("ffmpeg").args(["-hide_banner", "-encoders"]).output().ok()?;
        let listed = String::from_utf8_lossy(&listed.stdout).into_owned();
        let has = |name: &str| listed.lines().any(|l| l.split_whitespace().nth(1) == Some(name));
        let forced = std::env::var("SILL_ENCODER").ok();
        for kind in [Kind::Vaapi, Kind::Nvenc, Kind::X265] {
            if forced.as_deref().is_some_and(|f| f != kind.name()) {
                continue;
            }
            if has(kind.name()) && test_encode(kind) {
                return Some(kind);
            }
        }
        None
    })
}

fn test_encode(kind: Kind) -> bool {
    if kind == Kind::Vaapi && !std::path::Path::new(&vaapi_device()).exists() {
        return false;
    }
    let mut args: Vec<String> = vec!["-hide_banner".into(), "-loglevel".into(), "error".into()];
    if kind == Kind::Vaapi {
        args.extend(["-vaapi_device".into(), vaapi_device()]);
    }
    args.extend(["-f", "lavfi", "-i", "color=black:s=256x256:r=30", "-frames:v", "1"].map(String::from));
    if kind == Kind::Vaapi {
        args.extend(["-vf".into(), "format=nv12,hwupload".into()]);
    }
    args.extend(["-c:v".into(), kind.name().into(), "-f".into(), "null".into(), "-".into()]);
    Command::new("ffmpeg").args(&args).stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null()).status().is_ok_and(|s| s.success())
}

/// The encoded size for a picture of width×height at `scale`: rounded down to even, at least 2.
pub fn output_size(width: u32, height: u32, scale: f64) -> (u32, u32) {
    let s = if scale.is_finite() && scale > 0.0 { scale.min(1.0) } else { 1.0 };
    let w = (((width as f64) * s) as u32 & !1).max(2);
    let h = (((height as f64) * s) as u32 & !1).max(2);
    (w, h)
}

/// FFmpeg's arguments for raw BGRA pictures of width×height on stdin to HEVC, real time, no
/// B-frames, a keyframe every 4 s at most (the Mac's safety interval), parameter sets with every
/// keyframe and an access unit delimiter before every picture. The output's format and destination
/// are the caller's.
pub fn args(kind: Kind, width: u32, height: u32, config: &StreamConfig) -> Vec<String> {
    let (ow, oh) = output_size(width, height, config.scale);
    let fps = config.fps.clamp(1, 240);
    let gop = fps * 4;
    let rate = config.bitrate.max(500_000);
    let mut a: Vec<String> = vec!["-hide_banner".into(), "-loglevel".into(), "error".into(), "-nostdin".into()];
    if kind == Kind::Vaapi {
        a.extend(["-vaapi_device".into(), vaapi_device()]);
    }
    a.extend(
        [
            "-f".into(),
            "rawvideo".into(),
            "-pix_fmt".into(),
            "bgra".into(),
            "-s".into(),
            format!("{width}x{height}"),
            "-r".into(),
            fps.to_string(),
            "-i".into(),
            "pipe:0".into(),
        ],
    );
    let scaled = (ow, oh) != (width, height);
    match kind {
        Kind::Vaapi => {
            let mut vf = "format=nv12,hwupload".to_string();
            if scaled {
                vf.push_str(&format!(",scale_vaapi=w={ow}:h={oh}"));
            }
            a.extend(["-vf".into(), vf, "-c:v".into(), "hevc_vaapi".into(), "-bf".into(), "0".into()]);
            a.extend(["-g".into(), gop.to_string(), "-b:v".into(), rate.to_string(), "-maxrate".into(), rate.to_string()]);
            a.extend(["-aud".into(), "1".into()]);
        }
        Kind::Nvenc => {
            if scaled {
                a.extend(["-vf".into(), format!("scale={ow}:{oh}:flags=bilinear")]);
            }
            a.extend(["-c:v", "hevc_nvenc", "-preset", "p1", "-tune", "ull", "-zerolatency", "1", "-delay", "0", "-bf", "0", "-rc", "cbr"].map(String::from));
            a.extend(["-g".into(), gop.to_string(), "-b:v".into(), rate.to_string(), "-aud".into(), "1".into()]);
            a.extend(["-pix_fmt".into(), "yuv420p".into()]);
        }
        Kind::X265 => {
            if scaled {
                a.extend(["-vf".into(), format!("scale={ow}:{oh}:flags=bilinear")]);
            }
            let preset = if config.prioritize_speed { "ultrafast" } else { "superfast" };
            // VBV over one frame's worth of bits: the rate holds per frame, as real time needs.
            let buf = (rate / fps).max(50_000) / 1000;
            let kbps = rate / 1000;
            a.extend(["-c:v".into(), "libx265".into(), "-preset".into(), preset.into(), "-tune".into(), "zerolatency".into()]);
            a.extend(["-pix_fmt".into(), "yuv420p".into(), "-b:v".into(), rate.to_string()]);
            a.extend([
                "-x265-params".into(),
                format!("keyint={gop}:min-keyint={gop}:bframes=0:repeat-headers=1:aud=1:vbv-maxrate={kbps}:vbv-bufsize={buf}:log-level=error"),
            ]);
        }
    }
    a
}

/// Writes a stream to a file (the self-test), with a live stream's settings.
pub struct FileEncoder {
    child: Child,
    stdin: Option<ChildStdin>,
    pub frames: u64,
}

impl FileEncoder {
    pub fn new(kind: Kind, width: u32, height: u32, config: &StreamConfig, path: &str) -> Result<FileEncoder, String> {
        let mut a = args(kind, width, height, config);
        a.extend(["-f".into(), "hevc".into(), "-y".into(), path.into()]);
        let mut child = Command::new("ffmpeg").args(&a).stdin(Stdio::piped()).stdout(Stdio::null()).spawn().map_err(|e| format!("ffmpeg: {e}"))?;
        let stdin = child.stdin.take();
        Ok(FileEncoder { child, stdin, frames: 0 })
    }

    pub fn finish(mut self) -> Result<(), String> {
        drop(self.stdin.take());
        let status = self.child.wait().map_err(|e| e.to_string())?;
        if status.success() {
            Ok(())
        } else {
            Err(format!("ffmpeg exited {status}"))
        }
    }
}

impl Encoder for FileEncoder {
    fn frame(&mut self, bgra: &[u8], _width: u32, _height: u32, _keyframe: bool) {
        if let Some(stdin) = self.stdin.as_mut() {
            if stdin.write_all(bgra).is_ok() {
                self.frames += 1;
            }
        }
    }
}

/// Counters for the self-test: encoders started, keyframes asked of them, pictures submitted.
pub static STARTED: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
pub static KEYS_ASKED: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
pub static SUBMITTED: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);

/// The core's encoder for each stream, `kind` on this machine.
pub fn core(kind: Kind) -> MakeEncoder {
    use sill_host_core::ffmpeg::{FfmpegConfig, FfmpegEncoder, HevcEncoder, PixelFormat};
    Arc::new(move |w: u32, h: u32, c: &StreamConfig, sink: Arc<dyn StreamSink>| -> Result<Box<dyn Encoder>, String> {
        let (ow, oh) = output_size(w, h, c.scale);
        let encoder = match kind {
            Kind::Vaapi => HevcEncoder::Vaapi { device: vaapi_device() },
            Kind::Nvenc => HevcEncoder::Nvenc,
            Kind::X265 => HevcEncoder::Libx265,
        };
        let mut cfg = FfmpegConfig::new(encoder, PixelFormat::Bgra, ow, oh, c.fps, c.bitrate);
        cfg.prioritize_speed = c.prioritize_speed;
        let enc = FfmpegEncoder::start(cfg, sink)?;
        STARTED.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        Ok(Box::new(CoreEncoder { enc, out: (ow, oh) }))
    })
}

struct CoreEncoder {
    enc: sill_host_core::ffmpeg::FfmpegEncoder,
    out: (u32, u32),
}

impl Encoder for CoreEncoder {
    fn frame(&mut self, bgra: &[u8], width: u32, height: u32, keyframe: bool) {
        if keyframe {
            KEYS_ASKED.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
            self.enc.request_keyframe();
        }
        SUBMITTED.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        let (ow, oh) = self.out;
        let data = if (ow, oh) == (width, height) {
            bgra.to_vec()
        } else {
            crate::scale::downscale_bgra(bgra, width, height, ow, oh)
        };
        self.enc.submit(data);
    }
}

/// No encoder on this machine: every stream refuses with this.
pub fn unavailable() -> MakeEncoder {
    Arc::new(|_w: u32, _h: u32, _c: &StreamConfig, _s: Arc<dyn StreamSink>| -> Result<Box<dyn Encoder>, String> {
        Err("no HEVC encoder: install ffmpeg with libx265, or a VAAPI or NVENC driver (NOTES-linux.md)".into())
    })
}
