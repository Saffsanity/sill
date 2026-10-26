//! An HEVC encoder that runs FFmpeg as a subprocess (no FFmpeg code linked in: LGPL/GPL stay in
//! their own process). Raw BGRA or NV12 frames go in through stdin, HEVC access units come out as
//! the trait's `EncodedFrame`s: VPS/SPS/PPS split out, keyframes flagged, zero-latency tuning, no
//! B-frames, a keyframe on request.
//!
//! How it is wired, and why (measured with FFmpeg 9.0 on macOS, 2026-10-14):
//! - In: Matroska on stdin, one cluster per frame with its own timestamp (microseconds). A raw
//!   video pipe has no per-frame timestamps, and FFmpeg's CLI has no command to force a keyframe at
//!   run time, so a keyframe request rides on the timestamp: an odd microsecond means "keyframe",
//!   and `-force_key_frames expr:eq(mod(floor(t*1000000+0.5),2),1)` turns it into an IDR. Every
//!   other frame has an even timestamp. (Raw input through Matroska adds no delay: a frame comes out
//!   10–15 ms after it went in at 1080p with libx265 ultrafast.)
//! - Out: NUT on stdout. Raw Annex-B (`-f hevc`) has no packet boundaries, so a frame would only be
//!   known complete when the next one starts (a whole frame of latency, and the last frame of a
//!   still window stuck); AVI pads timestamp gaps with empty frames and, through `setts`, delays a
//!   frame; fragmented MP4 and Matroska write a frame only when the next arrives. NUT writes every
//!   packet at once with its size.
//! - No `-fflags nobuffer`: with it the Matroska demuxer holds the first frame until the second
//!   arrives (a still source would never start).
//! - At most `max_in_flight` frames are inside FFmpeg (1 by default); a newer frame replaces one
//!   still waiting to go in (`enc.mailboxDrop`), so a slow encoder costs frames, never latency.
//! - A keyframe asked for while the source is still: the last frame is sent again, flagged, 50 ms
//!   after the request if nothing newer came.

use crate::platform::{EncodedFrame, StreamSink};
use crate::stats::bump;
use crate::log;
use sill_protocol::blobs::{hevc_nal_type, nal_type, split_annex_b};
use std::io::{self, BufRead, BufReader, Read, Write};
use std::path::PathBuf;
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Condvar, Mutex, OnceLock};
use std::thread::JoinHandle;
use std::time::{Duration, Instant};

/// Which FFmpeg encoder to run.
#[derive(Clone, Debug, PartialEq)]
pub enum HevcEncoder {
    /// x265, in software (any machine; CPU heavy at large sizes).
    Libx265,
    /// VAAPI (Intel, AMD on Linux); the render node, e.g. "/dev/dri/renderD128".
    Vaapi { device: String },
    /// NVIDIA NVENC.
    Nvenc,
    /// Apple VideoToolbox (macOS; shares the Mac's one hardware encoder engine).
    VideoToolbox,
}

impl HevcEncoder {
    /// "libx265", "hevc_vaapi[:/dev/dri/renderD128]", "hevc_nvenc", "hevc_videotoolbox".
    pub fn parse(s: &str) -> Option<HevcEncoder> {
        match s {
            "libx265" | "x265" => Some(HevcEncoder::Libx265),
            "hevc_nvenc" | "nvenc" => Some(HevcEncoder::Nvenc),
            "hevc_videotoolbox" | "videotoolbox" => Some(HevcEncoder::VideoToolbox),
            _ => {
                let rest = s.strip_prefix("hevc_vaapi").or_else(|| s.strip_prefix("vaapi"))?;
                let device = rest.strip_prefix(':').unwrap_or("/dev/dri/renderD128");
                let device = if device.is_empty() { "/dev/dri/renderD128" } else { device };
                Some(HevcEncoder::Vaapi { device: device.to_string() })
            }
        }
    }

    pub fn name(&self) -> &'static str {
        match self {
            HevcEncoder::Libx265 => "libx265",
            HevcEncoder::Vaapi { .. } => "hevc_vaapi",
            HevcEncoder::Nvenc => "hevc_nvenc",
            HevcEncoder::VideoToolbox => "hevc_videotoolbox",
        }
    }
}

/// The raw frames handed to `submit`, tightly packed (no row padding).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PixelFormat {
    /// 4 bytes a pixel, B G R A.
    Bgra,
    /// The Y plane (width × height), then the interleaved UV plane (width × height / 2).
    Nv12,
}

impl PixelFormat {
    pub fn frame_len(self, width: u32, height: u32) -> usize {
        match self {
            PixelFormat::Bgra => width as usize * height as usize * 4,
            PixelFormat::Nv12 => width as usize * height as usize * 3 / 2,
        }
    }

    fn fourcc(self) -> &'static [u8; 4] {
        match self {
            PixelFormat::Bgra => b"BGRA",
            PixelFormat::Nv12 => b"NV12",
        }
    }
}

