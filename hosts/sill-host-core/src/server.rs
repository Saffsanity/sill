//! Every connected device (StreamServer.swift): one reader and one writer thread each, the frame
//! pacing (a slow client drops delta frames and waits for a keyframe rather than build a queue:
//! latency beats quality), the 30 ms ticks, ping echo, liveness and eviction, goodbyes.

use crate::stats::{self, bump};
use crate::transport::{endpoint_text, Transport};
use crate::{log, Event};
use sill_protocol::messages::{from_json, to_json, ClientStats, Goodbye, Hello, InputEvent, MacPointer};
use sill_protocol::text::label;
use sill_protocol::wire::{message, message_now, now_seconds, Header, Kind, HEADER_LEN, MAX_CLIENT_PAYLOAD};
use std::collections::{HashMap, VecDeque};
use std::io::{Read, Write};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::mpsc::Sender;
use std::sync::{Arc, Condvar, Mutex};
use std::time::{Duration, Instant};

pub type ClientId = u64;

/// How a session came in.
#[derive(Clone, Debug, PartialEq)]
pub enum Route {
    /// The plain home door (development builds and the CLI without --pairing).
    HomePlain,
    /// The TLS home door, with the peer's key and its paired name (None: an unpaired key while
    /// Require pairing is off).
    HomeTls { fingerprint: [u8; 32], paired_name: Option<String> },
    /// The remote door: a paired key, its name, how it came ("through Tailscale", "by address",
    /// "over the internet"), and whether it counts as away from home (a VPN or the internet;
    /// "by address" is home: AwayPolicy).
    Remote { fingerprint: [u8; 32], name: String, label: String, away: bool },
}

impl Route {
    pub fn is_remote(&self) -> bool {
        matches!(self, Route::Remote { .. })
    }

    pub fn is_away(&self) -> bool {
        matches!(self, Route::Remote { away: true, .. })
    }
}

struct Out {
    data: Arc<Vec<u8>>,
    /// Counts in `inflight` and `pending_bytes` (everything but ticks and kind 26), as Swift's
    /// `send(_:to:)`.
    counted: bool,
    frame: bool,
    /// A remote client's keyframe, tracked until its connection has taken it.
    keyframe_seq: Option<u64>,
}

struct ClientState {
    queue: VecDeque<Out>,
    /// Every counted message not yet handed to the socket (queued or being written).
    inflight: usize,
    inflight_frames: usize,
    /// When a frame was last drained, or queued from none (dead-peer detection).
    oldest_unacked_frame: Option<Instant>,
    needs_keyframe: bool,
    awaiting_first_keyframe: bool,
    closed: bool,
    /// Stats print rate limit and the worst values since the last line.
    last_stats_print: Option<Instant>,
    worst_age: i64,
    worst_rtt: i64,
    /// When a counted message was last queued (a TLS client skips a tick right after one).
    last_sent: Option<Instant>,
    /// The input messages (kind 8) read from it: every kind 26 sent to it carries the count.
    inputs_read: i64,
    /// The last kind 26 sent to it; None also while it drives the pointer.
    last_pointer: Option<MacPointer>,
    /// Bytes handed to it that its socket has not taken yet (counted messages).
    pending_bytes: usize,
    /// Remote clients: the keyframes still being taken (sequence, bytes), oldest first.
    keyframes_in_flight: Vec<(u64, usize)>,
    keyframe_bytes_in_flight: usize,
    keyframe_seq: u64,
    /// Remote clients: the smallest backlog since the keyframes it was taking were all taken.
    backlog_floor: usize,
    /// Remote clients: a frame was dropped for it and a keyframe should be asked for when due.
    keyframe_wanted: bool,
    /// The last header received from it (remote clients: silence eviction).
    last_heard: Instant,
}

pub struct Client {
    pub id: ClientId,
    pub endpoint: String,
    pub route: Route,
    /// The session is TLS.
    pub encrypted: bool,
    pub connected_at: Instant,
    state: Mutex<ClientState>,
    cv: Condvar,
    closer: Box<dyn Fn() + Send + Sync>,
    pub device: Mutex<Option<String>>,
    hello_seen: AtomicBool,
}

impl Client {
    fn enqueue(&self, st: &mut ClientState, data: Arc<Vec<u8>>, counted: bool, frame: bool) {
        self.enqueue_tracked(st, data, counted, frame, false)
    }

