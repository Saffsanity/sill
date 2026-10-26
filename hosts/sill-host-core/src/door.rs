//! Admission at the TLS home door (Door.swift, DoorPolicy.swift), as Sill.app's and
//! `SillHost --pairing`'s: TLS 1.3, both keys pinned, `sill/1` for a paired key's session,
//! `sill-pair/1` for one pairing request. Pending connections are capped (8 in all, 2 per source),
//! 10 s from accept to admission; a source the door refused 5 times in 60 s is refused for 300 s
//! (a paired key clears its count). Sources the home door does not admit (a VPN, the internet) are
//! closed before a byte is sent. Refusals are counted and summed up once a minute.

use crate::log;
use crate::origin::{classify, Origin};
use crate::pairing::{Attempt, Pairing};
use crate::server::{Route, Server};
use crate::tls_transport::TlsTransport;
use sill_protocol::identity::certificate_fingerprint;
use sill_protocol::messages::{from_json, to_json, PairRequest, PairResult};
use sill_protocol::tls::{chosen_alpn, server_config, TrustFn, PAIRING_ALPN, SESSION_ALPN};
use sill_protocol::wire::{message_now, Header, Kind, HEADER_LEN, MAX_PAIRING_PAYLOAD};
use std::collections::{BTreeMap, HashMap};
use std::io::{Read, Write};
use std::net::{IpAddr, TcpStream};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

const MAX_PENDING: usize = 8;
const MAX_PENDING_PER_SOURCE: usize = 2;
const ADMISSION_DEADLINE: Duration = Duration::from_secs(10);
const FAILURE_WINDOW: Duration = Duration::from_secs(60);
const FAILURES_FOR_BACKOFF: usize = 5;

#[derive(Default)]
struct State {
    pending: HashMap<IpAddr, usize>,
    total: usize,
    failures: HashMap<IpAddr, Vec<Instant>>,
    backoff_until: HashMap<IpAddr, Instant>,
    refusals: BTreeMap<&'static str, u64>,
}

/// Which door: the home door (this machine's own networks) or the remote door (VPNs and this
/// network; the internet only with `internet`).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum DoorKind {
    Home,
    Remote { internet: bool },
}

const MAX_REMOTE_SESSIONS: usize = 8;

pub struct Door {
    pub kind: DoorKind,
    pairing: Arc<Pairing>,
    server: Arc<Server>,
    state: Mutex<State>,
    backoff: Duration,
}

/// The pending slot of one connection, given back however it ends.
struct Slot<'a> {
    door: &'a Door,
    source: IpAddr,
}

impl Drop for Slot<'_> {
    fn drop(&mut self) {
        let mut st = self.door.state.lock().unwrap();
        st.total = st.total.saturating_sub(1);
        if let Some(n) = st.pending.get_mut(&self.source) {
            *n -= 1;
            if *n == 0 {
                st.pending.remove(&self.source);
            }
        }
    }
}

enum Outcome {
    /// Nothing to count: the peer went away by itself.
    Gone,
    Refused(&'static str),
    Admitted,
}

impl Door {
    pub fn new(kind: DoorKind, pairing: Arc<Pairing>, server: Arc<Server>) -> Arc<Door> {
        let backoff = std::env::var("SILL_TEST_BACKOFF_SECONDS")
            .ok()
            .and_then(|v| v.parse::<f64>().ok())
            .filter(|s| *s > 0.0)
            .map(Duration::from_secs_f64)
            .unwrap_or(Duration::from_secs(300));
        let door = Arc::new(Door { kind, pairing, server, state: Mutex::new(State::default()), backoff });
        // The once-a-minute summary of refusals.
        let weak = Arc::downgrade(&door);
        std::thread::Builder::new()
            .name("sill-door-summary".into())
            .spawn(move || loop {
                std::thread::sleep(Duration::from_secs(60));
                let Some(d) = weak.upgrade() else { return };
                let c = std::mem::take(&mut d.state.lock().unwrap().refusals);
                let n: u64 = c.values().sum();
                let g = |k: &str| c.get(k).copied().unwrap_or(0);
                if n > 0 && d.kind != DoorKind::Home {
                    log(&format!(
                        "Remote access refused {n} connection{} in the last minute: {} unpaired, {} from the internet (internet access off), {} over the limit.",
                        if n == 1 { "" } else { "s" },
                        g("unpaired"),
                        g("internet"),
                        g("limit")
                    ));
                } else if n > 0 {
                    log(&format!(
                        "Home door refused {n} connection{} in the last minute: {} unpaired, {} through a VPN, {} from the internet, {} from an older Sill (not TLS), {} over the limit.",
                        if n == 1 { "" } else { "s" },
                        g("unpaired"),
                        g("vpn"),
                        g("internet"),
                        g("older"),
                        g("limit")
                    ));
                }
            })
            .expect("door summary thread");
        door
    }