#[derive(Clone, Debug)]
pub struct FfmpegConfig {
    /// The ffmpeg executable: SILL_FFMPEG, else "ffmpeg" on the PATH.
    pub ffmpeg: PathBuf,
    pub encoder: HevcEncoder,
    pub input: PixelFormat,
    /// The frames' size, which is also the encoded size (scale before submitting). Even numbers.
    pub width: u32,
    pub height: u32,
    pub fps: u32,
    /// Bits per second.
    pub bitrate: u32,
    pub prioritize_speed: bool,
    /// The safety keyframe interval, seconds (4, as the Mac's encoder).
    pub keyframe_interval_secs: u32,
    /// Frames inside FFmpeg at once (1: lowest latency; 2 overlaps conversion and encoding).
    pub max_in_flight: usize,
}

impl FfmpegConfig {
    pub fn new(encoder: HevcEncoder, input: PixelFormat, width: u32, height: u32, fps: u32, bitrate: u32) -> FfmpegConfig {
        FfmpegConfig {
            ffmpeg: std::env::var_os("SILL_FFMPEG").map(PathBuf::from).unwrap_or_else(|| PathBuf::from("ffmpeg")),
            encoder,
            input,
            width: width & !1,
            height: height & !1,
            fps: fps.max(1),
            bitrate,
            prioritize_speed: false,
            keyframe_interval_secs: 4,
            max_in_flight: 1,
        }
    }
}

/// FFmpeg's version, read once: (major, minor); None when it could not be run or read.
type VersionCache = Mutex<std::collections::HashMap<PathBuf, Option<(u32, u32)>>>;

pub fn ffmpeg_version(ffmpeg: &PathBuf) -> Option<(u32, u32)> {
    static CACHE: OnceLock<VersionCache> = OnceLock::new();
    let cache = CACHE.get_or_init(|| Mutex::new(Default::default()));
    if let Some(v) = cache.lock().unwrap().get(ffmpeg) {
        return *v;
    }
    let out = Command::new(ffmpeg).args(["-hide_banner", "-version"]).output().ok();
    let v = out.and_then(|o| {
        let text = String::from_utf8_lossy(&o.stdout).to_string();
        let first = text.lines().next()?.to_string();
        let ver = first.split_whitespace().nth(2)?.trim_start_matches('n').to_string();
        let mut parts = ver.split(|c: char| !c.is_ascii_digit());
        let major: u32 = parts.next()?.parse().ok()?;
        let minor: u32 = parts.next().and_then(|m| m.parse().ok()).unwrap_or(0);
        Some((major, minor))
    });
    cache.lock().unwrap().insert(ffmpeg.clone(), v);
    v
}

/// The command line (without the executable).
pub fn arguments(cfg: &FfmpegConfig) -> Vec<String> {
    let mut a: Vec<String> = Vec::new();
    let mut push = |v: &[&str]| a.extend(v.iter().map(|s| s.to_string()));
    push(&["-hide_banner", "-nostats", "-loglevel", "error"]);
    if let HevcEncoder::Vaapi { device } = &cfg.encoder {
        push(&["-init_hw_device", &format!("vaapi=sillva:{device}"), "-filter_hw_device", "sillva"]);
    }
    push(&["-probesize", "32", "-analyzeduration", "0", "-f", "matroska", "-i", "pipe:0", "-an"]);
    // Every frame as it comes (variable rate), timestamps kept to the microsecond.
    let new_fps_mode = ffmpeg_version(&cfg.ffmpeg).map(|(ma, mi)| ma > 5 || (ma == 5 && mi >= 1)).unwrap_or(true);
    if new_fps_mode {
        push(&["-fps_mode", "passthrough"]);
    } else {
        push(&["-vsync", "passthrough"]);
    }
    push(&["-enc_time_base", "1:1000000", "-force_key_frames", "expr:eq(mod(floor(t*1000000+0.5),2),1)"]);
    let b = cfg.bitrate.max(100_000).to_string();
    let keyint = (cfg.fps * cfg.keyframe_interval_secs.max(1)).to_string();
    match &cfg.encoder {
        HevcEncoder::Libx265 => {
            let params = format!(
                "keyint={keyint}:min-keyint={keyint}:bframes=0:open-gop=0:repeat-headers=1:scenecut=0:info=0:log-level=error:rc-lookahead=0:frame-threads=1"
            );
            push(&["-c:v", "libx265", "-preset", "ultrafast", "-tune", "zerolatency", "-forced-idr", "1", "-g", &keyint]);
            push(&["-pix_fmt", "yuv420p", "-b:v", &b, "-maxrate", &b, "-bufsize", &b, "-x265-params", &params]);
        }
        HevcEncoder::Nvenc => {
            let half = (cfg.bitrate / 2).max(100_000).to_string();
            push(&["-pix_fmt", "nv12", "-c:v", "hevc_nvenc", "-preset", if cfg.prioritize_speed { "p1" } else { "p2" }]);
            push(&["-tune", "ull", "-zerolatency", "1", "-delay", "0", "-rc", "cbr", "-bf", "0", "-g", &keyint, "-forced-idr", "1"]);
            push(&["-b:v", &b, "-maxrate", &b, "-bufsize", &half]);
        }
        HevcEncoder::Vaapi { .. } => {
            push(&["-vf", "format=nv12,hwupload", "-c:v", "hevc_vaapi", "-bf", "0", "-g", &keyint, "-rc_mode", "CBR"]);
            push(&["-b:v", &b, "-maxrate", &b]);
        }
        HevcEncoder::VideoToolbox => {
            push(&["-pix_fmt", "nv12", "-c:v", "hevc_videotoolbox", "-realtime", "1", "-allow_sw", "0"]);
            push(&["-prio_speed", if cfg.prioritize_speed { "1" } else { "0" }, "-bf", "0", "-g", &keyint, "-b:v", &b]);
        }
    }
    push(&["-flush_packets", "1", "-f", "nut", "pipe:1"]);
    a
}