    /// `keyframe`: a remote client's keyframe, whose bytes count apart until it is taken.
    fn enqueue_tracked(&self, st: &mut ClientState, data: Arc<Vec<u8>>, counted: bool, frame: bool, keyframe: bool) {
        if st.closed {
            return;
        }
        if counted {
            st.inflight += 1;
            st.pending_bytes += data.len();
            st.last_sent = Some(Instant::now());
        }
        let mut keyframe_seq = None;
        if keyframe {
            st.keyframe_seq += 1;
            keyframe_seq = Some(st.keyframe_seq);
            st.keyframes_in_flight.push((st.keyframe_seq, data.len()));
            st.keyframe_bytes_in_flight += data.len();
        }
        if frame {
            st.inflight_frames += 1;
            if st.oldest_unacked_frame.is_none() {
                st.oldest_unacked_frame = Some(Instant::now());
            }
        }
        st.queue.push_back(Out { data, counted, frame, keyframe_seq });
        // notify_all: goodbye waiters share the condition variable with the writer.
        self.cv.notify_all();
    }

    /// One message to this client (counted).
    pub fn send(&self, data: Arc<Vec<u8>>) {
        let mut st = self.state.lock().unwrap();
        self.enqueue(&mut st, data, true, false);
    }

    pub fn close(&self) {
        let mut st = self.state.lock().unwrap();
        if !st.closed {
            st.closed = true;
            st.queue.clear();
        }
        drop(st);
        self.cv.notify_all();
        (self.closer)();
    }

    /// Closes from a place that already holds this client's state lock.
    fn close_locked(&self, st: &mut ClientState) {
        st.closed = true;
        st.queue.clear();
        self.cv.notify_all();
        (self.closer)();
    }

    pub fn is_closed(&self) -> bool {
        self.state.lock().unwrap().closed
    }

    /// The device's name from its hello or stats, else its endpoint.
    pub fn name(&self) -> String {
        self.device.lock().unwrap().clone().unwrap_or_else(|| self.endpoint.clone())
    }
}

/// A peer that has not drained a single video frame for this long stopped reading.
const DEAD_AFTER: Duration = Duration::from_secs(4);
/// No eviction while the connect burst (catalog + first keyframe) is still draining.
const GRACE_AFTER_CONNECT: Duration = Duration::from_secs(8);
const TICK_INTERVAL: Duration = Duration::from_millis(30);
const INPUT_RECENCY: Duration = Duration::from_secs(3);

pub struct Server {
    clients: Mutex<HashMap<ClientId, Arc<Client>>>,
    next_id: AtomicU64,
    events: Mutex<Sender<Event>>,
    last_parameter_sets: Mutex<Option<Arc<Vec<u8>>>>,
    streaming: AtomicBool,
    last_input_at: Mutex<Option<Instant>>,
    /// A keyframe request is waiting for the coordinator (coalesced).
    keyframe_wanted: AtomicBool,
    /// The stream generation whose frames are current (StreamSink checks it).
    pub generation: AtomicU64,
    /// The host's pointer (kind 26, PointerControl.swift): who moves it, and the source it is
    /// judged against.
    pointer: Mutex<PointerControl>,
    pointer_reader: Mutex<Option<PointerReader>>,
    /// When a keyframe was last asked for on a remote client's behalf, and when the last keyframe
    /// of any kind went out.
    last_remote_keyframe_request: Mutex<Option<Instant>>,
    last_keyframe_at: Mutex<Option<Instant>>,
}

pub type PointerReader = Box<dyn Fn() -> Option<(f64, f64)> + Send + Sync>;

/// Who moves the host's pointer: the host itself (its own mouse, or an app) or the device whose
/// input was read last. A read 0.5 units or more from the last one that counted, outside the
/// 0.25 s that follow Sill's own posts, is the host's.
#[derive(Default)]
struct PointerControl {
    /// None: the host.
    controller: Option<ClientId>,
    sill_until: Option<Instant>,
    last: Option<(f64, f64)>,
    previous: Option<(f64, f64)>,
    previous_at: Option<Instant>,
    /// The streamed source's rectangle; None while nothing streams (nothing is read then).
    rect: Option<crate::platform::Rect>,
}

const POINTER_SETTLE: Duration = Duration::from_millis(250);

impl PointerControl {
    fn read(&mut self, p: (f64, f64), now: Instant) {
        let watched = self.previous_at.map(|t| now.duration_since(t) <= POINTER_SETTLE).unwrap_or(false);
        self.previous = Some(p);
        self.previous_at = Some(now);
        let Some(from) = self.last.filter(|_| watched) else {
            self.last = Some(p);
            return;
        };
        if self.sill_until.map(|t| now < t).unwrap_or(false) {
            self.last = Some(p);
            return;
        }
        if ((p.0 - from.0).powi(2) + (p.1 - from.1).powi(2)).sqrt() < 0.5 {
            return;
        }
        self.last = Some(p);
        self.controller = None;
    }
}

