//! Pairing at the TLS home door (PairingWindow.swift, RemoteAccess.swift's judge and ask, the
//! identity store): this host's identity and trust list in a 0700 config directory, the pairing
//! window (a 12-digit code and a QR link, 5 minutes, single use, 5 wrong tries, spacing), the
//! device's "ask", and kind 18's signed MacInfo.
//!
//! As `SillHost --pairing` does it: a window is always open, its code printed to stdout (never sent
//! anywhere), a fresh one after each use or expiry; an ask while it is open is answered "shown" and
//! the code printed again. No USB-cable pairing (the Mac's rule reads its own IOKit), no lock check.

use crate::log;
use sill_protocol::identity::{base64_std, base64url, mac_id, random_bytes, short_name, Identity};
use sill_protocol::messages::{to_json, MacInfo, PairRequest, PairResult, SignedMacInfo};
use sill_protocol::pairing::{self as proofs, generate_code, grouped, pair_link};
use sill_protocol::text::label;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

/// One paired device, as the trust list keeps it.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct PairedDevice {
    /// base64url of its SPKI SHA-256.
    pub fingerprint: String,
    pub name: String,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub model: Option<String>,
    #[serde(rename = "pairedAt")]
    pub paired_at: f64,
    /// "qr", "code".
    pub method: String,
}

impl PairedDevice {
    /// "iPad (iPad14,1)", as the Mac shows a paired device.
    pub fn display_name(&self) -> String {
        match &self.model {
            Some(m) if !m.is_empty() => format!("{} ({m})", if self.name.is_empty() { "Device" } else { &self.name }),
            _ => {
                if self.name.is_empty() {
                    "a device".into()
                } else {
                    self.name.clone()
                }
            }
        }
    }
}

/// The config directory: the identity (PKCS#8), the recognition key and the trust list, 0700.
pub struct Store {
    pub dir: PathBuf,
}

impl Store {
    /// `dir`, else SILL_CONFIG_DIR, else the platform's config directory + "sill".
    pub fn open(dir: Option<PathBuf>) -> Result<Store, String> {
        let dir = dir
            .or_else(|| std::env::var_os("SILL_CONFIG_DIR").map(PathBuf::from))
            .or_else(default_dir)
            .ok_or("no config directory: give --config-dir")?;
        fs::create_dir_all(&dir).map_err(|e| format!("{}: {e}", dir.display()))?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            fs::set_permissions(&dir, fs::Permissions::from_mode(0o700)).map_err(|e| format!("{}: {e}", dir.display()))?;
        }
        Ok(Store { dir })
    }

    fn write_private(&self, name: &str, data: &[u8]) -> Result<(), String> {
        let path = self.dir.join(name);
        let tmp = self.dir.join(format!(".{name}.tmp"));
        fs::write(&tmp, data).map_err(|e| format!("{}: {e}", tmp.display()))?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let _ = fs::set_permissions(&tmp, fs::Permissions::from_mode(0o600));
        }
        fs::rename(&tmp, &path).map_err(|e| format!("{}: {e}", path.display()))
    }

    /// The identity, made on first use.
    pub fn identity(&self) -> Result<Identity, String> {
        let path = self.dir.join("identity.p8");
        match fs::read(&path) {
            Ok(der) => Identity::from_pkcs8(&der).map_err(|e| format!("{}: {e}", path.display())),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
                let id = Identity::generate()?;
                self.write_private("identity.p8", &id.pkcs8)?;
                Ok(id)
            }
            Err(e) => Err(format!("{}: {e}", path.display())),
        }
    }

    /// 32 bytes that resolve this host's TXT tag, made on first use.
    pub fn recognition_key(&self) -> Result<Vec<u8>, String> {
        let path = self.dir.join("recognition.key");
        match fs::read(&path) {
            Ok(k) if k.len() == 32 => Ok(k),
            Ok(_) => Err(format!("{}: not 32 bytes", path.display())),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
                let k = random_bytes(32);
                self.write_private("recognition.key", &k)?;
                Ok(k)
            }
            Err(e) => Err(format!("{}: {e}", path.display())),
        }
    }

    pub fn paired(&self) -> Result<Vec<PairedDevice>, String> {
        let path = self.dir.join("paired.json");
        match fs::read(&path) {
            Ok(b) => serde_json::from_slice(&b).map_err(|e| format!("{}: {e}", path.display())),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(Vec::new()),
            Err(e) => Err(format!("{}: {e}", path.display())),
        }
    }

    pub fn save_paired(&self, list: &[PairedDevice]) -> Result<(), String> {
        self.write_private("paired.json", &serde_json::to_vec_pretty(list).map_err(|e| e.to_string())?)
    }
}