// MARK: Matroska in

fn ebml_size(n: u64) -> [u8; 8] {
    // Always the 8-byte form: 0x01 then 7 bytes.
    let mut b = n.to_be_bytes();
    b[0] = 0x01;
    b
}

fn ebml_el(id: &[u8], data: &[u8]) -> Vec<u8> {
    let mut v = id.to_vec();
    v.extend_from_slice(&ebml_size(data.len() as u64));
    v.extend_from_slice(data);
    v
}

fn ebml_uint(id: &[u8], n: u64) -> Vec<u8> {
    let bytes = n.to_be_bytes();
    let skip = bytes.iter().take_while(|b| **b == 0).count().min(7);
    ebml_el(id, &bytes[skip..])
}

/// The stream's header: EBML, a Segment of unknown size, Info (timestamps in µs), one raw video
/// track whose DefaultDuration gives the encoder its frame rate. Without it the encoder's rate
/// control takes the microsecond time base for the frame rate and gives each frame a millionth of
/// a second's bits (measured: 280-byte frames at 15 Mbps).
pub fn mkv_header(fmt: PixelFormat, width: u32, height: u32, fps: u32) -> Vec<u8> {
    let ebml = ebml_el(
        &[0x1A, 0x45, 0xDF, 0xA3],
        &[
            ebml_uint(&[0x42, 0x86], 1),
            ebml_uint(&[0x42, 0xF7], 1),
            ebml_uint(&[0x42, 0xF2], 4),
            ebml_uint(&[0x42, 0xF3], 8),
            ebml_el(&[0x42, 0x82], b"matroska"),
            ebml_uint(&[0x42, 0x87], 4),
            ebml_uint(&[0x42, 0x85], 2),
        ]
        .concat(),
    );
    let mut v = ebml;
    v.extend_from_slice(&[0x18, 0x53, 0x80, 0x67, 0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]);
    v.extend(ebml_el(&[0x15, 0x49, 0xA9, 0x66], &ebml_uint(&[0x2A, 0xD7, 0xB1], 1000)));
    let video = ebml_el(
        &[0xE0],
        &[ebml_uint(&[0xB0], width as u64), ebml_uint(&[0xBA], height as u64), ebml_el(&[0x2E, 0xB5, 0x24], fmt.fourcc())].concat(),
    );
    let track = ebml_el(
        &[0xAE],
        &[
            ebml_uint(&[0xD7], 1),
            ebml_uint(&[0x73, 0xC5], 1),
            ebml_uint(&[0x83], 1),
            ebml_uint(&[0x23, 0xE3, 0x83], (1_000_000_000f64 / fps.max(1) as f64).round() as u64),
            ebml_el(&[0x86], b"V_UNCOMPRESSED"),
            video,
        ]
        .concat(),
    );
    v.extend(ebml_el(&[0x16, 0x54, 0xAE, 0x6B], &track));
    v
}

/// One frame: a Cluster (known size) with its timestamp and one SimpleBlock.
fn mkv_cluster_head(pts_us: u64, frame_len: usize) -> Vec<u8> {
    let tc = ebml_uint(&[0xE7], pts_us);
    let block_len = 4 + frame_len;
    let mut block_head = vec![0xA3];
    block_head.extend_from_slice(&ebml_size(block_len as u64));
    block_head.extend_from_slice(&[0x81, 0x00, 0x00, 0x80]);
    let body_len = tc.len() + block_head.len() + frame_len;
    let mut v = vec![0x1F, 0x43, 0xB6, 0x75];
    v.extend_from_slice(&ebml_size(body_len as u64));
    v.extend(tc);
    v.extend(block_head);
    v
}

// MARK: NUT out

const ID_STRING: &[u8] = b"nut/multimedia container\0";
const MAIN_STARTCODE: u64 = 0x7A561F5F04AD + ((((b'N' as u64) << 8) + b'M' as u64) << 48);
const STREAM_STARTCODE: u64 = 0x11405BF2F9DB + ((((b'N' as u64) << 8) + b'S' as u64) << 48);