impl Server {
    pub fn new(events: Sender<Event>) -> Arc<Server> {
        let s = Arc::new(Server {
            clients: Mutex::new(HashMap::new()),
            next_id: AtomicU64::new(1),
            events: Mutex::new(events),
            last_parameter_sets: Mutex::new(None),
            streaming: AtomicBool::new(false),
            last_input_at: Mutex::new(None),
            keyframe_wanted: AtomicBool::new(false),
            generation: AtomicU64::new(0),
            pointer: Mutex::new(PointerControl::default()),
            pointer_reader: Mutex::new(None),
            last_remote_keyframe_request: Mutex::new(None),
            last_keyframe_at: Mutex::new(None),
        });
        let sweeper = Arc::downgrade(&s);
        std::thread::Builder::new()
            .name("sill-sweep".into())
            .spawn(move || loop {
                std::thread::sleep(Duration::from_secs(1));
                let Some(s) = sweeper.upgrade() else { return };
                s.sweep();
            })
            .expect("sweep thread");
        let ticker = Arc::downgrade(&s);
        std::thread::Builder::new()
            .name("sill-tick".into())
            .spawn(move || loop {
                std::thread::sleep(TICK_INTERVAL);
                let Some(s) = ticker.upgrade() else { return };
                s.tick();
            })
            .expect("tick thread");
        s
    }

    fn event(&self, e: Event) {
        let _ = self.events.lock().unwrap().send(e);
    }

    pub fn client(&self, id: ClientId) -> Option<Arc<Client>> {
        self.clients.lock().unwrap().get(&id).cloned()
    }

    pub fn client_ids(&self) -> Vec<ClientId> {
        self.clients.lock().unwrap().keys().copied().collect()
    }

    pub fn client_count(&self) -> usize {
        self.clients.lock().unwrap().len()
    }

    fn snapshot(&self) -> Vec<Arc<Client>> {
        self.clients.lock().unwrap().values().cloned().collect()
    }

    /// From now on `transport` gets broadcasts, ticks and the catalog ("Client connected").
    pub fn register(self: &Arc<Server>, mut transport: Box<dyn Transport>, route: Route, hello: Option<Hello>) -> std::io::Result<()> {
        let reader = transport.take_reader()?;
        let writer = transport.take_writer()?;
        let closer = transport.closer()?;
        let endpoint = endpoint_text(&transport.peer());
        let encrypted = transport.encrypted();
        let id = self.next_id.fetch_add(1, Ordering::Relaxed);
        let client = Arc::new(Client {
            id,
            endpoint: endpoint.clone(),
            route,
            encrypted,
            connected_at: Instant::now(),
            state: Mutex::new(ClientState {
                queue: VecDeque::new(),
                inflight: 0,
                inflight_frames: 0,
                oldest_unacked_frame: None,
                needs_keyframe: true,
                awaiting_first_keyframe: true,
                closed: false,
                last_stats_print: None,
                worst_age: -1,
                worst_rtt: -1,
                last_sent: None,
                inputs_read: 0,
                last_pointer: None,
                pending_bytes: 0,
                keyframes_in_flight: Vec::new(),
                keyframe_bytes_in_flight: 0,
                keyframe_seq: 0,
                backlog_floor: 0,
                keyframe_wanted: false,
                last_heard: Instant::now(),
            }),
            cv: Condvar::new(),
            closer,
            device: Mutex::new(None),
            hello_seen: AtomicBool::new(false),
        });
        let count = {
            let mut c = self.clients.lock().unwrap();
            c.insert(id, client.clone());
            c.len()
        };
        stats::stats().clients.store(count, Ordering::Relaxed);
        match &client.route {
            Route::Remote { name, label, .. } => log(&format!("Remote client connected: {name} {label} ({endpoint})")),
            _ => log(&format!("Client connected: {endpoint}")),
        }
        // Writer and reader threads.
        let w = client.clone();
        let srv = Arc::downgrade(self);
        std::thread::Builder::new().name(format!("sill-w{id}")).spawn(move || writer_loop(w, writer, srv))?;
        let r = client.clone();
        let srv = self.clone();
        std::thread::Builder::new().name(format!("sill-r{id}")).spawn(move || srv.reader_loop(r, reader))?;
        self.event(Event::Connected(id));
        if let Some(h) = hello {
            self.took_hello(&client, h);
        }
        Ok(())
    }