fn default_dir() -> Option<PathBuf> {
    if cfg!(windows) {
        return std::env::var_os("APPDATA").map(|a| PathBuf::from(a).join("Sill"));
    }
    if let Some(x) = std::env::var_os("XDG_CONFIG_HOME").filter(|x| !x.is_empty()) {
        return Some(PathBuf::from(x).join("sill"));
    }
    std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".config").join("sill"))
}

fn now_epoch() -> f64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs_f64()).unwrap_or(0.0)
}

// MARK: The pairing window (PairingWindow.swift)

pub const LIFETIME: Duration = Duration::from_secs(300);
pub const MAX_FAILURES: u32 = 5;
const SOURCE_SPACING: Duration = Duration::from_secs(5);
const SPACING: [u64; 4] = [1, 2, 4, 8];

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CloseReason {
    Used,
    Expired,
    Stopped,
    Withdrawn,
    None,
}

struct Window {
    secret: Vec<u8>,
    code: String,
    code_key: Option<[u8; 32]>,
    expires_at: Instant,
    failures: u32,
    next_allowed_at: Instant,
    last_attempt_by_source: HashMap<String, Instant>,
    /// The device whose ask opened it, if one did.
    by_device: Option<[u8; 32]>,
    /// The remote door takes proofs for it (this host's own windows while the remote door runs).
    for_remote: bool,
}

#[derive(Debug, PartialEq)]
enum Verdict {
    Accept(Vec<u8>),
    Reject(u32),
    Busy(f64),
    Closed(CloseReason),
}

/// The ask rule's verdict (DoorPolicy.ask) without the cable and lock steps.
#[derive(Debug, PartialEq)]
enum Ask {
    Shown { opened: bool },
    OpenOnMac(&'static str),
}

/// One pairing attempt, as the door hands it over.
pub struct Attempt {
    pub request: PairRequest,
    /// From the TLS session, never from the message.
    pub device_fingerprint: [u8; 32],
    /// The source address without its zone (per-source rules).
    pub source: String,
    pub display: String,
    /// Loopback, or one of this machine's own addresses.
    pub from_this_machine: bool,
    /// It came through the remote door (an ask or a cancel there is answered closed, and a proof
    /// counts only for a window the remote door runs for).
    pub remote: bool,
}

/// The remote door as pairing and kind 18 see it.
#[derive(Clone, Debug)]
pub struct RemoteDoor {
    /// The port it listens on (devices dial it from afar).
    pub port: u16,
    pub internet: bool,
    /// Listening on 127.0.0.1 only (tests): the address list is "127.0.0.1", as the Mac's test hosts.
    pub loopback: bool,
    /// Whether the TLS home door also runs (the startup line says so).
    pub home_tls: bool,
}

struct State {
    window: Option<Window>,
    closed: CloseReason,
    paired: Vec<PairedDevice>,
    /// Ask limits: device-opened windows in the last 10 minutes, and askers kept quiet.
    opened_at: Vec<Instant>,
    quiet: HashMap<String, Instant>,
}

pub struct Pairing {
    pub identity: Arc<Identity>,
    pub recognition_key: Vec<u8>,
    pub name: String,
    store: Store,
    state: Mutex<State>,
    /// The remote port a link names (7455 unless a remote door runs elsewhere).
    pub link_port: u16,
    /// The remote door, once it listens.
    remote: Mutex<Option<RemoteDoor>>,
}

const ASK_SPAN: Duration = Duration::from_secs(600);
const ASK_MAX_WINDOWS: usize = 3;

impl Pairing {
    pub fn new(store: Store, name: &str) -> Result<Arc<Pairing>, String> {
        let identity = Arc::new(store.identity()?);
        let recognition_key = store.recognition_key()?;
        let paired = store.paired()?;
        let clean = label(name);
        Ok(Arc::new(Pairing {
            identity,
            recognition_key,
            name: if clean.is_empty() { "PC".into() } else { clean },
            store,
            state: Mutex::new(State { window: None, closed: CloseReason::None, paired, opened_at: Vec::new(), quiet: HashMap::new() }),
            link_port: 7455,
            remote: Mutex::new(None),
        }))
    }