    fn count(&self, word: &'static str) {
        *self.state.lock().unwrap().refusals.entry(word).or_insert(0) += 1;
    }

    /// One failure for `source`; the fifth within a minute starts its backoff.
    fn count_failure(&self, source: IpAddr) {
        let mut st = self.state.lock().unwrap();
        let list = st.failures.entry(source).or_default();
        list.retain(|t| t.elapsed() < FAILURE_WINDOW);
        list.push(Instant::now());
        if list.len() >= FAILURES_FOR_BACKOFF {
            list.clear();
            let until = Instant::now() + self.backoff;
            st.backoff_until.insert(source, until);
        }
        if st.failures.len() > 256 {
            st.failures.retain(|_, l| l.iter().any(|t| t.elapsed() < FAILURE_WINDOW));
        }
    }

    /// A source that proved itself starts clean.
    fn forgive(&self, source: IpAddr) {
        let mut st = self.state.lock().unwrap();
        st.failures.remove(&source);
        st.backoff_until.remove(&source);
    }

    /// A new connection from the listener; admission runs on its own thread.
    pub fn accept(self: &Arc<Door>, stream: TcpStream) {
        let Ok(peer) = stream.peer_addr() else { return };
        let source = match peer.ip() {
            IpAddr::V6(v6) => v6.to_ipv4_mapped().map(IpAddr::V4).unwrap_or(IpAddr::V6(v6)),
            ip => ip,
        };
        // The origin before a byte is sent: a source this door does not admit gets nothing.
        let mut origin = classify(source);
        // TEST ONLY: SILL_TEST_REMOTE_ORIGIN=vpn|internet makes loopback at the remote door count as
        // that origin, so one loopback host serves a device away (the Mac's test hook).
        if origin == Origin::Loopback && self.kind != DoorKind::Home {
            match std::env::var("SILL_TEST_REMOTE_ORIGIN").as_deref() {
                Ok("vpn") => origin = Origin::Vpn,
                Ok("internet") => origin = Origin::Internet,
                _ => {}
            }
        }
        let admitted = match self.kind {
            DoorKind::Home => origin.home_admits(),
            DoorKind::Remote { internet } => match origin {
                Origin::Loopback | Origin::Lan | Origin::Vpn => true,
                Origin::Internet => internet,
                Origin::Direct => false,
            },
        };
        if !admitted {
            self.count(if origin == Origin::Vpn { "vpn" } else { "internet" });
            self.count_failure(source);
            return;
        }
        {
            let mut st = self.state.lock().unwrap();
            if let Some(until) = st.backoff_until.get(&source) {
                if Instant::now() < *until {
                    st.refusals.entry("limit").and_modify(|n| *n += 1).or_insert(1);
                    return;
                }
            }
            let from_source = st.pending.get(&source).copied().unwrap_or(0);
            if st.total >= MAX_PENDING || from_source >= MAX_PENDING_PER_SOURCE {
                st.refusals.entry("limit").and_modify(|n| *n += 1).or_insert(1);
                return;
            }
            st.total += 1;
            *st.pending.entry(source).or_insert(0) += 1;
        }
        let door = self.clone();
        std::thread::spawn(move || {
            let slot = Slot { door: &door, source };
            let display = match peer {
                std::net::SocketAddr::V6(v6) if v6.scope_id() != 0 && source.is_ipv6() => format!("{}%{}", source, v6.scope_id()),
                _ => source.to_string(),
            };
            let outcome = door.admit(stream, source, display, origin);
            drop(slot);
            match outcome {
                Outcome::Refused(word) => {
                    door.count(word);
                    door.count_failure(source);
                }
                Outcome::Gone | Outcome::Admitted => {}
            }
        });
    }