    fn unregister(&self, id: ClientId) {
        let (client, count) = {
            let mut c = self.clients.lock().unwrap();
            let client = c.remove(&id);
            (client, c.len())
        };
        let Some(client) = client else { return };
        {
            let mut p = self.pointer.lock().unwrap();
            if p.controller == Some(id) {
                p.controller = None;
            }
        }
        client.close();
        stats::stats().clients.store(count, Ordering::Relaxed);
        log(&format!("Client left: {}", client.endpoint));
        self.event(Event::Left(id));
    }

    fn took_hello(&self, client: &Client, hello: Hello) {
        client.hello_seen.store(true, Ordering::Relaxed);
        let name = label(hello.device.as_deref().unwrap_or(""));
        if !name.is_empty() {
            let mut d = client.device.lock().unwrap();
            if d.is_none() {
                *d = Some(name.clone());
            }
        }
        let v = sill_protocol::text::safe_label(hello.app_version.as_deref().unwrap_or(""), 32);
        let build = sill_protocol::text::safe_label(hello.build.as_deref().unwrap_or(""), 32);
        let mut line = format!("Client hello: {}, ", if name.is_empty() { client.endpoint.clone() } else { name.clone() });
        line += &if v.is_empty() {
            "no version".to_string()
        } else {
            format!("Sill {v}") + &if build.is_empty() { String::new() } else { format!(" ({build})") }
        };
        if let Some(p) = hello.protocol {
            line += &format!(", protocol {p}");
        }
        if !name.is_empty() {
            line += &format!(" ({})", client.endpoint);
        }
        log(&line);
    }

    /// Client → host messages, one at a time.
    fn reader_loop(self: Arc<Server>, client: Arc<Client>, mut r: Box<dyn Read + Send>) {
        let mut head = [0u8; HEADER_LEN];
        loop {
            if r.read_exact(&mut head).is_err() {
                break;
            }
            let Some(h) = Header::parse(&head) else { break };
            client.state.lock().unwrap().last_heard = Instant::now();
            // A header can announce up to 4 GiB: no client message comes near a megabyte.
            if h.payload_len as usize > MAX_CLIENT_PAYLOAD {
                log(&format!(
                    "Closing {}: it announced a {}-byte message (the limit is 1 MB).",
                    client.endpoint, h.payload_len
                ));
                break;
            }
            let mut payload = vec![0u8; h.payload_len as usize];
            if r.read_exact(&mut payload).is_err() {
                break;
            }
            match h.kind {
                Kind::Ping => {
                    // Echoed straight back: the round trip should measure the network alone.
                    client.send(Arc::new(message(Kind::Pong, h.timestamp, false, &payload)));
                }
                Kind::Input => {
                    *self.last_input_at.lock().unwrap() = Some(Instant::now());
                    // This device moves the host's pointer now; the count and the controller change
                    // together, so no kind 26 carries the new count with the old controller.
                    let moves = matches!(
                        from_json::<InputEvent>(&payload),
                        Some(InputEvent::Pointer { .. } | InputEvent::Scroll { .. } | InputEvent::ScrollGesture { .. })
                    );
                    {
                        let mut st = client.state.lock().unwrap();
                        st.inputs_read += 1;
                        st.last_pointer = None;
                        let mut p = self.pointer.lock().unwrap();
                        p.controller = Some(client.id);
                        if moves {
                            p.sill_until = Some(Instant::now() + POINTER_SETTLE);
                        }
                    }
                    self.event(Event::Message(client.id, h.kind, payload));
                }
                Kind::ClientStats => {
                    if let Some(s) = from_json::<ClientStats>(&payload) {
                        self.client_stats(&client, s);
                    }
                }
                Kind::Hello => {
                    if !client.hello_seen.swap(true, Ordering::Relaxed) {
                        if let Some(hello) = from_json::<Hello>(&payload) {
                            self.took_hello(&client, hello);
                        }
                    }
                }
                Kind::Unknown(_) => {}
                kind => self.event(Event::Message(client.id, kind, payload)),
            }
        }
        // EOF or a read error: the client closed (or was killed).
        self.unregister(client.id);
    }

    /// The device's own report, printed every ~2 s with the worst values since the last line.
    fn client_stats(&self, client: &Client, s: ClientStats) {
        let name = label(&s.device);
        *client.device.lock().unwrap() = if name.is_empty() { None } else { Some(name.clone()) };
        let mut st = client.state.lock().unwrap();
        st.worst_age = st.worst_age.max(s.frame_age_max_ms.unwrap_or(-1));
        st.worst_rtt = st.worst_rtt.max(s.rtt_max_ms.unwrap_or(-1));
        let due = st.last_stats_print.map(|t| t.elapsed() >= Duration::from_millis(1500)).unwrap_or(true);
        if due {
            st.last_stats_print = Some(Instant::now());
            let age = median_and_worst(s.frame_age_ms, s.frame_age_max_ms.map(|_| st.worst_age));
            let rtt = median_and_worst(s.rtt_ms, s.rtt_max_ms.map(|_| st.worst_rtt));
            st.worst_age = -1;
            st.worst_rtt = -1;
            drop(st);
            let who = if name.is_empty() { client.endpoint.clone() } else { name };
            log(&format!("client {who}: {} fps, frame age {age}, rtt {rtt}", s.fps));
        }
    }