    /// The remote door listens (or stops: None). Windows opened from now on are its too.
    pub fn set_remote(&self, door: Option<RemoteDoor>) {
        *self.remote.lock().unwrap() = door;
    }

    pub fn remote(&self) -> Option<RemoteDoor> {
        self.remote.lock().unwrap().clone()
    }

    /// A window the remote door takes proofs for is open (its `sill-pair/1` is admitted then).
    pub fn remote_window_open(&self) -> bool {
        self.state.lock().unwrap().window.as_ref().map(|w| w.for_remote).unwrap_or(false)
    }

    /// The addresses a device away from home dials (kind 18, the pairing link), in the Mac's order:
    /// VPN addresses (Tailscale's 100.64/10 first), then this network's address.
    pub fn addresses(&self) -> Vec<sill_protocol::messages::MacAddress> {
        use sill_protocol::messages::MacAddress;
        let Some(door) = self.remote() else { return Vec::new() };
        if door.loopback {
            return vec![MacAddress { host: "127.0.0.1".into(), port: None, kind: MacAddress::LAN.into(), via: "This Mac".into() }];
        }
        let mut vpn = Vec::new();
        let mut lan = Vec::new();
        for i in if_addrs::get_if_addrs().unwrap_or_default() {
            let if_addrs::IfAddr::V4(a) = &i.addr else { continue };
            let ip = a.ip;
            if ip.is_loopback() || ip.is_link_local() || ip.is_unspecified() {
                continue;
            }
            let o = ip.octets();
            let cgnat = o[0] == 100 && (o[1] & 0xC0) == 64;
            let name = i.name.to_ascii_lowercase();
            let tunnel = ["utun", "tun", "wg", "tailscale", "zt", "ppp", "ipsec"].iter().any(|p| name.starts_with(p));
            if cgnat || tunnel {
                let via = if cgnat || name.contains("tailscale") { "Tailscale".to_string() } else { format!("VPN ({})", i.name) };
                vpn.push((!cgnat, MacAddress { host: ip.to_string(), port: None, kind: MacAddress::VPN.into(), via }));
            } else if ip.is_private() {
                lan.push(MacAddress { host: ip.to_string(), port: None, kind: MacAddress::LAN.into(), via: i.name.clone() });
            }
        }
        vpn.sort_by_key(|(not_tailscale, _)| *not_tailscale);
        let mut out: Vec<MacAddress> = vpn.into_iter().map(|(_, a)| a).collect();
        out.extend(lan.into_iter().take(1));
        out.truncate(12);
        out
    }

    pub fn store_dir(&self) -> &Path {
        &self.store.dir
    }

    pub fn paired_count(&self) -> usize {
        self.state.lock().unwrap().paired.len()
    }

    /// The paired device with this key, by name; None when the key is not paired.
    pub fn paired_name(&self, fp: &[u8; 32]) -> Option<String> {
        let b = base64url::encode(fp);
        self.state.lock().unwrap().paired.iter().find(|d| d.fingerprint == b).map(|d| d.display_name())
    }

    /// The TXT record's keys: a fresh recognition tag, and `p` = "1" (pairing required) when the
    /// home door speaks TLS (no `p`: a plain door, as SillHost --remote without --pairing).
    pub fn txt(&self, home_tls: bool) -> Vec<(String, String)> {
        let mut v = vec![(proofs::TXT_RECOGNITION.to_string(), proofs::recognition_tag(&self.recognition_key, None))];
        if home_tls {
            v.push((proofs::TXT_HOME_DOOR.to_string(), proofs::home_door_value(true).to_string()));
        }
        v
    }