    fn admit(self: &Arc<Door>, mut tcp: TcpStream, source: IpAddr, display: String, origin: Origin) -> Outcome {
        let deadline = Instant::now() + ADMISSION_DEADLINE;
        let left = || deadline.saturating_duration_since(Instant::now()).max(Duration::from_millis(1));
        let _ = tcp.set_read_timeout(Some(left()));
        let _ = tcp.set_write_timeout(Some(ADMISSION_DEADLINE));
        // The ClientHello first: its ALPN decides how this connection's key is trusted.
        let mut acceptor = rustls::server::Acceptor::default();
        let mut first_byte_checked = false;
        let accepted = loop {
            match acceptor.read_tls(&mut tcp) {
                Ok(0) => return Outcome::Gone,
                Ok(_) => {}
                Err(_) => return Outcome::Refused("unpaired"),
            }
            match acceptor.accept() {
                Ok(Some(a)) => break a,
                Ok(None) => {
                    first_byte_checked = true;
                    continue;
                }
                Err((_, _)) => {
                    // Not TLS: an older Sill speaking the plain protocol (its header starts with a
                    // small kind byte, never a TLS record's 0x16). Counted, never held against it.
                    let _ = first_byte_checked;
                    return Outcome::Refused("older");
                }
            }
        };
        let offered: Vec<Vec<u8>> = accepted.client_hello().alpn().map(|i| i.map(|p| p.to_vec()).collect()).unwrap_or_default();
        let alpn = chosen_alpn(&offered);
        let pairing = self.pairing.clone();
        let remote = self.kind != DoorKind::Home;
        // DoorPolicy.trusts: a session for a paired key at either door; pairing at home always,
        // at the remote door only while a window it runs for is open.
        let trust: TrustFn = Arc::new(move |fp, alpn| {
            let Some(fp) = fp else { return false };
            match alpn {
                Some(a) if a == SESSION_ALPN => pairing.paired_name(&fp).is_some(),
                Some(a) if a == PAIRING_ALPN => !remote || pairing.remote_window_open(),
                _ => false,
            }
        });
        let config = match server_config(&self.pairing.identity, alpn, trust) {
            Ok(c) => c,
            Err(e) => {
                log(&format!("Home door: TLS could not start ({e})."));
                return Outcome::Gone;
            }
        };
        let mut conn = match accepted.into_connection(config) {
            Ok(c) => c,
            Err((_, mut alert)) => {
                let _ = alert.write_all(&mut tcp);
                return Outcome::Refused("unpaired");
            }
        };
        while conn.is_handshaking() {
            let _ = tcp.set_read_timeout(Some(left()));
            if let Err(e) = conn.complete_io(&mut tcp) {
                // The verify block refused the key (an alert went out), the pin did not match on
                // the device's side, or the deadline passed.
                let _ = conn.complete_io(&mut tcp);
                return if e.kind() == std::io::ErrorKind::UnexpectedEof { Outcome::Gone } else { Outcome::Refused("unpaired") };
            }
        }
        let Some(fp) = conn.peer_certificates().and_then(|c| c.first()).and_then(|c| certificate_fingerprint(c.as_ref())) else {
            return Outcome::Refused("unpaired");
        };
        match conn.alpn_protocol() {
            Some(a) if a == SESSION_ALPN.as_bytes() => {
                // Judged again now: the key may have been removed during the handshake.
                let Some(name) = self.pairing.paired_name(&fp) else { return Outcome::Refused("unpaired") };
                self.forgive(source);
                let route = match self.kind {
                    DoorKind::Home => Route::HomeTls { fingerprint: fp, paired_name: Some(name) },
                    DoorKind::Remote { .. } => {
                        if self.server.remote_session_count() >= MAX_REMOTE_SESSIONS {
                            // A paired key the door does not serve now: goodbye "busy", then closed.
                            goodbye(conn, tcp, sill_protocol::messages::Goodbye::BUSY);
                            self.count("limit");
                            return Outcome::Admitted;
                        }
                        let label = match origin {
                            Origin::Vpn => {
                                if is_tailscale(source) { "through Tailscale" } else { "through your VPN" }
                            }
                            Origin::Internet => "over the internet",
                            _ => "by address",
                        };
                        Route::Remote {
                            fingerprint: fp,
                            name,
                            label: label.to_string(),
                            away: matches!(origin, Origin::Vpn | Origin::Internet),
                        }
                    }
                };
                let _ = tcp.set_read_timeout(None);
                let _ = tcp.set_write_timeout(None);
                if self.kind != DoorKind::Home {
                    crate::transport::limit_unsent(&tcp, 32 * 1024);
                }
                match TlsTransport::new(conn, tcp, fp) {
                    Ok(t) => {
                        if let Err(e) = self.server.register(Box::new(t), route, None) {
                            log(&format!("Could not serve {display}: {e}"));
                        }
                        Outcome::Admitted
                    }
                    Err(_) => Outcome::Gone,
                }
            }
            Some(a) if a == PAIRING_ALPN.as_bytes() => self.pair(conn, tcp, fp, source, display, origin, deadline),
            _ => Outcome::Refused("unpaired"),
        }
    }