    /// One message to one client (counted).
    pub fn send(&self, id: ClientId, data: Vec<u8>) {
        if let Some(c) = self.client(id) {
            c.send(Arc::new(data));
        }
    }

    /// One message to every client (counted). Parameter sets are remembered for clients that wait
    /// for a keyframe.
    pub fn broadcast(&self, kind: Kind, data: Vec<u8>) {
        let data = Arc::new(data);
        if kind == Kind::ParameterSets {
            *self.last_parameter_sets.lock().unwrap() = Some(data.clone());
        }
        for c in self.snapshot() {
            c.send(data.clone());
        }
    }

    /// A video frame to every client, by StreamServer's home rule: a client waiting for a keyframe
    /// gets nothing until one comes (and the parameter sets before it); a client with more than two
    /// messages not yet taken by its socket loses this delta and waits for a keyframe, which is
    /// asked for at once.
    pub fn broadcast_frame(&self, data: Vec<u8>, keyframe: bool) {
        let data = Arc::new(data);
        let ps = self.last_parameter_sets.lock().unwrap().clone();
        let mut want_keyframe = false;
        let now = Instant::now();
        if keyframe {
            *self.last_keyframe_at.lock().unwrap() = Some(now);
        }
        let clients = self.snapshot();
        let home_present = clients.iter().any(|c| !c.route.is_remote());
        for c in clients {
            let mut st = c.state.lock().unwrap();
            if st.closed {
                continue;
            }
            if c.route.is_remote() {
                if self.pace_remote(&c, &mut st, &data, keyframe, ps.clone(), home_present) {
                    want_keyframe = true;
                }
                continue;
            }
            if st.needs_keyframe {
                let (true, Some(ps)) = (keyframe, ps.clone()) else {
                    bump("net.waitKey");
                    continue;
                };
                c.enqueue(&mut st, ps, true, false);
                st.needs_keyframe = false;
                st.awaiting_first_keyframe = false;
            } else if st.inflight > 2 && !keyframe {
                // Every later delta references this one, so the client now waits for a keyframe.
                bump("net.dropped");
                st.needs_keyframe = true;
                want_keyframe = true;
                continue;
            }
            if not_draining(&c, &st, now) {
                drop(st);
                c.close();
                continue;
            }
            bump("net.sent");
            c.enqueue(&mut st, data.clone(), true, true);
        }
        if want_keyframe {
            self.want_keyframe();
        }
    }

    /// A remote client's frames (StreamServer.paceRemote, docs/remote-bundle-plan.md §3): what it
    /// has queued is counted in bytes its connection has not taken. Behind keyframes still being
    /// taken, frames go out until more than 512 KB waits beyond them; otherwise a frame is dropped
    /// only when the backlog is over both 256 KB and what the last keyframe left behind plus
    /// 128 KB. A client that lost a frame asks for a keyframe only once at most 16 KB waits (so the
    /// keyframe leads its queue), at most every 2 s for all remote clients (4 s beside a home
    /// client, and 4 s after any keyframe). Returns whether to ask for one now.
    fn pace_remote(&self, c: &Client, st: &mut ClientState, data: &Arc<Vec<u8>>, keyframe: bool, ps: Option<Arc<Vec<u8>>>, home_present: bool) -> bool {
        let now = Instant::now();
        st.backlog_floor = st.backlog_floor.min(st.pending_bytes);
        if st.needs_keyframe {
            if !keyframe {
                bump("net.waitKey");
                if st.keyframe_wanted && st.pending_bytes <= REMOTE_IDLE_BYTES && self.remote_keyframe_due(now, home_present) {
                    *self.last_remote_keyframe_request.lock().unwrap() = Some(now);
                    st.keyframe_wanted = false;
                    return true;
                }
                return false;
            }
            let Some(ps) = ps.filter(|_| st.awaiting_first_keyframe || st.pending_bytes <= REMOTE_BACKLOG_BUDGET) else {
                // Its queue is still full: this keyframe is lost to it too; ask again once drained.
                bump("net.waitKey");
                st.keyframe_wanted = true;
                return false;
            };
            c.enqueue(st, ps, true, false);
            st.needs_keyframe = false;
            st.awaiting_first_keyframe = false;
        } else {
            let too_much = if !st.keyframes_in_flight.is_empty() {
                st.pending_bytes.saturating_sub(st.keyframe_bytes_in_flight) > REMOTE_HOLD_CAP
            } else {
                st.pending_bytes > REMOTE_BACKLOG_BUDGET.max(st.backlog_floor + REMOTE_BACKLOG_SLACK)
            };
            if too_much {
                bump("net.dropped");
                st.needs_keyframe = true;
                st.keyframe_wanted = true;
                return false;
            }
        }
        if not_draining(c, st, now) {
            c.close_locked(st);
            return false;
        }
        bump("net.sent");
        c.enqueue_tracked(st, data.clone(), true, true, keyframe);
        false
    }

