//! sill-host-linux: the Sill host on a Linux X11 session (see ../NOTES-linux.md).
//!
//!   sill-host-linux --selftest [DIR] [--seconds N]   every part of the backend once (Docker test)
//!   sill-host-linux --list                           the windows and apps a device would see
//!   sill-host-linux --launch APP_ID                  launches a desktop entry
//!   sill-host-linux --window raise|close|minimize|fullscreen|resize W H|thumbnail ID   one call
//!   sill-host-linux [core options]                   the host (the core's options: NOTES-core.md)

#[cfg(not(target_os = "linux"))]
fn main() {
    eprintln!("sill-host-linux runs on Linux (an X11 session); this build is for checking the crate only.");
    std::process::exit(1);
}

#[cfg(target_os = "linux")]
fn main() {
    use sill_host_core::platform::Platform;
    use sill_host_linux::linux::{encoder, selftest, LinuxPlatform};

    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.first().map(String::as_str) == Some("--selftest") {
        let dir = args.get(1).filter(|a| !a.starts_with("--")).cloned().unwrap_or_else(|| "selftest".into());
        let seconds = args
            .iter()
            .position(|a| a == "--seconds")
            .and_then(|i| args.get(i + 1))
            .and_then(|s| s.parse().ok())
            .unwrap_or(4);
        std::process::exit(selftest::run(std::path::Path::new(&dir), seconds));
    }
    if args.first().map(String::as_str) == Some("--list") {
        let p = LinuxPlatform::new(encoder::unavailable()).unwrap_or_else(|e| {
            eprintln!("{e}");
            std::process::exit(1)
        });
        println!("{}", p.machine_name());
        for w in p.windows() {
            println!("window {:#x} {:?} {:?} ({}) {}x{}", w.id, w.title, w.app_name, w.app_id, w.width, w.height);
        }
        for a in p.apps() {
            println!("app {} ({})", a.name, a.app_id);
        }
        return;
    }
    if let (Some("--launch"), Some(id)) = (args.first().map(String::as_str), args.get(1)) {
        let p = LinuxPlatform::new(encoder::unavailable()).unwrap_or_else(|e| {
            eprintln!("{e}");
            std::process::exit(1)
        });
        match p.launch(id) {
            Ok(()) => println!("launched {id}"),
            Err(e) => {
                eprintln!("{e}");
                std::process::exit(1)
            }
        }
        std::thread::sleep(std::time::Duration::from_millis(300));
        return;
    }
    // Debugging aids: one platform call against a window (an id in hex or decimal).
    if let (Some("--window"), Some(cmd), Some(id)) = (args.first().map(String::as_str), args.get(1), args.get(2)) {
        use sill_host_core::platform::WindowCommand;
        let id = u32::from_str_radix(id.trim_start_matches("0x"), if id.starts_with("0x") { 16 } else { 10 }).unwrap_or(0);
        let p = LinuxPlatform::new(encoder::unavailable()).unwrap_or_else(|e| {
            eprintln!("{e}");
            std::process::exit(1)
        });
        match cmd.as_str() {
            "raise" => p.raise(id),
            "close" => p.window_command(id, WindowCommand::Close),
            "minimize" => p.window_command(id, WindowCommand::Minimize),
            "fullscreen" => p.window_command(id, WindowCommand::FullScreen),
            "resize" => {
                let w = args.get(3).and_then(|v| v.parse().ok()).unwrap_or(800);
                let h = args.get(4).and_then(|v| v.parse().ok()).unwrap_or(600);
                println!("{:?}", p.resize(id, w, h));
            }
            "thumbnail" => println!("{:?} bytes", p.thumbnail(id).map(|t| t.len())),
            other => eprintln!("unknown window command {other}"),
        }
        if let Some(ms) = std::env::var("SILL_LINGER_MS").ok().and_then(|v| v.parse().ok()) {
            std::thread::sleep(std::time::Duration::from_millis(ms));
        }
        return;
    }
    // The host: the core's options, plus --encoder=libx265|hevc_vaapi|hevc_nvenc (else probed).
    let (options, rest) = sill_host_core::HostOptions::from_args(args).unwrap_or_else(|e| {
        eprintln!("{e}\n\nsill-host-linux [--encoder=libx265|hevc_vaapi|hevc_nvenc] [options]\n{}", sill_host_core::HostOptions::USAGE);
        std::process::exit(2)
    });
    for a in &rest {
        match a.split_once('=') {
            Some(("--encoder", name)) => std::env::set_var("SILL_ENCODER", name),
            _ => {
                eprintln!("unknown option {a}\n\nsill-host-linux [--encoder=libx265|hevc_vaapi|hevc_nvenc] [options]\n{}", sill_host_core::HostOptions::USAGE);
                std::process::exit(2);
            }
        }
    }
    let make = match encoder::probe() {
        Some(kind) => {
            println!("Encoder: {} through ffmpeg.", kind.name());
            encoder::core(kind)
        }
        None => {
            eprintln!("No HEVC encoder found (ffmpeg with libx265, hevc_vaapi or hevc_nvenc): devices will see no picture.");
            encoder::unavailable()
        }
    };
    let platform = std::sync::Arc::new(LinuxPlatform::new(make).unwrap_or_else(|e| {
        eprintln!("{e}");
        std::process::exit(1)
    }));
    let result = sill_host_core::run(platform.clone(), options);
    platform.release_input();
    if let Err(e) = result {
        eprintln!("{e}");
        std::process::exit(1);
    }
}