const FLAG_CODED_PTS: u64 = 8;
const FLAG_STREAM_ID: u64 = 16;
const FLAG_SIZE_MSB: u64 = 32;
const FLAG_CHECKSUM: u64 = 64;
const FLAG_RESERVED: u64 = 128;
const FLAG_SM_DATA: u64 = 256;
const FLAG_HEADER_IDX: u64 = 1024;
const FLAG_MATCH_TIME: u64 = 2048;
const FLAG_CODED: u64 = 4096;
const FLAG_INVALID: u64 = 8192;

#[derive(Clone, Copy, Default)]
struct FrameCode {
    flags: u64,
    stream_id: u64,
    size_mul: u64,
    size_lsb: u64,
    reserved: u64,
    header_idx: u64,
}

/// A NUT demuxer for exactly what FFmpeg's NUT muxer writes for one video stream.
pub struct NutReader<R: Read> {
    r: R,
    codes: [FrameCode; 256],
    headers: Vec<Vec<u8>>,
    version: u64,
    /// Each stream's codec-specific data (the encoder's global header: VPS/SPS/PPS).
    pub extradata: Vec<Vec<u8>>,
    started: bool,
}

/// One packet: its stream and bytes.
pub struct NutPacket {
    pub stream: u64,
    pub data: Vec<u8>,
}

fn bad(what: &str) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, format!("NUT: {what}"))
}

struct Cursor<'a> {
    b: &'a [u8],
    i: usize,
}

impl Cursor<'_> {
    fn byte(&mut self) -> io::Result<u8> {
        let v = *self.b.get(self.i).ok_or_else(|| bad("short header"))?;
        self.i += 1;
        Ok(v)
    }
    fn v(&mut self) -> io::Result<u64> {
        let mut val: u64 = 0;
        for _ in 0..10 {
            let b = self.byte()?;
            val = (val << 7) | (b & 0x7F) as u64;
            if b & 0x80 == 0 {
                return Ok(val);
            }
        }
        Err(bad("varint too long"))
    }
    fn s(&mut self) -> io::Result<i64> {
        let v = self.v()? as i64 + 1;
        Ok(if v & 1 == 1 { -(v >> 1) } else { v >> 1 })
    }
    fn bytes(&mut self, n: usize) -> io::Result<&[u8]> {
        let end = self.i.checked_add(n).filter(|e| *e <= self.b.len()).ok_or_else(|| bad("short field"))?;
        let s = &self.b[self.i..end];
        self.i = end;
        Ok(s)
    }
    fn left(&self) -> usize {
        self.b.len() - self.i
    }
}

impl<R: Read> NutReader<R> {
    pub fn new(r: R) -> NutReader<R> {
        NutReader { r, codes: [FrameCode::default(); 256], headers: vec![Vec::new()], version: 3, extradata: Vec::new(), started: false }
    }

    fn byte(&mut self) -> io::Result<u8> {
        let mut b = [0u8; 1];
        self.r.read_exact(&mut b)?;
        Ok(b[0])
    }

    fn v(&mut self) -> io::Result<u64> {
        let mut val: u64 = 0;
        for _ in 0..10 {
            let b = self.byte()?;
            val = (val << 7) | (b & 0x7F) as u64;
            if b & 0x80 == 0 {
                return Ok(val);
            }
        }
        Err(bad("varint too long"))
    }

    fn s(&mut self) -> io::Result<i64> {
        let v = self.v()? as i64 + 1;
        Ok(if v & 1 == 1 { -(v >> 1) } else { v >> 1 })
    }

    fn main_header(&mut self, body: &[u8]) -> io::Result<()> {
        let mut c = Cursor { b: body, i: 0 };
        self.version = c.v()?;
        if self.version > 3 {
            c.v()?;
        }
        let _streams = c.v()?;
        let _max_distance = c.v()?;
        let tbs = c.v()?;
        for _ in 0..tbs {
            c.v()?;
            c.v()?;
        }
        // Fields left out of a group keep the previous group's value (pts delta, multiplier,
        // stream, header index); size and reserved count reset to 0.
        let (mut tmp_mul, mut tmp_stream, mut tmp_head_idx) = (1u64, 0u64, 0u64);
        let mut i = 0usize;
        while i < 256 {
            let tmp_flags = c.v()?;
            let tmp_fields = c.v()?;
            if tmp_fields > 0 {
                c.s()?; // pts delta: timestamps are not needed here
            }
            if tmp_fields > 1 {
                tmp_mul = c.v()?;
            }
            if tmp_fields > 2 {
                tmp_stream = c.v()?;
            }
            let tmp_size = if tmp_fields > 3 { c.v()? } else { 0 };
            let tmp_res = if tmp_fields > 4 { c.v()? } else { 0 };
            let count = if tmp_fields > 5 { c.v()? } else { tmp_mul.wrapping_sub(tmp_size) };
            if tmp_fields > 6 {
                c.s()?;
            }
            if tmp_fields > 7 {
                tmp_head_idx = c.v()?;
            }
            for _ in 8..tmp_fields {
                c.v()?;
            }
            if count == 0 || count > 256 {
                return Err(bad("frame code count"));
            }
            let mut j = 0u64;
            while j < count && i < 256 {
                if i == b'N' as usize {
                    self.codes[i] = FrameCode { flags: FLAG_INVALID, ..Default::default() };
                    i += 1;
                    continue;
                }
                self.codes[i] = FrameCode {
                    flags: tmp_flags,
                    stream_id: tmp_stream,
                    size_mul: tmp_mul,
                    size_lsb: tmp_size + j,
                    reserved: tmp_res,
                    header_idx: tmp_head_idx,
                };
                i += 1;
                j += 1;
            }
        }
        self.headers = vec![Vec::new()];
        if c.left() > 4 {
            let count = c.v()? + 1;
            for _ in 1..count {
                let len = c.v()? as usize;
                self.headers.push(c.bytes(len)?.to_vec());
            }
        }
        Ok(())
    }