    /// `sill-pair/1`: exactly one kind 19 of at most 4 KB within the deadline, one kind 20 back,
    /// then closed. A device that goes away before its kind 19 is not refused, only closed.
    #[allow(clippy::too_many_arguments)]
    fn pair(
        &self,
        mut conn: rustls::ServerConnection,
        mut tcp: TcpStream,
        fp: [u8; 32],
        source: IpAddr,
        display: String,
        origin: Origin,
        deadline: Instant,
    ) -> Outcome {
        let _ = tcp.set_read_timeout(Some(deadline.saturating_duration_since(Instant::now()).max(Duration::from_millis(1))));
        let read = |conn: &mut rustls::ServerConnection, tcp: &mut TcpStream, n: usize| -> Option<Vec<u8>> {
            let mut s = rustls::Stream::new(conn, tcp);
            let mut b = vec![0u8; n];
            s.read_exact(&mut b).ok()?;
            Some(b)
        };
        let Some(head) = read(&mut conn, &mut tcp, HEADER_LEN) else { return Outcome::Gone };
        let Some(h) = Header::parse(&head) else { return Outcome::Refused("unpaired") };
        if h.kind != Kind::PairRequest || h.payload_len == 0 || h.payload_len as usize > MAX_PAIRING_PAYLOAD {
            return Outcome::Refused("unpaired");
        }
        let Some(payload) = read(&mut conn, &mut tcp, h.payload_len as usize) else { return Outcome::Gone };
        let Some(request) = from_json::<PairRequest>(&payload) else { return Outcome::Refused("unpaired") };
        let from_this_machine = origin == Origin::Loopback;
        let attempt = Attempt {
            request,
            device_fingerprint: fp,
            source: source.to_string(),
            display,
            from_this_machine,
            remote: self.kind != DoorKind::Home,
        };
        let result: PairResult = self.pairing.judge(&attempt);
        let ok = result.ok;
        let mut s = rustls::Stream::new(&mut conn, &mut tcp);
        let _ = s.write_all(&message_now(Kind::PairResult, &to_json(&result)));
        let _ = s.flush();
        conn.send_close_notify();
        let _ = conn.complete_io(&mut tcp);
        let _ = tcp.shutdown(std::net::Shutdown::Both);
        if ok {
            self.forgive(source);
        }
        Outcome::Admitted
    }
}

/// A Tailscale address (100.64.0.0/10, or its fd7a:115c:a1e0::/48 IPv6 range).
fn is_tailscale(ip: IpAddr) -> bool {
    match ip {
        IpAddr::V4(v4) => {
            let o = v4.octets();
            o[0] == 100 && (o[1] & 0xC0) == 64
        }
        IpAddr::V6(v6) => {
            let s = v6.segments();
            s[0] == 0xfd7a && s[1] == 0x115c && s[2] == 0xa1e0
        }
    }
}

/// Kind 22 with `reason` inside TLS, then this side's close.
fn goodbye(mut conn: rustls::ServerConnection, mut tcp: TcpStream, reason: &str) {
    let g = sill_protocol::messages::Goodbye::reason(reason);
    let mut s = rustls::Stream::new(&mut conn, &mut tcp);
    let _ = s.write_all(&message_now(Kind::Goodbye, &to_json(&g)));
    let _ = s.flush();
    conn.send_close_notify();
    let _ = conn.complete_io(&mut tcp);
    let _ = tcp.shutdown(std::net::Shutdown::Both);
}