    /// Kind 18's payload: MacInfo's exact JSON bytes, signed with the identity key.
    pub fn signed_mac_info(&self) -> Option<Vec<u8>> {
        let door = self.remote();
        let info = MacInfo {
            v: 1,
            mac_id: mac_id(&self.identity.fingerprint),
            name: self.name.clone(),
            issued_at: now_epoch(),
            remote_access: door.is_some(),
            remote_port: door.as_ref().map(|d| d.port).unwrap_or(self.link_port) as i64,
            internet: door.as_ref().map(|d| d.internet).unwrap_or(false),
            addresses: self.addresses(),
        };
        let bytes = to_json(&info);
        let sig = self.identity.sign(&bytes).ok()?;
        Some(to_json(&SignedMacInfo { info: base64_std(&bytes), key: base64_std(&self.identity.point), sig: base64_std(&sig) }))
    }

    /// Opens a window (the host's own: always one open, as SillHost --pairing) and prints its code.
    /// `asked_by`: the device whose ask opened it.
    pub fn open_window(self: &Arc<Self>, asked_by: Option<([u8; 32], &str)>, first: bool) {
        let code = generate_code();
        let secret = random_bytes(16);
        let door = self.remote();
        // This host's own window is the remote door's too while it runs; a device's ask opens one
        // for the home door alone, whose link names no address.
        let for_remote = door.is_some() && asked_by.is_none();
        let link = self.link_for(&secret, for_remote);
        {
            let mut st = self.state.lock().unwrap();
            st.window = Some(Window {
                secret,
                code: code.clone(),
                code_key: None,
                expires_at: Instant::now() + pairing_lifetime(),
                failures: 0,
                next_allowed_at: Instant::now(),
                last_attempt_by_source: HashMap::new(),
                by_device: asked_by.map(|a| a.0),
                for_remote,
            });
            if asked_by.is_some() {
                st.opened_at.retain(|t| t.elapsed() < ASK_SPAN);
                st.opened_at.push(Instant::now());
            }
        }
        // K for the typed path (PBKDF2, 600,000 rounds), off the caller's thread; a code proof
        // before it is ready is answered busy.
        let me = self.clone();
        let c = code.clone();
        std::thread::spawn(move || {
            if let Some(k) = proofs::code_key(&c, &me.identity.fingerprint) {
                let mut st = me.state.lock().unwrap();
                if let Some(w) = st.window.as_mut().filter(|w| w.code == c) {
                    w.code_key = Some(k);
                }
            }
        });
        if first {
            match &door {
                Some(d) => {
                    log(&format!("Remote access for this run on port {} (TLS, paired devices only). Pair with {} or {link}", d.port, grouped(&code)));
                    if d.home_tls {
                        log("Pairing required for this run (TLS on the home door).");
                    }
                }
                None => log(&format!("Pairing required for this run (TLS on the home door). Pair with {} or {link}", grouped(&code))),
            }
        } else if let Some((_, who)) = asked_by {
            log(&format!("Pairing: {who} asked; code {} or {link}", grouped(&code)));
        } else {
            log(&format!("Pairing: new code {} or {link}", grouped(&code)));
        }
    }

    /// A window's link: the remote door's port and addresses (at most 5) when it runs for it.
    fn link_for(&self, secret: &[u8], for_remote: bool) -> String {
        match self.remote().filter(|_| for_remote) {
            Some(d) => {
                let addresses: Vec<String> = self.addresses().iter().take(5).map(|a| a.host.clone()).collect();
                pair_link(&self.identity.fingerprint, secret, &self.name, d.port, &addresses)
            }
            None => pair_link(&self.identity.fingerprint, secret, &self.name, self.remote().map(|d| d.port).unwrap_or(self.link_port), &[]),
        }
    }

    /// The open window's code again (an ask while it is up).
    fn offer_again(&self, who: &str) {
        let open = self.state.lock().unwrap().window.as_ref().map(|w| (w.secret.clone(), w.for_remote, w.code.clone()));
        if let Some((secret, for_remote, code)) = open {
            let link = self.link_for(&secret, for_remote);
            log(&format!("Pairing: {who} asked; code {} or {link}", grouped(&code)));
        }
    }

    /// Closes an expired window and opens a fresh one (the CLI's "always open" rule). Called once a
    /// second by the door.
    pub fn tick(self: &Arc<Self>) {
        let expired = {
            let mut st = self.state.lock().unwrap();
            match &st.window {
                Some(w) if Instant::now() >= w.expires_at => {
                    st.window = None;
                    st.closed = CloseReason::Expired;
                    true
                }
                _ => false,
            }
        };
        if expired {
            self.open_window(None, false);
        }
    }