    fn stream_header(&mut self, body: &[u8]) -> io::Result<()> {
        let mut c = Cursor { b: body, i: 0 };
        let id = c.v()? as usize;
        let _class = c.v()?;
        let fourcc_len = c.v()? as usize;
        c.bytes(fourcc_len)?;
        c.v()?; // time base id
        c.v()?; // msb_pts_shift
        c.v()?; // max_pts_distance
        c.v()?; // decode_delay
        c.v()?; // stream flags
        let n = c.v()? as usize;
        let extra = c.bytes(n)?.to_vec();
        if self.extradata.len() <= id {
            self.extradata.resize(id + 1, Vec::new());
        }
        self.extradata[id] = extra;
        Ok(())
    }

    /// The next frame, skipping headers, syncpoints, info and the index. None at the end.
    pub fn next_packet(&mut self) -> io::Result<Option<NutPacket>> {
        if !self.started {
            let mut id = [0u8; 25];
            self.r.read_exact(&mut id)?;
            if id != ID_STRING {
                return Err(bad("not a NUT stream"));
            }
            self.started = true;
        }
        loop {
            let first = match self.byte() {
                Ok(b) => b,
                Err(e) if e.kind() == io::ErrorKind::UnexpectedEof => return Ok(None),
                Err(e) => return Err(e),
            };
            if first == b'N' {
                let mut rest = [0u8; 7];
                self.r.read_exact(&mut rest)?;
                let mut sc = [0u8; 8];
                sc[0] = first;
                sc[1..].copy_from_slice(&rest);
                let startcode = u64::from_be_bytes(sc);
                let forward = self.v()? as usize;
                if forward > 4096 {
                    let mut ck = [0u8; 4];
                    self.r.read_exact(&mut ck)?;
                }
                if forward > 64 << 20 {
                    return Err(bad("packet too large"));
                }
                let mut body = vec![0u8; forward];
                self.r.read_exact(&mut body)?;
                match startcode {
                    MAIN_STARTCODE => self.main_header(&body)?,
                    STREAM_STARTCODE => self.stream_header(&body)?,
                    _ => {}
                }
                continue;
            }
            let code = self.codes[first as usize];
            let mut flags = code.flags;
            if flags & FLAG_INVALID != 0 {
                return Err(bad("invalid frame code"));
            }
            if flags & FLAG_CODED != 0 {
                flags ^= self.v()?;
            }
            let mut stream = code.stream_id;
            if flags & FLAG_STREAM_ID != 0 {
                stream = self.v()?;
            }
            if flags & FLAG_CODED_PTS != 0 {
                self.v()?;
            }
            let mut size = code.size_lsb;
            if flags & FLAG_SIZE_MSB != 0 {
                size += code.size_mul * self.v()?;
            }
            if flags & FLAG_MATCH_TIME != 0 {
                self.s()?;
            }
            let mut header_idx = code.header_idx;
            if flags & FLAG_HEADER_IDX != 0 {
                header_idx = self.v()?;
            }
            let mut reserved = code.reserved;
            if flags & FLAG_RESERVED != 0 {
                reserved = self.v()?;
            }
            for _ in 0..reserved {
                self.v()?;
            }
            if flags & FLAG_SM_DATA != 0 {
                return Err(bad("side data in a frame (NUT version 4) is not read here"));
            }
            if header_idx as usize >= self.headers.len() {
                return Err(bad("header index"));
            }
            if size > 4096 {
                header_idx = 0;
            }
            if flags & FLAG_CHECKSUM != 0 {
                let mut ck = [0u8; 4];
                self.r.read_exact(&mut ck)?;
            }
            let head = self.headers[header_idx as usize].clone();
            if (size as usize) < head.len() || size > 256 << 20 {
                return Err(bad("frame size"));
            }
            let mut data = head;
            let start = data.len();
            data.resize(size as usize, 0);
            self.r.read_exact(&mut data[start..])?;
            return Ok(Some(NutPacket { stream, data }));
        }
    }
}

