//! Starting a host: the options every backend's binary shares, the home door's listener, and the
//! coordinator's loop until Ctrl-C.

use crate::catalog::Catalog;
use crate::config::HostConfig;
use crate::coordinator::{Coordinator, CoordinatorOptions};
use crate::door::{Door, DoorKind};
use crate::origin;
use crate::pairing::{Pairing, RemoteDoor, Store};
use crate::platform::Platform;
use crate::server::{Route, Server};
use crate::transport::PlainTransport;
use crate::{log, stats, Event};
use sill_protocol::identity::{mac_id, random_bytes, short_name};
use std::collections::HashMap;
use std::net::{IpAddr, Ipv4Addr, Ipv6Addr, SocketAddr, TcpListener};
use std::path::PathBuf;
use std::sync::mpsc::channel;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

/// The flags every Rust host takes (each backend's binary may add its own: they come back in the
/// rest list of `from_args`).
#[derive(Clone, Debug)]
pub struct HostOptions {
    /// The home door's port; 0 picks a free one (as the Mac's listener does: devices find it by
    /// Bonjour). `--port=N`.
    pub port: u16,
    /// Listen on 127.0.0.1 alone (tests; no firewall prompt). `--loopback`, or SILL_TEST_LOOPBACK=1.
    pub loopback: bool,
    /// The home door speaks TLS with pairing, as Sill.app's does. `--pairing`.
    pub pairing: bool,
    /// The remote door for this run (TLS 1.3, paired devices only), on this port (0: any free
    /// one). `--remote[=PORT]`. Devices away from home reach it through a VPN (Tailscale) or this
    /// network; `--internet` also from the internet (a router port forward).
    pub remote: Option<u16>,
    pub internet: bool,
    /// Where the identity and the trust list live (`--config-dir=PATH`); default: the platform's
    /// config directory + "sill" (created 0700).
    pub config_dir: Option<PathBuf>,
    /// The name devices list; default `Platform::machine_name()`. `--name=NAME`.
    pub name: Option<String>,
    /// Advertise `_sill._tcp` through the platform (`--no-advertise` turns it off; a loopback host
    /// never advertises).
    pub advertise: bool,
    /// The streaming knobs at launch (`--bitrate=MBPS`, `--max-fps=N`, `--standard` for half scale).
    pub config: HostConfig,
}

impl Default for HostOptions {
    fn default() -> Self {
        HostOptions {
            port: 0,
            loopback: false,
            pairing: false,
            remote: None,
            internet: false,
            config_dir: None,
            name: None,
            advertise: true,
            config: HostConfig::standard(),
        }
    }
}

impl HostOptions {
    pub const USAGE: &'static str = "  --port=N          the home door's port (default: any free port)\n\
  --loopback        listen on 127.0.0.1 only (tests)\n\
  --pairing         the home door speaks TLS 1.3 with pairing (as Sill.app)\n\
  --remote[=PORT]   the remote door for devices away from home (TLS, paired devices only)\n\
  --internet        with --remote: also admit paired devices from the internet\n\
  --config-dir=PATH where the identity and the paired devices are kept\n\
  --name=NAME       the name devices show\n\
  --no-advertise    do not register _sill._tcp\n\
  --bitrate=MBPS    bits per 60 fps (default 15)\n\
  --max-fps=N       the frame rate ceiling (default 120)\n\
  --standard        stream at half the source's size (default: full)";

    /// Parses the shared flags; anything else comes back in order for the backend.
    pub fn from_args<I: IntoIterator<Item = String>>(args: I) -> Result<(HostOptions, Vec<String>), String> {
        let mut o = HostOptions::default();
        let mut rest = Vec::new();
        for a in args {
            let (k, v) = match a.split_once('=') {
                Some((k, v)) => (k.to_string(), Some(v.to_string())),
                None => (a.clone(), None),
            };
            let need = |v: &Option<String>| v.clone().ok_or_else(|| format!("{k} needs a value"));
            match k.as_str() {
                "--port" => o.port = need(&v)?.parse().map_err(|_| "--port: a number from 0 to 65535".to_string())?,
                "--loopback" => o.loopback = true,
                "--pairing" => o.pairing = true,
                "--remote" => {
                    o.remote = Some(match &v {
                        None => 0,
                        Some(p) => p.parse().ok().filter(|p: &u16| *p >= 1024).ok_or("--remote=PORT takes a port from 1024 to 65535")?,
                    })
                }
                "--internet" => o.internet = true,
                "--config-dir" => o.config_dir = Some(PathBuf::from(need(&v)?)),
                "--name" => o.name = Some(need(&v)?),
                "--no-advertise" => o.advertise = false,
                "--bitrate" => {
                    let mbps: f64 = need(&v)?.parse().map_err(|_| "--bitrate: megabits per second".to_string())?;
                    o.config.bitrate = (mbps * 1_000_000.0) as i64;
                }
                "--max-fps" => o.config.max_fps = need(&v)?.parse().map_err(|_| "--max-fps: a number".to_string())?,
                "--standard" => o.config.capture_scale = 1.0,
                _ => rest.push(a),
            }
        }
        if o.internet && o.remote.is_none() {
            return Err("--internet needs --remote.".into());
        }
        if std::env::var("SILL_TEST_LOOPBACK").as_deref() == Ok("1") {
            o.loopback = true;
        }
        if o.loopback {
            o.advertise = false;
        }
        o.config = o.config.validated();
        Ok((o, rest))
    }
}