    /// One kind 19, judged: an ask, a cancel, or a proof for the window.
    pub fn judge(self: &Arc<Self>, a: &Attempt) -> PairResult {
        let r = &a.request;
        // A later generation of pairing comes with a later `v`: answered closed, no try counted.
        if r.v != PairRequest::VERSION {
            return PairResult::refused(PairResult::CLOSED);
        }
        let who = display_name(r);
        // The remote door answers an ask and a cancel `closed` with no try counted, and takes a
        // proof only for a window it runs for.
        if a.remote
            && (r.method == PairRequest::ASK || r.method == PairRequest::CANCEL || !self.remote_window_open())
        {
            return PairResult::refused(PairResult::CLOSED);
        }
        if r.method == PairRequest::ASK {
            return self.ask(a, &who);
        }
        if r.method == PairRequest::CANCEL {
            let mut st = self.state.lock().unwrap();
            if st.window.as_ref().and_then(|w| w.by_device) == Some(a.device_fingerprint) {
                st.window = None;
                st.closed = CloseReason::Withdrawn;
                drop(st);
                log(&format!("Pairing: {who} at {} no longer needs its code; the window closed.", a.display));
                self.open_window(None, false);
            }
            return PairResult::refused(PairResult::CLOSED);
        }
        let proof = base64url::decode(&r.proof).unwrap_or_default();
        let (verdict, was_open) = {
            let mut st = self.state.lock().unwrap();
            let was_open = st.window.is_some();
            let v = try_proof(&mut st, &r.method, &proof, &a.device_fingerprint, &self.identity.fingerprint, &a.source);
            (v, was_open)
        };
        match verdict {
            Verdict::Accept(proof_m) => {
                let device = PairedDevice {
                    fingerprint: base64url::encode(&a.device_fingerprint),
                    name: label(&r.name),
                    model: r.model.as_deref().map(label).filter(|m| !m.is_empty()),
                    paired_at: now_epoch(),
                    method: r.method.clone(),
                };
                let saved = {
                    let mut st = self.state.lock().unwrap();
                    let mut next = st.paired.clone();
                    next.retain(|d| d.fingerprint != device.fingerprint);
                    next.push(device.clone());
                    let saved = self.store.save_paired(&next);
                    if saved.is_ok() {
                        st.paired = next;
                    }
                    saved
                };
                if let Err(e) = saved {
                    log(&format!("Pairing: {} not paired: the paired devices could not be saved ({e}).", device.display_name()));
                    self.open_window(None, false);
                    return PairResult::refused(PairResult::CLOSED);
                }
                log(&format!(
                    "Paired {} (key {}…) from {}, with {}.",
                    device.display_name(),
                    short_name(&a.device_fingerprint),
                    a.display,
                    if r.method == PairRequest::QR { "the QR code" } else { "the code" }
                ));
                self.open_window(None, false);
                PairResult {
                    ok: true,
                    proof: Some(base64url::encode(&proof_m)),
                    mac_id: Some(mac_id(&self.identity.fingerprint)),
                    name: Some(self.name.clone()),
                    recognition_key: Some(base64url::encode(&self.recognition_key)),
                    ..Default::default()
                }
            }
            Verdict::Reject(left) => {
                log(&format!("Pairing: a wrong code from {} ({left} tr{} left).", a.display, if left == 1 { "y" } else { "ies" }));
                PairResult { tries_left: Some(left as i64), ..PairResult::refused(PairResult::CODE) }
            }
            Verdict::Busy(after) => PairResult { retry_after: Some((after * 10.0).ceil() / 10.0), ..PairResult::refused(PairResult::BUSY) },
            Verdict::Closed(reason) => {
                if was_open && reason == CloseReason::Stopped {
                    log(&format!("Pairing stopped after {MAX_FAILURES} wrong codes."));
                }
                if was_open && reason == CloseReason::Expired {
                    self.open_window(None, false);
                }
                let word = match reason {
                    CloseReason::Stopped if was_open => PairResult::STOPPED,
                    CloseReason::Expired => PairResult::EXPIRED,
                    _ => PairResult::CLOSED,
                };
                PairResult::refused(word)
            }
        }
    }