    /// Whether a keyframe may be asked for on a remote client's behalf now (remoteKeyframeDue).
    fn remote_keyframe_due(&self, now: Instant, home_present: bool) -> bool {
        let last = *self.last_remote_keyframe_request.lock().unwrap();
        let since = |t: Option<Instant>, d: Duration| t.map(|t| now.duration_since(t) >= d).unwrap_or(true);
        if !home_present {
            return since(last, REMOTE_KEYFRAME_SPACING);
        }
        since(last, REMOTE_KEYFRAME_SPACING_BESIDE_HOME) && since(*self.last_keyframe_at.lock().unwrap(), REMOTE_KEYFRAME_SPACING_BESIDE_HOME)
    }

    /// Once a second: a remote client that has sent nothing for 8 s is gone (it pings every 0.25 s);
    /// one that lost a frame while its window went still asks for its keyframe here.
    fn sweep(&self) {
        let now = Instant::now();
        let clients = self.snapshot();
        let home_present = clients.iter().any(|c| !c.route.is_remote());
        let mut waiting = Vec::new();
        for c in clients.iter().filter(|c| c.route.is_remote()) {
            let st = c.state.lock().unwrap();
            let silent = now.duration_since(st.last_heard);
            if now.duration_since(c.connected_at) >= REMOTE_SILENCE && silent > REMOTE_SILENCE {
                drop(st);
                log(&format!("Client silent for {} s, dropping: {}", silent.as_secs(), c.endpoint));
                c.close();
                continue;
            }
            if st.needs_keyframe && st.keyframe_wanted && !st.awaiting_first_keyframe && st.pending_bytes <= REMOTE_IDLE_BYTES {
                waiting.push(c.clone());
            }
        }
        if !waiting.is_empty() && self.remote_keyframe_due(now, home_present) {
            *self.last_remote_keyframe_request.lock().unwrap() = Some(now);
            for c in &waiting {
                c.state.lock().unwrap().keyframe_wanted = false;
            }
            self.want_keyframe();
        }
    }

    /// The remote door's sessions now.
    pub fn remote_session_count(&self) -> usize {
        self.snapshot().iter().filter(|c| c.route.is_remote()).count()
    }

    /// Asks the coordinator for a keyframe (coalesced until it has asked the stream).
    pub fn want_keyframe(&self) {
        if !self.keyframe_wanted.swap(true, Ordering::AcqRel) {
            self.event(Event::KeyframeNeeded);
        }
    }

    /// The coordinator has passed the request on.
    pub fn keyframe_requested(&self) {
        self.keyframe_wanted.store(false, Ordering::Release);
    }

    /// The source is changing: forget the old parameter sets and make every client wait for the
    /// next keyframe, so nobody decodes frames of the new source with the old format.
    pub fn reset_for_new_stream(&self) {
        *self.last_parameter_sets.lock().unwrap() = None;
        for c in self.snapshot() {
            let mut st = c.state.lock().unwrap();
            st.needs_keyframe = true;
            st.awaiting_first_keyframe = true;
        }
    }

    pub fn set_streaming(&self, on: bool) {
        self.streaming.store(on, Ordering::Relaxed);
    }

