//! Sill host for Windows (owned by the Windows agent; see ../README.md and ../NOTES-windows.md).
//!
//! The platform-independent parts (the HID → scancode table, the key state, Annex-B parsing, the
//! pointer's arithmetic, the picture sizes, the image helpers) compile everywhere and are
//! unit-tested on any machine; the backend itself (`win`) is Windows-only.
//!
//! Usage on Windows:
//!   sill-host-windows --selftest [--frames N] [--window ID] [--out DIR]
//!       lists windows and apps, writes an icon and a thumbnail, and streams N frames (default
//!       120) of the primary display (or a window) through the real capture and encoder into
//!       DIR\selftest.h265 (default: the current folder), printing each frame's size.
//!   sill-host-windows --list
//!       the window list, the installed apps and the HEVC encoders, then exits.
//!   sill-host-windows [--port=N] [--loopback] [--name=NAME] [--no-advertise] [--bitrate=MBPS] …
//!       the host itself: sill-host-core's server with this backend (HostOptions::USAGE).

#![cfg_attr(not(windows), allow(dead_code))]

mod annexb;
mod imaging;
mod keymap;
mod keys;
mod pointer;
mod sizing;

#[cfg(windows)]
mod selftest;
#[cfg(windows)]
mod win;

#[cfg(windows)]
fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let code = match args.first().map(String::as_str) {
        Some("--selftest") => selftest::run(&args[1..]),
        Some("--list") => selftest::list(),
        Some("--help") | Some("-h") => {
            println!("{USAGE}\nhost options:\n{}", sill_host_core::HostOptions::USAGE);
            0
        }
        _ => serve(&args),
    };
    std::process::exit(code);
}

#[cfg(windows)]
const USAGE: &str = "usage: sill-host-windows [host options] | --selftest [--frames N] [--window ID] [--out DIR] | --list";

/// The host: sill-host-core's server (the home door, sessions, the catalog, pacing) with this
/// backend (NOTES-core.md, "How a backend uses the core"). Blocks until Ctrl-C.
#[cfg(windows)]
fn serve(args: &[String]) -> i32 {
    let (options, rest) = match sill_host_core::HostOptions::from_args(args.iter().cloned()) {
        Ok(parsed) => parsed,
        Err(e) => {
            eprintln!("{e}\n{USAGE}\n{}", sill_host_core::HostOptions::USAGE);
            return 2;
        }
    };
    if let Some(unknown) = rest.first() {
        eprintln!("unknown argument {unknown}\n{USAGE}\n{}", sill_host_core::HostOptions::USAGE);
        return 2;
    }
    let platform = win::WindowsPlatform::new();
    let shared: std::sync::Arc<dyn sill_host_core::platform::Platform> = platform.clone();
    let result = sill_host_core::run(shared, options);
    // The core releases a departing device's keys; this covers anything left at the end.
    platform.release_input();
    match result {
        Ok(()) => 0,
        Err(e) => {
            eprintln!("{e}");
            1
        }
    }
}

#[cfg(not(windows))]
fn main() {
    eprintln!("sill-host-windows runs on Windows only (build it with --target x86_64-pc-windows-msvc or -gnu).");
    std::process::exit(2);
}
