//! The host without an OS (owned by the core agent; see ../README.md and ../NOTES-core.md).
//!
//! A backend implements [`platform::Platform`] and calls [`run`]; the core does the rest: the home
//! door, sessions, the catalog, source switching, input placement, frame pacing and dropping,
//! keyframes, host settings, ticks, liveness and goodbyes, exactly as SillHost does it.

pub mod catalog;
pub mod config;
pub mod coordinator;
pub mod door;
pub mod ffmpeg;
pub mod host;
pub mod origin;
pub mod pairing;
pub mod platform;
pub mod server;
pub mod stats;
pub mod synthetic;
pub mod tls_transport;
pub mod transport;

pub use host::{run, HostOptions};

use server::ClientId;
use sill_protocol::wire::Kind;

/// What the network, the catalog and the backend's threads tell the coordinator.
pub enum Event {
    Connected(ClientId),
    Left(ClientId),
    Message(ClientId, Kind, Vec<u8>),
    WindowsChanged(Vec<platform::Window>),
    KeyframeNeeded,
    /// A stream (by generation) ended by itself.
    StreamEnded(u64, String),
    /// A stream's (by generation) first frame, or a new size.
    FrameSize(u64, u32, u32),
    /// Goodbye to every device, then stop; the sender hears when that is done.
    Shutdown(std::sync::mpsc::Sender<()>),
}

/// One log line on stdout, as the Swift host prints them (flushed at once, so a test reading the
/// host's output through a pipe sees each line as it happens).
pub fn log(line: &str) {
    use std::io::Write;
    let mut out = std::io::stdout().lock();
    let _ = writeln!(out, "{line}");
    let _ = out.flush();
}