    /// An empty kind 13 to every client every 30 ms while a source streams or a client sent input
    /// in the last 3 s: keeps the device's Wi-Fi radio out of power save. Not counted in
    /// `inflight`, so it never makes a link drop frames.
    fn tick(&self) {
        let live = self.streaming.load(Ordering::Relaxed)
            || self.last_input_at.lock().unwrap().map(|t| t.elapsed() < INPUT_RECENCY).unwrap_or(false);
        if !live {
            return;
        }
        let clients = self.snapshot();
        if clients.is_empty() {
            return;
        }
        let data = Arc::new(message_now(Kind::Tick, &[]));
        let reading = self.sample_pointer();
        for c in clients {
            let mut st = c.state.lock().unwrap();
            // The host's pointer, to every device that is not moving it, when its report changed
            // (not counted in `inflight`); a kind 26 stands in for that device's tick.
            if let Some((x, y, inside, controller)) = reading {
                if controller == Some(c.id) {
                    st.last_pointer = None;
                } else {
                    let seen = Some(st.inputs_read);
                    let report = if inside {
                        MacPointer { x: Some(x), y: Some(y), inside: Some(true), seen }
                    } else {
                        MacPointer { x: None, y: None, inside: Some(false), seen }
                    };
                    if st.last_pointer.as_ref() != Some(&report) {
                        let m = Arc::new(message_now(Kind::MacPointer, &to_json(&report)));
                        st.last_pointer = Some(report);
                        c.enqueue(&mut st, m, false, false);
                        bump("ptr.sent");
                        continue;
                    }
                }
            }
            // Over TLS every record costs CPU: skip a tick right after anything else went out
            // (the link is busy anyway, so the device's radio stays awake). The plain door keeps
            // every tick.
            if c.encrypted && st.last_sent.map(|t| t.elapsed() < TICK_INTERVAL).unwrap_or(false) {
                continue;
            }
            c.enqueue(&mut st, data.clone(), false, false);
        }
        bump("net.tick");
    }

    /// Where the host's pointer is (`Platform::pointer_location`), read at each tick while
    /// something streams.
    pub fn set_pointer_reader(&self, read: PointerReader) {
        *self.pointer_reader.lock().unwrap() = Some(read);
    }

    /// The streamed source's rectangle (None: nothing streams, so nothing is read).
    pub fn set_pointer_rect(&self, rect: Option<crate::platform::Rect>) {
        self.pointer.lock().unwrap().rect = rect;
    }

    /// The core is about to post a pointer or scroll event: its motion is not the host's own.
    pub fn sill_moved_pointer(&self) {
        self.pointer.lock().unwrap().sill_until = Some(Instant::now() + POINTER_SETTLE);
    }

    /// One reading: the fractions (4 places), whether it is over the source, and who drives.
    fn sample_pointer(&self) -> Option<(f64, f64, bool, Option<ClientId>)> {
        let rect = self.pointer.lock().unwrap().rect?;
        let p = (self.pointer_reader.lock().unwrap().as_ref()?)()?;
        let mut pc = self.pointer.lock().unwrap();
        pc.read(p, Instant::now());
        if rect.width <= 0.0 || rect.height <= 0.0 || !p.0.is_finite() || !p.1.is_finite() {
            return Some((0.0, 0.0, false, pc.controller));
        }
        let x = (p.0 - rect.x) / rect.width;
        let y = (p.1 - rect.y) / rect.height;
        let inside = (0.0..1.0).contains(&x) && (0.0..1.0).contains(&y);
        Some((MacPointer::rounded(x), MacPointer::rounded(y), inside, pc.controller))
    }

    /// Every client gets `goodbye` (kind 22); returns once each message was written or after
    /// `within`, then closes them all.
    pub fn goodbye_all(&self, goodbye: &Goodbye, within: Duration) {
        let data = Arc::new(message_now(Kind::Goodbye, &sill_protocol::to_json(goodbye)));
        let clients = self.snapshot();
        for c in &clients {
            let mut st = c.state.lock().unwrap();
            // Nothing older matters now: the goodbye goes next.
            st.queue.retain(|o| !o.frame);
            c.enqueue(&mut st, data.clone(), true, false);
        }
        let deadline = Instant::now() + within;
        for c in &clients {
            let mut st = c.state.lock().unwrap();
            while st.inflight > 0 && !st.closed {
                let left = deadline.saturating_duration_since(Instant::now());
                if left.is_zero() {
                    break;
                }
                st = c.cv.wait_timeout(st, left).unwrap().0;
            }
        }
        for c in clients {
            c.close();
        }
    }

    /// One client gets `goodbye`, then is closed within `within`.
    pub fn goodbye(&self, id: ClientId, goodbye: &Goodbye, within: Duration) {
        let Some(c) = self.client(id) else { return };
        c.send(Arc::new(message_now(Kind::Goodbye, &sill_protocol::to_json(goodbye))));
        std::thread::spawn(move || {
            let deadline = Instant::now() + within;
            let mut st = c.state.lock().unwrap();
            while st.inflight > 0 && !st.closed {
                let left = deadline.saturating_duration_since(Instant::now());
                if left.is_zero() {
                    break;
                }
                st = c.cv.wait_timeout(st, left).unwrap().0;
            }
            drop(st);
            c.close();
        });
    }
}