    /// "Pair me, now if you can, else show me your code": the ask rule without the cable and lock
    /// steps (DoorPolicy.ask).
    fn ask(self: &Arc<Self>, a: &Attempt, who: &str) -> PairResult {
        let verdict = {
            let mut st = self.state.lock().unwrap();
            st.quiet.retain(|_, t| t.elapsed() < ASK_SPAN);
            st.opened_at.retain(|t| t.elapsed() < ASK_SPAN);
            let quiet = st.quiet.contains_key(&base64url::encode(&a.device_fingerprint)) || st.quiet.contains_key(&a.source);
            if st.window.is_some() {
                Ask::Shown { opened: false }
            } else if a.from_this_machine && std::env::var("SILL_TEST_ASK_FROM_THIS_MAC").as_deref() != Ok("1") {
                Ask::OpenOnMac("it asked from this computer")
            } else if quiet {
                Ask::OpenOnMac("its last window was closed")
            } else if st.opened_at.len() >= ASK_MAX_WINDOWS {
                Ask::OpenOnMac("too many windows")
            } else {
                Ask::Shown { opened: true }
            }
        };
        match verdict {
            Ask::Shown { opened: false } => {
                log(&format!("Pairing: {who} at {} asked to pair; the code is already showing.", a.display));
                self.offer_again(who);
                PairResult::refused(PairResult::SHOWN)
            }
            Ask::Shown { opened: true } => {
                log(&format!("Pairing: {who} at {} asked to pair; showing the code.", a.display));
                self.open_window(Some((a.device_fingerprint, who)), false);
                PairResult::refused(PairResult::SHOWN)
            }
            Ask::OpenOnMac(why) => {
                log(&format!("Pairing: {who} at {} asked to pair; not shown ({why}).", a.display));
                PairResult::refused(PairResult::OPEN_ON_MAC)
            }
        }
    }
}

/// SILL_TEST_PAIRING_TTL (seconds), else 5 minutes.
fn pairing_lifetime() -> Duration {
    std::env::var("SILL_TEST_PAIRING_TTL")
        .ok()
        .and_then(|v| v.parse::<f64>().ok())
        .filter(|s| *s > 0.0)
        .map(Duration::from_secs_f64)
        .unwrap_or(LIFETIME)
}

fn display_name(r: &PairRequest) -> String {
    PairedDevice {
        fingerprint: String::new(),
        name: label(&r.name),
        model: r.model.as_deref().map(label).filter(|m| !m.is_empty()),
        paired_at: 0.0,
        method: String::new(),
    }
    .display_name()
}

/// PairingWindow.tryProof.
fn try_proof(st: &mut State, method: &str, proof: &[u8], fp_device: &[u8; 32], fp_mac: &[u8; 32], source: &str) -> Verdict {
    let now = Instant::now();
    let Some(w) = st.window.as_mut() else { return Verdict::Closed(st.closed) };
    if now >= w.expires_at {
        st.window = None;
        st.closed = CloseReason::Expired;
        return Verdict::Closed(CloseReason::Expired);
    }
    if now < w.next_allowed_at {
        return Verdict::Busy((w.next_allowed_at - now).as_secs_f64());
    }
    if let Some(last) = w.last_attempt_by_source.get(source) {
        let since = now.duration_since(*last);
        if since < SOURCE_SPACING {
            return Verdict::Busy((SOURCE_SPACING - since).as_secs_f64());
        }
    }
    let key: Option<Vec<u8>> = match method {
        PairRequest::QR => Some(w.secret.clone()),
        PairRequest::CODE => match w.code_key {
            Some(k) => Some(k.to_vec()),
            None => return Verdict::Busy(1.0),
        },
        _ => None, // an unknown method never matches: a wrong proof
    };
    w.last_attempt_by_source.insert(source.to_string(), now);
    if let Some(key) = key {
        if proofs::is_valid_device_proof(proof, &key, fp_device, fp_mac) {
            st.window = None;
            st.closed = CloseReason::Used;
            return Verdict::Accept(proofs::mac_proof(&key, fp_mac, fp_device));
        }
    }
    w.failures += 1;
    if w.failures >= MAX_FAILURES {
        if let Some(asker) = w.by_device {
            st.quiet.insert(base64url::encode(&asker), now);
        }
        st.quiet.insert(source.to_string(), now);
        st.window = None;
        st.closed = CloseReason::Stopped;
        return Verdict::Closed(CloseReason::Stopped);
    }
    w.next_allowed_at = now + Duration::from_secs(SPACING[(w.failures as usize - 1).min(SPACING.len() - 1)]);
    Verdict::Reject(MAX_FAILURES - w.failures)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn pairing() -> (Arc<Pairing>, PathBuf) {
        let dir = std::env::temp_dir().join(format!("sill-pairing-test-{}", base64url::encode(&random_bytes(6))));
        let p = Pairing::new(Store::open(Some(dir.clone())).unwrap(), "Test PC").unwrap();
        (p, dir)
    }

    fn attempt(method: &str, proof: &[u8], dev: [u8; 32], source: &str) -> Attempt {
        Attempt {
            request: PairRequest { v: 1, method: method.into(), proof: base64url::encode(proof), name: "iPad".into(), model: Some("iPad14,1".into()), cable: None },
            device_fingerprint: dev,
            source: source.into(),
            display: source.into(),
            from_this_machine: false,
            remote: false,
        }
    }

    #[test]
    fn qr_pairs_once_and_persists() {
        let (p, dir) = pairing();
        p.open_window(None, true);
        let secret = p.state.lock().unwrap().window.as_ref().unwrap().secret.clone();
        let dev = [3u8; 32];
        let proof = proofs::device_proof(&secret, &dev, &p.identity.fingerprint);
        let r = p.judge(&attempt("qr", &proof, dev, "10.0.0.2"));
        assert!(r.ok, "{r:?}");
        let want = proofs::mac_proof(&secret, &p.identity.fingerprint, &dev);
        assert_eq!(base64url::decode(r.proof.as_deref().unwrap()).unwrap(), want);
        assert_eq!(r.mac_id.as_deref(), Some(mac_id(&p.identity.fingerprint).as_str()));
        assert_eq!(p.paired_name(&dev).as_deref(), Some("iPad (iPad14,1)"));
        // A fresh window: the old secret no longer works.
        let again = p.judge(&attempt("qr", &proof, [4u8; 32], "10.0.0.3"));
        assert_eq!(again.reason.as_deref(), Some("code"));
        // The identity and the trust list come back from the directory.
        let q = Pairing::new(Store::open(Some(dir.clone())).unwrap(), "Test PC").unwrap();
        assert_eq!(q.identity.fingerprint, p.identity.fingerprint);
        assert!(q.paired_name(&dev).is_some());
        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn wrong_codes_space_out_then_stop() {
        let (p, dir) = pairing();
        p.open_window(None, true);
        let dev = [5u8; 32];
        let r = p.judge(&attempt("qr", &[0u8; 32], dev, "a"));
        assert_eq!((r.reason.as_deref(), r.tries_left), (Some("code"), Some(4)));
        let r = p.judge(&attempt("qr", &[0u8; 32], dev, "b"));
        assert_eq!(r.reason.as_deref(), Some("busy"));
        // Past the spacing, from other sources, until the window stops.
        for (i, src) in ["c", "d", "e", "f"].iter().enumerate() {
            if let Some(w) = p.state.lock().unwrap().window.as_mut() {
                w.next_allowed_at = Instant::now();
            }
            let r = p.judge(&attempt("qr", &[0u8; 32], dev, src));
            if i < 3 {
                assert_eq!(r.reason.as_deref(), Some("code"));
            } else {
                assert_eq!(r.reason.as_deref(), Some("stopped"));
            }
        }
        let r = p.judge(&attempt("qr", &[0u8; 32], dev, "g"));
        assert_eq!(r.reason.as_deref(), Some("closed"));
        // An ask now: the asker's source is quiet only if it was the one stopped; another opens.
        let mut ask = attempt("ask", &[], [9u8; 32], "h");
        ask.request.proof = String::new();
        assert_eq!(p.judge(&ask).reason.as_deref(), Some("shown"));
        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn later_generation_is_closed() {
        let (p, dir) = pairing();
        p.open_window(None, true);
        let mut a = attempt("code", &[0u8; 32], [1u8; 32], "x");
        a.request.v = 2;
        assert_eq!(p.judge(&a).reason.as_deref(), Some("closed"));
        assert_eq!(p.state.lock().unwrap().window.as_ref().unwrap().failures, 0);
        let _ = fs::remove_dir_all(dir);
    }
}