/// A random UUID in Foundation's upper-case form: the launch ID every window list carries.
fn launch_id() -> String {
    let mut b = random_bytes(16);
    b[6] = (b[6] & 0x0F) | 0x40;
    b[8] = (b[8] & 0x3F) | 0x80;
    let h: String = b.iter().map(|x| format!("{x:02X}")).collect();
    format!("{}-{}-{}-{}-{}", &h[0..8], &h[8..12], &h[12..16], &h[16..20], &h[20..32])
}

/// Binds the home door: every interface (dual stack where the system allows), or 127.0.0.1.
fn bind(opts: &HostOptions, port: u16) -> std::io::Result<TcpListener> {
    if opts.loopback {
        return TcpListener::bind(SocketAddr::new(IpAddr::V4(Ipv4Addr::LOCALHOST), port));
    }
    let any6 = SocketAddr::new(IpAddr::V6(Ipv6Addr::UNSPECIFIED), port);
    let s = socket2::Socket::new(socket2::Domain::IPV6, socket2::Type::STREAM, Some(socket2::Protocol::TCP));
    if let Ok(s) = s {
        let _ = s.set_only_v6(false);
        let _ = s.set_reuse_address(true);
        if s.bind(&any6.into()).is_ok() && s.listen(64).is_ok() {
            return Ok(s.into());
        }
    }
    TcpListener::bind(SocketAddr::new(IpAddr::V4(Ipv4Addr::UNSPECIFIED), port))
}

/// Accepts on `listener` for `door`, for good.
fn start_tls_door(listener: TcpListener, door: Arc<Door>) -> Result<(), String> {
    std::thread::Builder::new()
        .name("sill-accept".into())
        .spawn(move || {
            for stream in listener.incoming().flatten() {
                door.accept(stream);
            }
        })
        .map(|_| ())
        .map_err(|e| e.to_string())
}

/// Whether an accepted connection is closed or reset by its peer before it sent a byte (waiting
/// up to 0.1 s for its first one).
fn reset_already(s: &std::net::TcpStream) -> bool {
    if s.set_read_timeout(Some(Duration::from_millis(100))).is_err() {
        return false;
    }
    let mut b = [0u8; 1];
    let gone = match s.peek(&mut b) {
        Ok(0) => true,
        Ok(_) => false,
        Err(e) => !matches!(e.kind(), std::io::ErrorKind::WouldBlock | std::io::ErrorKind::TimedOut),
    };
    let _ = s.set_read_timeout(None);
    gone
}