/// A remote client's backlog that never drops a frame.
const REMOTE_BACKLOG_BUDGET: usize = 256 * 1024;
/// Growth over what a keyframe left behind that still counts as noise.
const REMOTE_BACKLOG_SLACK: usize = 128 * 1024;
/// How much may queue behind a keyframe the connection is still taking.
const REMOTE_HOLD_CAP: usize = 512 * 1024;
/// A queue this short holds nothing but control messages: a keyframe asked for now leads it.
const REMOTE_IDLE_BYTES: usize = 16 * 1024;
const REMOTE_KEYFRAME_SPACING: Duration = Duration::from_secs(2);
const REMOTE_KEYFRAME_SPACING_BESIDE_HOME: Duration = Duration::from_secs(4);
const REMOTE_SILENCE: Duration = Duration::from_secs(8);
const REMOTE_DEAD_AFTER: Duration = Duration::from_secs(15);
const REMOTE_GRACE: Duration = Duration::from_secs(15);

/// A peer that has not drained a single video frame for 4 s (a remote one: 15 s) stopped reading;
/// not within 8 s (15 s) of connecting.
fn not_draining(c: &Client, st: &ClientState, now: Instant) -> bool {
    let (dead, grace) = if c.route.is_remote() { (REMOTE_DEAD_AFTER, REMOTE_GRACE) } else { (DEAD_AFTER, GRACE_AFTER_CONNECT) };
    let Some(oldest) = st.oldest_unacked_frame else { return false };
    if now.duration_since(oldest) > dead && now.duration_since(c.connected_at) > grace {
        log(&format!("Client not draining for {} s, dropping: {}", now.duration_since(oldest).as_secs(), c.endpoint));
        return true;
    }
    false
}

/// Takes queued messages and hands them to the socket, one at a time.
fn writer_loop(c: Arc<Client>, mut w: Box<dyn Write + Send>, server: std::sync::Weak<Server>) {
    loop {
        let out = {
            let mut st = c.state.lock().unwrap();
            loop {
                if st.closed {
                    return;
                }
                if let Some(o) = st.queue.pop_front() {
                    break o;
                }
                st = c.cv.wait(st).unwrap();
            }
        };
        let ok = w.write_all(&out.data).and_then(|_| w.flush()).is_ok();
        let mut st = c.state.lock().unwrap();
        if out.counted {
            st.inflight = st.inflight.saturating_sub(1);
            st.pending_bytes = st.pending_bytes.saturating_sub(out.data.len());
        }
        if let Some(seq) = out.keyframe_seq {
            if let Some(i) = st.keyframes_in_flight.iter().position(|(s, _)| *s == seq) {
                let (_, bytes) = st.keyframes_in_flight.remove(i);
                st.keyframe_bytes_in_flight = st.keyframe_bytes_in_flight.saturating_sub(bytes);
                // The last of them taken: what they left behind them.
                if st.keyframes_in_flight.is_empty() {
                    st.backlog_floor = st.pending_bytes;
                }
            }
        }
        if out.frame {
            st.inflight_frames = st.inflight_frames.saturating_sub(1);
            // Progress: a slow but live peer on a saturated link never drains to zero.
            st.oldest_unacked_frame = if st.inflight_frames == 0 { None } else { Some(Instant::now()) };
        }
        c.cv.notify_all();
        if !ok {
            drop(st);
            c.close();
            if let Some(s) = server.upgrade() {
                s.unregister(c.id);
            }
            return;
        }
    }
}

/// "7/80 ms": the last second's median over the worst since the previous line; "–" for a second
/// without a sample; an older client sends no max and gets "7 ms".
fn median_and_worst(median: i64, worst: Option<i64>) -> String {
    match worst {
        None => format!("{median} ms"),
        Some(w) if median < 0 => {
            if w < 0 {
                "–".into()
            } else {
                format!("–/{w} ms")
            }
        }
        Some(w) => format!("{median}/{} ms", w.max(median)),
    }
}

/// The host's timestamp for messages built here.
pub fn stamp() -> f64 {
    now_seconds()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stats_numbers() {
        assert_eq!(median_and_worst(7, None), "7 ms");
        assert_eq!(median_and_worst(7, Some(80)), "7/80 ms");
        assert_eq!(median_and_worst(-1, Some(-1)), "–");
        assert_eq!(median_and_worst(-1, Some(80)), "–/80 ms");
        assert_eq!(median_and_worst(9, Some(3)), "9/9 ms");
    }
}