/// VPS, SPS and PPS from an encoder's global header: Annex-B, or an hvcC record.
pub fn parameter_sets_from_extradata(extra: &[u8]) -> Option<Vec<Vec<u8>>> {
    let nals: Vec<Vec<u8>> = if extra.first() == Some(&1) && extra.len() > 23 {
        // hvcC: 22 bytes, numOfArrays, then arrays of (type, count, (len, nal)…).
        let mut out = Vec::new();
        let mut i = 23;
        for _ in 0..extra[22] {
            if i + 3 > extra.len() {
                break;
            }
            let count = u16::from_be_bytes([extra[i + 1], extra[i + 2]]) as usize;
            i += 3;
            for _ in 0..count {
                if i + 2 > extra.len() {
                    break;
                }
                let len = u16::from_be_bytes([extra[i], extra[i + 1]]) as usize;
                i += 2;
                if i + len > extra.len() {
                    break;
                }
                out.push(extra[i..i + len].to_vec());
                i += len;
            }
        }
        out
    } else {
        split_annex_b(extra).into_iter().map(|n| n.to_vec()).collect()
    };
    pick_parameter_sets(&nals)
}

fn pick_parameter_sets<T: AsRef<[u8]>>(nals: &[T]) -> Option<Vec<Vec<u8>>> {
    let find = |t: u8| nals.iter().find(|n| hevc_nal_type(n.as_ref()) == t).map(|n| n.as_ref().to_vec());
    Some(vec![find(nal_type::VPS)?, find(nal_type::SPS)?, find(nal_type::PPS)?])
}

/// An access unit as the trait carries it: NAL units without start codes, the parameter sets
/// split out (and kept in `ps` for the next keyframe), delimiters and fillers dropped.
pub fn access_unit(data: &[u8], ps: &mut Option<Vec<Vec<u8>>>, width: u32, height: u32, first: bool) -> EncodedFrame {
    let nals: Vec<&[u8]> = if data.starts_with(&[0, 0, 1]) || data.starts_with(&[0, 0, 0, 1]) {
        split_annex_b(data)
    } else {
        sill_protocol::blobs::split_frame_payload(data).unwrap_or_default()
    };
    let mut kept = Vec::new();
    let mut inband = Vec::new();
    let mut keyframe = false;
    for n in nals {
        let t = hevc_nal_type(n);
        match t {
            nal_type::VPS | nal_type::SPS | nal_type::PPS => inband.push(n),
            nal_type::AUD | nal_type::EOS | nal_type::EOB | nal_type::FD => {}
            _ => {
                if nal_type::is_irap(t) {
                    keyframe = true;
                }
                kept.push(n.to_vec());
            }
        }
    }
    if let Some(sets) = pick_parameter_sets(&inband) {
        *ps = Some(sets);
    }
    EncodedFrame {
        nals: kept,
        keyframe,
        parameter_sets: if keyframe || first { ps.clone() } else { None },
        width,
        height,
    }
}

// MARK: The encoder

struct Mail {
    /// Whether any frame came out yet.
    produced: bool,
    next: Option<Vec<u8>>,
    last: Option<Arc<Vec<u8>>>,
    key_requested: Option<Instant>,
    in_flight: usize,
    last_output: Instant,
    stop: bool,
}

struct Shared {
    mail: Mutex<Mail>,
    cv: Condvar,
    sink: Arc<dyn StreamSink>,
    dead: AtomicBool,
    last_error: Mutex<String>,
}

impl Shared {
    fn die(&self, reason: String) {
        let stopping = self.mail.lock().unwrap().stop;
        if !self.dead.swap(true, Ordering::AcqRel) && !stopping {
            self.sink.ended(reason);
        }
        self.cv.notify_all();
    }
}

/// A running FFmpeg encoder feeding a `StreamSink`. Dropping it (or `stop`) ends the process.
pub struct FfmpegEncoder {
    shared: Arc<Shared>,
    child: Mutex<Option<Child>>,
    threads: Vec<JoinHandle<()>>,
    frame_len: usize,
    cfg: FfmpegConfig,
}

impl FfmpegEncoder {
    /// Starts FFmpeg; frames then go to `sink.frame`, and `sink.ended` is called once if FFmpeg
    /// stops by itself.
    pub fn start(cfg: FfmpegConfig, sink: Arc<dyn StreamSink>) -> Result<FfmpegEncoder, String> {
        if cfg.width < 16 || cfg.height < 16 {
            return Err(format!("{}×{} is too small to encode", cfg.width, cfg.height));
        }
        let args = arguments(&cfg);
        let mut child = Command::new(&cfg.ffmpeg)
            .args(&args)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .map_err(|e| format!("could not run {}: {e}", cfg.ffmpeg.display()))?;
        let stdin = child.stdin.take().ok_or("no stdin")?;
        let stdout = child.stdout.take().ok_or("no stdout")?;
        let stderr = child.stderr.take().ok_or("no stderr")?;
        let shared = Arc::new(Shared {
            mail: Mutex::new(Mail { produced: false, next: None, last: None, key_requested: None, in_flight: 0, last_output: Instant::now(), stop: false }),
            cv: Condvar::new(),
            sink,
            dead: AtomicBool::new(false),
            last_error: Mutex::new(String::new()),
        });
        let mut threads = Vec::new();
        let s = shared.clone();
        let c = cfg.clone();
        threads.push(std::thread::Builder::new().name("sill-ffmpeg-in".into()).spawn(move || writer(s, c, stdin)).map_err(|e| e.to_string())?);
        let s = shared.clone();
        let c = cfg.clone();
        threads.push(std::thread::Builder::new().name("sill-ffmpeg-out".into()).spawn(move || reader(s, c, stdout)).map_err(|e| e.to_string())?);
        let s = shared.clone();
        threads.push(
            std::thread::Builder::new()
                .name("sill-ffmpeg-err".into())
                .spawn(move || {
                    for line in BufReader::new(stderr).lines().map_while(Result::ok) {
                        let line = line.trim().to_string();
                        if line.is_empty() {
                            continue;
                        }
                        log(&format!("ffmpeg: {line}"));
                        *s.last_error.lock().unwrap() = line;
                    }
                })
                .map_err(|e| e.to_string())?,
        );
        Ok(FfmpegEncoder { shared, child: Mutex::new(Some(child)), threads, frame_len: cfg.input.frame_len(cfg.width, cfg.height), cfg })
    }

