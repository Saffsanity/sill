//! The one contract between the shared host (sessions, doors, pairing, pacing: this crate) and each
//! platform's backend (sill-host-windows, sill-host-linux). The core never touches an OS API; a
//! backend never touches the wire. Everything here is in the platform's own terms (pixels, its own
//! window IDs); the core turns it into the protocol's (StreamProtocol's WindowList, kinds 0–28).
//!
//! The macOS host is the reference for behaviour: Sources/SillHost (WindowCatalog, WindowCapture,
//! HEVCEncoder, InputInjector, WindowSizer, CursorShapeWatcher). Changing this file is the core
//! agent's job alone: a backend that needs more writes it down in its NOTES file instead.

use std::sync::Arc;

/// A rectangle in the platform's global desktop coordinates, in its logical units (Windows: physical
/// pixels of the virtual screen; X11: pixels of the root window).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Rect {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
}

/// One top-level window a device may pick (the protocol's WindowInfo).
#[derive(Clone, Debug, PartialEq)]
pub struct Window {
    /// Stable for the window's life and never 0 (Windows: the HWND's value truncated to 32 bits is
    /// fine while unique; X11: the window XID).
    pub id: u32,
    pub title: String,
    /// The app's display name ("Notepad", "Firefox").
    pub app_name: String,
    /// What groups an app's windows and keys its icon (the protocol calls it bundleID): Windows the
    /// executable's path or AppUserModelID; Linux the WM_CLASS or .desktop file ID.
    pub app_id: String,
    /// The window's size in the same units as `Rect`.
    pub width: u32,
    pub height: u32,
}

/// An installed app a device may launch (the protocol's AppInfo).
#[derive(Clone, Debug, PartialEq)]
pub struct App {
    pub name: String,
    pub app_id: String,
}

/// What to stream.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Source {
    /// The primary display, whole.
    Desktop,
    Window(u32),
}

/// How a stream should look. The core sets it from the host settings and the devices' viewports.
#[derive(Clone, Debug, PartialEq)]
pub struct StreamConfig {
    pub source: Source,
    /// Frames per second the encoder targets (60 or 120). Capture may deliver fewer when nothing
    /// changes; the encoder must not invent duplicates beyond what a keyframe request needs.
    pub fps: u32,
    /// Target bitrate, bits per second.
    pub bitrate: u32,
    /// 1.0 encodes at the source's pixel size; 0.5 at half each way (the "Standard" resolution of a
    /// HiDPI source). Width and height are rounded down to even numbers.
    pub scale: f64,
    /// Prefer speed over picture (the Mac's "Prioritize Encoding Speed").
    pub prioritize_speed: bool,
}

/// One encoded HEVC access unit. Real-time, low latency, no B-frames (every frame's decode order is
/// its display order), as VideoToolbox's real-time mode gives on the Mac.
#[derive(Clone, Debug)]
pub struct EncodedFrame {
    /// The access unit's NAL units, without start codes or length prefixes (VPS/SPS/PPS left out:
    /// they go in `parameter_sets`). The core frames them for the wire (4-byte lengths, hvcC style).
    pub nals: Vec<Vec<u8>>,
    pub keyframe: bool,
    /// VPS, SPS, PPS of the stream, in that order: set on the first frame and on every keyframe
    /// (the core sends them only when they change).
    pub parameter_sets: Option<Vec<Vec<u8>>>,
    /// The encoded picture's size in pixels.
    pub width: u32,
    pub height: u32,
}

/// The streamed source's cursor: an RGBA image, its hotspot and size in the source's units.
#[derive(Clone, Debug, PartialEq)]
pub struct CursorShape {
    pub png: Vec<u8>,
    pub hotspot_x: f64,
    pub hotspot_y: f64,
    pub width: f64,
    pub height: f64,
}

/// Where a running stream delivers. Called from the backend's own threads; never blocks for long
/// (the core drops frames rather than queue them: latency beats quality).
pub trait StreamSink: Send + Sync {
    fn frame(&self, frame: EncodedFrame);
    /// The cursor's shape changed (left out of the video: devices draw it themselves).
    fn cursor(&self, shape: CursorShape);
    /// The stream ended by itself (the window closed, the capture failed). Called once.
    fn ended(&self, reason: String);
}

/// A running stream: capture plus encoder, until dropped or `stop`ped.
pub trait Stream: Send {
    /// The next frame is a keyframe (a device joined, or lost a frame). When the source is still,
    /// the backend re-encodes its last picture so the keyframe goes out anyway.
    fn request_keyframe(&self);
    /// The source's rectangle now, for input (fractions of it) and the pointer.
    fn source_rect(&self) -> Option<Rect>;
    fn stop(self: Box<Self>);
}