/// Runs the host until Ctrl-C (or SIGTERM): listens, serves devices, then says goodbye to each.
pub fn run(platform: Arc<dyn Platform>, opts: HostOptions) -> Result<(), String> {
    let name = opts.name.clone().unwrap_or_else(|| platform.machine_name());
    let (tx, rx) = channel::<Event>();
    let server = Server::new(tx.clone());
    let reader = platform.clone();
    server.set_pointer_reader(Box::new(move || reader.pointer_location()));
    let catalog = Catalog::new(platform.clone(), server.clone(), tx.clone());
    // --pairing: the identity, the trust list and the pairing window (the TLS home door).
    let pairing = if opts.pairing || opts.remote.is_some() {
        let store = Store::open(opts.config_dir.clone())?;
        let p = Pairing::new(store, &name)?;
        log(&format!(
            "Identity: ID {} (key {}…), kept in {}",
            mac_id(&p.identity.fingerprint),
            short_name(&p.identity.fingerprint),
            p.store_dir().display()
        ));
        Some(p)
    } else {
        None
    };
    let listener = bind(&opts, opts.port).map_err(|e| format!("Listener failed: {e}"))?;
    let port = listener.local_addr().map_err(|e| e.to_string())?.port();
    stats::start_printing();
    catalog.start();
    if opts.loopback {
        log("Test listener: loopback only; reach this host at 127.0.0.1.");
    }
    if let (true, Some(p)) = (opts.pairing, &pairing) {
        log(&format!("Home door: TLS on port {port}, pairing required ({} paired).", p.paired_count()));
        start_tls_door(listener, Door::new(DoorKind::Home, p.clone(), server.clone()))?;
    } else {
        log(&format!(
            "Home door: plain TCP on port {port} (development builds of the apps; Release builds need --pairing)."
        ));
        start_plain_door(listener, server.clone())?;
    }
    if let (Some(remote_port), Some(p)) = (opts.remote, &pairing) {
        let l = bind(&opts, remote_port).map_err(|e| format!("Remote access couldn’t start ({e})."))?;
        let bound = l.local_addr().map_err(|e| e.to_string())?.port();
        p.set_remote(Some(RemoteDoor { port: bound, internet: opts.internet, loopback: opts.loopback, home_tls: opts.pairing }));
        log(&format!("Remote access: listening on port {bound} (TLS, paired devices only; {} paired).", p.paired_count()));
        if opts.internet {
            log("Internet access on for this run: the remote door also admits paired devices from outside this machine's networks and VPNs.");
        }
        start_tls_door(l, Door::new(DoorKind::Remote { internet: opts.internet }, p.clone(), server.clone()))?;
    }
    if let Some(p) = &pairing {
        // A pairing window is always open: its code goes to stdout only.
        p.open_window(None, true);
        let ticker = p.clone();
        std::thread::Builder::new()
            .name("sill-pairing".into())
            .spawn(move || loop {
                std::thread::sleep(Duration::from_secs(1));
                ticker.tick();
            })
            .map_err(|e| e.to_string())?;
    }
    // Bonjour, through the platform: a TLS door's record carries `r` (a fresh recognition tag) and
    // `p` ("1": pairing required).
    let txt = pairing.as_ref().map(|p| p.txt(opts.pairing)).unwrap_or_default();
    let _advertisement = if opts.advertise {
        match platform.advertise(&name, port, &txt) {
            Ok(guard) => {
                log(&format!("Advertising _sill._tcp as \"{name}\" on port {port}."));
                Some(guard)
            }
            Err(e) => {
                log(&format!("Not advertised ({e}); devices reach this host by address."));
                None
            }
        }
    } else {
        None
    };
    log("Nothing is streaming yet: pick a window or the desktop on the device. Ctrl-C to stop.");
    // Ctrl-C / SIGTERM: goodbye "quit" to every device, then return.
    let (done_tx, done_rx) = channel::<()>();
    let stop_tx = Mutex::new(Some((tx.clone(), done_tx)));
    let _ = ctrlc::set_handler(move || {
        if let Some((tx, done)) = stop_tx.lock().unwrap().take() {
            let _ = tx.send(Event::Shutdown(done));
        } else {
            std::process::exit(130);
        }
    });
    let coordinator = Coordinator::new(
        platform.clone(),
        server.clone(),
        catalog,
        tx,
        CoordinatorOptions { mac_name: name, launch_id: launch_id(), pairing, config: opts.config.clone() },
    );
    coordinator.run(rx);
    let _ = done_rx.recv_timeout(Duration::from_secs(2));
    log("Stopped.");
    Ok(())
}

/// The plain door (no TLS): admits only this machine's own networks (OriginPolicy.homeAdmits).
fn start_plain_door(listener: TcpListener, srv: Arc<Server>) -> Result<(), String> {
    std::thread::Builder::new()
        .name("sill-accept".into())
        .spawn(move || {
            let refused: Mutex<HashMap<IpAddr, Instant>> = Mutex::new(HashMap::new());
            for conn in listener.incoming() {
                let Ok(stream) = conn else { continue };
                let Ok(peer) = stream.peer_addr() else { continue };
                let origin = origin::classify(peer.ip());
                if !origin.home_admits() {
                    let mut r = refused.lock().unwrap();
                    let due = r.get(&peer.ip()).map(|t| t.elapsed() > Duration::from_secs(60)).unwrap_or(true);
                    if due {
                        r.insert(peer.ip(), Instant::now());
                        log(&format!(
                            "Home door refused {} ({:?}): only this machine's own networks reach it.",
                            peer.ip(),
                            origin
                        ));
                    }
                    drop(stream);
                    continue;
                }
                let srv = srv.clone();
                std::thread::spawn(move || {
                    // A connection reset before it said anything (a port scan, a flood) is never a
                    // client: Network.framework never reports one ready, so Swift logs nothing for
                    // it. A device says hello at once; a silent one is let in after 0.1 s.
                    if reset_already(&stream) {
                        return;
                    }
                    match PlainTransport::new(stream) {
                        Ok(t) => {
                            if let Err(e) = srv.register(Box::new(t), Route::HomePlain, None) {
                                log(&format!("Could not serve {peer}: {e}"));
                            }
                        }
                        Err(e) => log(&format!("Could not serve {peer}: {e}")),
                    }
                });
            }
        })
        .map_err(|e| e.to_string())?;
    Ok(())
}
