//! A Sill host with a synthetic backend: a moving test pattern for the Desktop and two fake
//! windows, HEVC through FFmpeg (libx265 by default), input only logged. Runs anywhere FFmpeg runs.
//!
//!     sill-host-synthetic --synthetic --loopback [--port=N] [--encoder=libx265|hevc_videotoolbox|…]
//!
//! `--synthetic` is accepted and ignored: Scripts/sillclient.py sends input only to a process
//! listening on its port whose arguments carry it.

use sill_host_core::ffmpeg::HevcEncoder;
use sill_host_core::synthetic::SyntheticPlatform;
use sill_host_core::HostOptions;
use std::sync::Arc;

fn main() {
    let (options, rest) = HostOptions::from_args(std::env::args().skip(1)).unwrap_or_else(|e| {
        eprintln!("sill-host-synthetic: {e}");
        std::process::exit(2)
    });
    let mut encoder = HevcEncoder::Libx265;
    for a in rest {
        if a == "--synthetic" {
            continue;
        } else if let Some(name) = a.strip_prefix("--encoder=") {
            encoder = HevcEncoder::parse(name).unwrap_or_else(|| {
                eprintln!("sill-host-synthetic: unknown encoder {name:?} (libx265, hevc_vaapi[:DEVICE], hevc_nvenc, hevc_videotoolbox)");
                std::process::exit(2)
            });
        } else if a == "--help" || a == "-h" {
            println!("usage: sill-host-synthetic [--synthetic] [--encoder=NAME]\n{}", HostOptions::USAGE);
            return;
        } else {
            eprintln!("sill-host-synthetic: unknown argument {a:?}");
            std::process::exit(2);
        }
    }
    sill_host_core::log("Synthetic mode: pick Desktop on the device (or from a test client) to stream a test pattern.");
    if let Err(e) = sill_host_core::run(Arc::new(SyntheticPlatform::new(encoder)), options) {
        eprintln!("{e}");
        std::process::exit(1);
    }
}