    pub fn config(&self) -> &FfmpegConfig {
        &self.cfg
    }

    /// The bytes `submit` takes per frame.
    pub fn frame_len(&self) -> usize {
        self.frame_len
    }

    /// One frame, tightly packed. Never blocks: a frame still waiting to go in is replaced.
    pub fn submit(&self, frame: Vec<u8>) {
        if frame.len() != self.frame_len || self.shared.dead.load(Ordering::Acquire) {
            return;
        }
        let mut m = self.shared.mail.lock().unwrap();
        if m.next.replace(frame).is_some() {
            bump("enc.mailboxDrop");
        }
        bump("enc.in");
        drop(m);
        self.shared.cv.notify_all();
    }

    /// The next frame is a keyframe; with no new frame within 50 ms, the last one is encoded again
    /// as a keyframe.
    pub fn request_keyframe(&self) {
        let mut m = self.shared.mail.lock().unwrap();
        if m.key_requested.is_none() {
            m.key_requested = Some(Instant::now());
        }
        drop(m);
        self.shared.cv.notify_all();
    }

    pub fn is_dead(&self) -> bool {
        self.shared.dead.load(Ordering::Acquire)
    }

    /// Ends FFmpeg and its threads.
    pub fn stop(mut self) {
        self.shutdown();
    }

    fn shutdown(&mut self) {
        self.shared.mail.lock().unwrap().stop = true;
        self.shared.cv.notify_all();
        if let Some(mut c) = self.child.lock().unwrap().take() {
            let _ = c.kill();
            let _ = c.wait();
        }
        for t in self.threads.drain(..) {
            let _ = t.join();
        }
    }
}

impl Drop for FfmpegEncoder {
    fn drop(&mut self) {
        self.shutdown();
    }
}

fn got_output(m: &Mail) -> bool {
    m.produced
}

fn writer(s: Arc<Shared>, cfg: FfmpegConfig, mut stdin: ChildStdin) {
    if let Err(e) = stdin.write_all(&mkv_header(cfg.input, cfg.width, cfg.height, cfg.fps)) {
        s.die(format!("the encoder did not start ({e})"));
        return;
    }
    let start = Instant::now();
    let mut last_pts: Option<u64> = None;
    let mut warned_stuck = false;
    loop {
        let (frame, key) = {
            let mut m = s.mail.lock().unwrap();
            loop {
                if m.stop || s.dead.load(Ordering::Acquire) {
                    return;
                }
                // FFmpeg dropped a frame without a word (it should not): do not wait for it. Its
                // first frame takes as long as FFmpeg's start (x265's set-up included).
                let patience = if got_output(&m) { Duration::from_secs(1) } else { Duration::from_secs(5) };
                if m.in_flight > 0 && m.last_output.elapsed() > patience {
                    if !warned_stuck {
                        warned_stuck = true;
                        log("Encoder: a frame has not come back for a second; sending the next one anyway.");
                    }
                    m.in_flight = 0;
                }
                if m.in_flight < cfg.max_in_flight {
                    if let Some(f) = m.next.take() {
                        let key = m.key_requested.take().is_some();
                        let f = Arc::new(f);
                        m.last = Some(f.clone());
                        m.in_flight += 1;
                        break (f, key);
                    }
                    if let (Some(at), Some(last)) = (m.key_requested, m.last.clone()) {
                        if at.elapsed() >= Duration::from_millis(50) && m.in_flight == 0 {
                            m.key_requested = None;
                            m.in_flight += 1;
                            break (last, true);
                        }
                    }
                }
                m = s.cv.wait_timeout(m, Duration::from_millis(20)).unwrap().0;
            }
        };
        // Even microseconds for every frame, odd for a keyframe (see the module's comment). The
        // first frame is always at 0 and never marked: FFmpeg shifts every timestamp by the
        // stream's start, so an odd first one would make every later one odd, and every frame an
        // IDR (the Linux agent saw 232 of 232). It is an IDR anyway, so a request made before it
        // is answered by it.
        let mut pts = match last_pts {
            None => 0,
            Some(lp) => {
                let mut p = (start.elapsed().as_micros() as u64) & !1;
                if p <= lp {
                    p = (lp + 2) & !1;
                }
                if key {
                    p |= 1;
                }
                p
            }
        };
        if last_pts.is_some() && pts <= last_pts.unwrap() {
            pts += 2;
        }
        last_pts = Some(pts);
        let head = mkv_cluster_head(pts, frame.len());
        if let Err(e) = stdin.write_all(&head).and_then(|_| stdin.write_all(&frame)).and_then(|_| stdin.flush()) {
            let why = s.last_error.lock().unwrap().clone();
            s.die(if why.is_empty() { format!("the encoder stopped ({e})") } else { format!("the encoder stopped: {why}") });
            return;
        }
    }
}