/// A pointer button.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Button {
    Left,
    Right,
}

/// A scroll's phase as the protocol carries it (a trackpad gesture, then momentum). Platforms
/// without phased scrolling may ignore them and post plain wheel deltas.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ScrollPhase {
    Began,
    Ended,
    MomentumBegan,
    MomentumEnded,
}

/// What a device does, already placed on the desktop by the core (fractions of the source turned
/// into absolute positions). Keys are USB HID usages (page 7) with the protocol's modifier bits
/// (shift 1<<17, control 1<<18, option 1<<19, command 1<<20): each backend maps them to its own
/// keys, ⌘ and ⌃ to Ctrl, ⌥ to Alt (README.md).
#[derive(Clone, Debug, PartialEq)]
pub enum Input {
    Move { x: f64, y: f64 },
    ButtonDown { button: Button, x: f64, y: f64 },
    ButtonUp { button: Button, x: f64, y: f64 },
    /// Pixels the content should move (natural sign: positive dy moves content down).
    Scroll { x: f64, y: f64, dx: f64, dy: f64 },
    ScrollPhase { phase: ScrollPhase, x: f64, y: f64 },
    Key { hid_usage: u16, down: bool, modifiers: u64 },
    /// Text typed on a device's software keyboard ("\n", "\t" and "\u{8}" are Return, Tab, Backspace).
    Text(String),
}

/// A window command from a device's thumbnail menu.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum WindowCommand {
    Close,
    Minimize,
    FullScreen,
}

/// Everything the core needs from the operating system. One per process, shared across threads.
pub trait Platform: Send + Sync + 'static {
    /// The machine's name as devices list it ("Alex's PC", the hostname).
    fn machine_name(&self) -> String;

    /// Visible top-level windows a device may pick, front to back. Not the host's own windows.
    fn windows(&self) -> Vec<Window>;
    /// Installed apps, for the device's "All apps"; may be slow (the core calls it off its loop).
    fn apps(&self) -> Vec<App>;
    /// A small JPEG of a window, or None. The Mac fits it in 208×132 (twice the device's 104×66 pt
    /// tile) at quality 0.6; larger works and only costs bandwidth. The core asks every 2 s for the
    /// streamed window and for windows whose title or size changed, every 6 s for the rest, and
    /// sends one only when its bytes changed.
    fn thumbnail(&self, window: u32) -> Option<Vec<u8>>;
    /// The app's icon as a PNG (about 128 px), or None.
    fn icon(&self, app_id: &str) -> Option<Vec<u8>>;

    /// Starts capturing and encoding `config.source` into `sink`. Errors are shown to the person on
    /// the host's log and the device gets nothing streaming.
    fn start_stream(&self, config: StreamConfig, sink: Arc<dyn StreamSink>) -> Result<Box<dyn Stream>, String>;

    /// Posts one input event. Never blocks on the device's behalf for long.
    ///
    /// The core keeps track of what each device holds: when a device leaves, its keys come up
    /// (`Key { down: false, modifiers: 0 }`) and its buttons too (at the last pointer position).
    fn inject(&self, input: Input);
    /// Lets go of every key and button this host has pressed (modifiers included). The core calls
    /// it once as it stops (Ctrl-C, SIGTERM), after the devices' own releases; also a good place for
    /// a backend's own tracker to reset. Default: nothing. (Added 2026-10-14, additive.)
    fn release_all_input(&self) {}
    /// Brings a picked window forward and gives it the keyboard (regular mode on the Mac).
    fn raise(&self, window: u32);
    /// Resizes a window to `width`×`height` (the device's Aa / Text Size), keeping its top-left
    /// corner; returns the size it actually got (apps have minimum sizes), in the same units.
    /// The core passes logical points: the device's panel in points ÷ its Aa scale, as the Mac
    /// sizes a window in its points. A backend whose `Rect` units are physical pixels multiplies by
    /// its display's scale factor (Windows: DPI ÷ 96) before resizing, and divides on the way back.
    fn resize(&self, window: u32, width: u32, height: u32) -> Option<(u32, u32)>;
    fn window_command(&self, window: u32, command: WindowCommand);
    /// Launches an installed app; the core then picks its first window when it appears.
    fn launch(&self, app_id: &str) -> Result<(), String>;

    /// Where the pointer is now, in desktop coordinates (for kind 26, the host's pointer).
    fn pointer_location(&self) -> Option<(f64, f64)>;

    /// Advertises the host on the local network as `_sill._tcp` (`instance` is the machine name,
    /// `port` the home door's, `txt` the record's keys: `r`, `p`), until the returned guard drops.
    fn advertise(&self, instance: &str, port: u16, txt: &[(String, String)]) -> Result<Box<dyn Send>, String>;
}