fn reader(s: Arc<Shared>, cfg: FfmpegConfig, stdout: std::process::ChildStdout) {
    let mut nut = NutReader::new(BufReader::with_capacity(1 << 20, stdout));
    let mut ps: Option<Vec<Vec<u8>>> = None;
    let mut first = true;
    loop {
        match nut.next_packet() {
            Ok(Some(p)) => {
                if p.stream != 0 {
                    continue;
                }
                if ps.is_none() {
                    ps = nut.extradata.first().and_then(|e| parameter_sets_from_extradata(e));
                }
                let frame = access_unit(&p.data, &mut ps, cfg.width, cfg.height, first);
                first = false;
                {
                    let mut m = s.mail.lock().unwrap();
                    m.in_flight = m.in_flight.saturating_sub(1);
                    m.last_output = Instant::now();
                    m.produced = true;
                }
                s.cv.notify_all();
                if frame.nals.is_empty() {
                    continue;
                }
                bump("enc.frames");
                s.sink.frame(frame);
            }
            Ok(None) => {
                let why = s.last_error.lock().unwrap().clone();
                s.die(if why.is_empty() { "the encoder exited".into() } else { format!("the encoder exited: {why}") });
                return;
            }
            Err(e) => {
                s.die(format!("the encoder's output could not be read ({e})"));
                return;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn encoder_names() {
        assert_eq!(HevcEncoder::parse("libx265"), Some(HevcEncoder::Libx265));
        assert_eq!(HevcEncoder::parse("hevc_vaapi"), Some(HevcEncoder::Vaapi { device: "/dev/dri/renderD128".into() }));
        assert_eq!(HevcEncoder::parse("hevc_vaapi:/dev/dri/renderD129"), Some(HevcEncoder::Vaapi { device: "/dev/dri/renderD129".into() }));
        assert_eq!(HevcEncoder::parse("h264"), None);
    }

    #[test]
    fn mkv_sizes() {
        let h = mkv_cluster_head(1_000_001, 100);
        // Cluster id, 8-byte size, timecode element (id, 8-byte size, 3 bytes), block head.
        assert_eq!(&h[..4], &[0x1F, 0x43, 0xB6, 0x75]);
        let body = u64::from_be_bytes([0, h[5], h[6], h[7], h[8], h[9], h[10], h[11]]);
        assert_eq!(body as usize, (h.len() - 12) + 100);
        assert_eq!(PixelFormat::Nv12.frame_len(4, 2), 12);
    }

    #[test]
    fn hvcc_extradata() {
        let mut hvcc = vec![1u8; 22];
        hvcc.push(3);
        for (t, nal) in [(32u8, vec![0x40, 1]), (33, vec![0x42, 1]), (34, vec![0x44, 1])] {
            hvcc.extend_from_slice(&[t, 0, 1, 0, nal.len() as u8]);
            hvcc.extend_from_slice(&nal);
        }
        let ps = parameter_sets_from_extradata(&hvcc).unwrap();
        assert_eq!(ps, vec![vec![0x40, 1], vec![0x42, 1], vec![0x44, 1]]);
        let annex = [0, 0, 0, 1, 0x40, 1, 0, 0, 0, 1, 0x42, 1, 0, 0, 0, 1, 0x44, 1];
        assert_eq!(parameter_sets_from_extradata(&annex).unwrap(), ps);
    }

    #[test]
    fn access_units() {
        let mut ps = None;
        let key = [0, 0, 0, 1, 0x40, 1, 0, 0, 0, 1, 0x42, 1, 0, 0, 0, 1, 0x44, 1, 0, 0, 0, 1, 0x28, 1, 7, 7];
        let f = access_unit(&key, &mut ps, 64, 32, true);
        assert!(f.keyframe);
        assert_eq!(f.nals, vec![vec![0x28, 1, 7, 7]]);
        assert_eq!(f.parameter_sets.as_ref().unwrap().len(), 3);
        let delta = [0, 0, 0, 1, 0x46, 1, 0, 0, 1, 0x02, 1, 5];
        let f = access_unit(&delta, &mut ps, 64, 32, false);
        assert!(!f.keyframe);
        assert_eq!(f.nals, vec![vec![0x02, 1, 5]]);
        assert!(f.parameter_sets.is_none());
    }
}
