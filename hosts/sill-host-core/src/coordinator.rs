//! The host's one serial loop (StreamCoordinator.swift's main actor): it owns the stream, switches
//! sources on a device's pick, places input, applies viewports and settings, follows the catalog,
//! and answers each new device with the catalog. Network and backend threads talk to it through
//! `Event`s; frames never pass through it (the `CoreSink` hands them straight to the server).

use crate::catalog::{window_infos, Catalog};
use crate::config::{accepted, HostConfig};
use crate::platform::{Button, CursorShape, EncodedFrame, Input, Platform, Rect, ScrollPhase as PScrollPhase, Source, Stream, StreamConfig, StreamSink, WindowCommand as PWindowCommand};
use crate::server::{ClientId, Server};
use crate::stats::bump;
use crate::{log, Event};
use sill_protocol::blobs::{cursor_blob, frame_payload, ParameterSets};
use sill_protocol::messages::*;
use sill_protocol::wire::{message, message_now, now_seconds, Kind, PROTOCOL_CURRENT};
use std::collections::{HashMap, HashSet};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{Receiver, RecvTimeoutError, Sender};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

/// What the coordinator needs to know about its host.
pub struct CoordinatorOptions {
    pub mac_name: String,
    /// Random per launch: two lists with the same one come from the same running host.
    pub launch_id: String,
    /// A host with an identity (the TLS door): kind 16 carries `away` and kind 18 (the signed
    /// MacInfo) follows it in every catalog, as SillHost --pairing does.
    pub pairing: Option<Arc<crate::pairing::Pairing>>,
    pub config: HostConfig,
}

#[derive(Clone, Debug)]
struct Running {
    fps: i64,
    bitrate: i64,
    /// It runs the away pair (every connected device was away when it started).
    away: bool,
    /// The window's size when its stream started (a resize restarts it).
    window_size: Option<(u32, u32)>,
    /// The window's app when its stream started: the same ID naming another app's window (X11
    /// reuses IDs) means the streamed window is gone.
    window_app: Option<String>,
    /// The encoded picture, once the first frame said.
    size: Option<(u32, u32)>,
}

#[derive(Default)]
struct Held {
    keys: HashSet<u16>,
    buttons: HashSet<u8>,
}

/// (the target asked, what `resize` said it got, the window's size in `windows()`'s units after).
type Fitted = ((u32, u32), (u32, u32), (u32, u32));

pub struct Coordinator {
    platform: Arc<dyn Platform>,
    server: Arc<Server>,
    catalog: Arc<Catalog>,
    events_tx: Sender<Event>,
    opts: CoordinatorOptions,
    config: HostConfig,
    active: StreamSource,
    stream: Option<Box<dyn Stream>>,
    generation: u64,
    running: Option<Running>,
    viewport: Option<Viewport>,
    client_fps: HashMap<ClientId, i64>,
    published: HashMap<ClientId, HostSettingsState>,
    settings_arrivals: HashMap<ClientId, Vec<Instant>>,
    settings_ignored_line: HashMap<ClientId, Instant>,
    pending_launch: Option<(String, Instant)>,
    held: HashMap<ClientId, Held>,
    last_pointer: Option<(f64, f64)>,
    cursor: Arc<Mutex<Option<Vec<u8>>>>,
    told_unsupported: HashSet<u8>,
    /// Each window fitted to a viewport: the target asked (logical points), what `resize` said it
    /// got (logical points), and its size in `windows()`'s units right after.
    fitted: HashMap<u32, Fitted>,
}

fn button_id(b: Button) -> u8 {
    match b {
        Button::Left => 0,
        Button::Right => 1,
    }
}

impl Coordinator {
    pub fn new(
        platform: Arc<dyn Platform>,
        server: Arc<Server>,
        catalog: Arc<Catalog>,
        events_tx: Sender<Event>,
        opts: CoordinatorOptions,
    ) -> Coordinator {
        let config = opts.config.clone().validated();
        Coordinator {
            platform,
            server,
            catalog,
            events_tx,
            opts,
            config,
            active: StreamSource::None,
            stream: None,
            generation: 0,
            running: None,
            viewport: None,
            client_fps: HashMap::new(),
            published: HashMap::new(),
            settings_arrivals: HashMap::new(),
            settings_ignored_line: HashMap::new(),
            pending_launch: None,
            held: HashMap::new(),
            last_pointer: None,
            cursor: Arc::new(Mutex::new(None)),
            told_unsupported: HashSet::new(),
            fitted: HashMap::new(),
        }
    }

    /// Runs until `Event::Shutdown`. Returns once every device was told goodbye.
    pub fn run(mut self, rx: Receiver<Event>) {
        loop {
            let e = match rx.recv_timeout(Duration::from_millis(500)) {
                Ok(e) => e,
                Err(RecvTimeoutError::Timeout) => {
                    self.housekeeping();
                    continue;
                }
                Err(RecvTimeoutError::Disconnected) => break,
            };
            match e {
                Event::Connected(id) => self.connected(id),
                Event::Left(id) => self.left(id),
                Event::Message(id, kind, payload) => self.message(id, kind, &payload),
                Event::WindowsChanged(list) => self.windows_changed(list, None),
                Event::KeyframeNeeded => {
                    self.server.keyframe_requested();
                    if let Some(s) = &self.stream {
                        s.request_keyframe();
                    }
                }
                Event::StreamEnded(generation, reason) => {
                    if generation == self.generation && self.stream.is_some() {
                        log(&format!("Stream ended: {reason}"));
                        self.select(StreamSource::None, false);
                    }
                }
                Event::FrameSize(generation, w, h) => {
                    if generation == self.generation {
                        if let Some(r) = &mut self.running {
                            if r.size != Some((w, h)) {
                                r.size = Some((w, h));
                                log(&format!("Encoding {w}×{h}"));
                                self.publish_settings();
                            }
                        }
                    }
                }
                Event::Shutdown(done) => {
                    self.stop_stream();
                    for id in self.held.keys().copied().collect::<Vec<_>>() {
                        self.release_held(id);
                    }
                    self.platform.release_all_input();
                    self.server.goodbye_all(&Goodbye::reason(Goodbye::QUIT), Duration::from_millis(500));
                    let _ = done.send(());
                    break;
                }
            }
        }
    }

    fn housekeeping(&mut self) {
        if let Some((_, at)) = &self.pending_launch {
            if at.elapsed() > Duration::from_secs(30) {
                self.pending_launch = None;
            }
        }
    }

    // MARK: Devices

    fn connected(&mut self, id: ClientId) {
        let Some(client) = self.server.client(id) else { return };
        if self.catalog.refresh() {
            // The list changed: the devices already here hear it as from a poll; this one gets it
            // with its catalog below.
            let list = self.catalog.windows();
            self.windows_changed(list, Some(id));
        }
        let (w, i, a) = self.catalog.counts();
        log(&format!("Catalog → {}: {w} windows, {i} icons, {a} apps", client.endpoint));
        self.server.send(id, self.list_message());
        let state = self.settings_state(id, None);
        self.server.send(id, message_now(Kind::HostSettings, &to_json(&state)));
        self.published.insert(id, state);
        if let Some(info) = self.opts.pairing.as_ref().and_then(|p| p.signed_mac_info()) {
            self.server.send(id, message_now(Kind::MacInfo, &info));
        }
        for m in self.catalog.connect_messages() {
            self.server.send(id, m);
        }
        if let Some(c) = self.cursor.lock().unwrap().clone() {
            self.server.send(id, message_now(Kind::CursorShape, &c));
        }
        // Fresh thumbnails now rather than at the next poll.
        let catalog = self.catalog.clone();
        std::thread::spawn(move || catalog.refresh_images(true));
        if let Some(s) = &self.stream {
            s.request_keyframe();
        }
        self.follow_away();
        self.publish_settings();
    }

    fn left(&mut self, id: ClientId) {
        self.client_fps.remove(&id);
        self.published.remove(&id);
        self.settings_arrivals.remove(&id);
        self.settings_ignored_line.remove(&id);
        self.release_held(id);
        if self.server.client_count() == 0 {
            // Nobody is watching: stop capturing and encoding. The next device picks afresh.
            self.viewport = None;
            self.client_fps.clear();
            if self.active != StreamSource::None {
                self.select(StreamSource::None, false);
            }
        } else if let Some(r) = &self.running {
            if self.effective_fps() != r.fps || r.away != self.away_wanted() {
                // A 120 Hz device left a 60 Hz one behind (come down to its rate), or the last
                // device at home left devices away behind (the away quality).
                self.follow_away();
                if self.running.as_ref().map(|r| r.fps != self.effective_fps()).unwrap_or(false) {
                    self.select(self.active, false);
                }
            }
            self.publish_settings();
        }
    }

    fn who(&self, id: ClientId) -> String {
        self.server.client(id).map(|c| c.name()).unwrap_or_else(|| format!("client {id}"))
    }

    fn message(&mut self, id: ClientId, kind: Kind, payload: &[u8]) {
        match kind {
            Kind::SelectSource => {
                if let Some(source) = from_json::<StreamSource>(payload) {
                    // A pick from the device's switcher.
                    self.select(source, true);
                }
            }
            Kind::LaunchApp => {
                let Some(req) = from_json::<LaunchApp>(payload) else { return };
                match self.platform.launch(&req.bundle_id) {
                    Ok(()) => {
                        log(&format!("Launching {} for {}", req.bundle_id, self.who(id)));
                        self.pending_launch = Some((req.bundle_id, Instant::now()));
                    }
                    Err(e) => log(&format!("Launch failed: {e}")),
                }
            }
            Kind::Input => {
                if let Some(e) = from_json::<InputEvent>(payload) {
                    self.input(id, e);
                }
            }
            Kind::Viewport => {
                if let Some(v) = from_json::<Viewport>(payload) {
                    self.viewport_changed(id, v);
                }
            }
            Kind::WindowCommand => {
                let Some(cmd) = from_json::<sill_protocol::messages::WindowCommand>(payload) else { return };
                let c = match cmd.action.as_str() {
                    "close" => PWindowCommand::Close,
                    "minimize" => PWindowCommand::Minimize,
                    "fullScreen" => PWindowCommand::FullScreen,
                    _ => return,
                };
                self.platform.window_command(cmd.id, c);
                log(&format!("Window {} {}: done", cmd.id, cmd.action));
                if self.catalog.refresh() {
                    let list = self.catalog.windows();
                    self.windows_changed(list, None);
                }
            }
            Kind::ChangeSettings => self.change_settings(id, payload),
            Kind::PairingWanted => {}
            Kind::Gesture | Kind::FetchMenu | Kind::PressMenuItem | Kind::MacPointer => {
                if self.told_unsupported.insert(kind.as_u8()) {
                    log(&format!("Kind {} from {} ignored: this host does not offer it.", kind.as_u8(), self.who(id)));
                }
            }
            _ => {}
        }
    }

    // MARK: The catalog

    fn list_message(&self) -> Vec<u8> {
        let list = WindowList {
            mac_name: self.opts.mac_name.clone(),
            windows: window_infos(&self.catalog.windows()),
            active: self.active,
            launch_id: Some(self.opts.launch_id.clone()),
            // SillHost (no bundle) sends no host version either; devices then never tell the
            // person to update this host by version.
            host_version: None,
            protocol: Some(PROTOCOL_CURRENT),
            // No trackpad gestures (kind 28): devices send none.
            gestures: None,
        };
        message_now(Kind::WindowList, &to_json(&list))
    }

    fn broadcast_list(&self) {
        self.server.broadcast(Kind::WindowList, self.list_message());
    }

    /// The catalog changed: a launched app's first window is picked, a closed window stops its
    /// stream, a resized one restarts it, and every device gets the new list (but `except`, a
    /// device whose catalog is about to go out).
    fn windows_changed(&mut self, list: Vec<crate::platform::Window>, except: Option<ClientId>) {
        self.fitted.retain(|id, _| list.iter().any(|w| w.id == *id));
        if let Some((app, _)) = &self.pending_launch {
            if let Some(w) = list.iter().find(|w| &w.app_id == app) {
                let id = w.id;
                self.pending_launch = None;
                self.select(StreamSource::Window(id), true); // launched from the device to use it: a pick
                return;
            }
        }
        if let StreamSource::Window(id) = self.active {
            let same_app = |w: &&crate::platform::Window| {
                self.running.as_ref().and_then(|r| r.window_app.as_ref()).map(|a| *a == w.app_id).unwrap_or(true)
            };
            match list.iter().find(|w| w.id == id).filter(same_app) {
                None => {
                    log(&format!("Window {id} is gone."));
                    self.select(StreamSource::None, false);
                    return;
                }
                Some(w) => {
                    if let Some(r) = &self.running {
                        if r.window_size.is_some() && r.window_size != Some((w.width, w.height)) {
                            // The encoder is fixed to one size: a resized window means a fresh stream.
                            self.select(self.active, false);
                            return;
                        }
                    }
                }
            }
        }
        self.server.set_pointer_rect(self.stream.as_ref().and_then(|s| s.source_rect()));
        let m = self.list_message();
        for c in self.server.client_ids() {
            if Some(c) != except {
                self.server.send(c, m.clone());
            }
        }
    }

    // MARK: Streams

    /// Whether a device's connection counts as away from home (the remote door, from a VPN or the
    /// internet: AwayPolicy).
    fn is_away(&self, id: ClientId) -> bool {
        self.server.client(id).map(|c| c.route.is_away()).unwrap_or(false)
    }

    /// The away pair is the target while at least one device is connected and every one is away.
    fn away_wanted(&self) -> bool {
        let ids = self.server.client_ids();
        !ids.is_empty() && ids.iter().all(|id| self.is_away(*id))
    }

    /// Home or away changed (a device joined or left): the stream takes the other pair.
    fn follow_away(&mut self) {
        let wanted = self.away_wanted();
        let Some(r) = &self.running else { return };
        if r.away != wanted && self.active != StreamSource::None {
            let (b, s) = self.config.effective(wanted);
            log(&format!(
                "{}: streaming at {} · {} ({} Mbps per 60 fps).",
                if wanted { "Away from home: every connected device is away" } else { "Home quality again: a device connected at home" },
                sill_protocol::messages::settings_choices::quality_name(b),
                if s >= 1.5 { "Retina" } else { "Standard" },
                b / 1_000_000
            ));
            self.select(self.active, false);
        }
    }

    fn effective_fps(&self) -> i64 {
        let wanted = self.client_fps.values().copied().max().unwrap_or(60).max(24);
        wanted.min(self.config.max_fps)
    }

    fn stop_stream(&mut self) {
        // Frames still in flight from the old stream are dropped by their generation.
        self.generation += 1;
        self.server.generation.store(self.generation, Ordering::Release);
        self.server.set_streaming(false);
        self.server.set_pointer_rect(None);
        self.catalog.set_active(None);
        if let Some(s) = self.stream.take() {
            s.stop();
        }
        self.running = None;
    }

    /// Streams `source` in place of whatever streams now; also how the host restarts the current
    /// source (a rate, a size or a settings change). `bring_forward`: a pick from a device, which
    /// raises a picked window (regular mode on the Mac).
    fn select(&mut self, source: StreamSource, bring_forward: bool) {
        self.stop_stream();
        self.server.reset_for_new_stream();
        self.active = StreamSource::None;
        let mut window_app = None;
        let (platform_source, describe, window_size) = match source {
            StreamSource::None => {
                self.broadcast_list();
                self.publish_settings();
                return;
            }
            StreamSource::Desktop => (Source::Desktop, "the whole desktop".to_string(), None),
            StreamSource::Window(id) => {
                let mut w = self.catalog.window(id);
                if w.is_none() && self.catalog.refresh() {
                    w = self.catalog.window(id);
                }
                let Some(w) = w else {
                    log(&format!("Window {id} is not on screen."));
                    self.broadcast_list();
                    self.publish_settings();
                    return;
                };
                log(&format!("Selecting window {} {} — {} {}×{}", w.id, w.app_name, w.title, w.width, w.height));
                if bring_forward {
                    self.platform.raise(id);
                }
                let mut size = (w.width, w.height);
                if let Some(actual) = self.fit_to_viewport(&w) {
                    size = actual;
                    // The catalog's copy has the old size: read it again now.
                    self.catalog.refresh();
                    if let Some(fresh) = self.catalog.window(id) {
                        size = (fresh.width, fresh.height);
                    }
                }
                window_app = Some(w.app_id.clone());
                (Source::Window(id), format!("{} — {}", w.app_name, w.title), Some(size))
            }
        };
        let fps = self.effective_fps();
        let away = self.away_wanted();
        let (per60, capture_scale) = self.config.effective(away);
        let bitrate = per60 * fps / 60;
        let config = StreamConfig {
            source: platform_source,
            fps: fps as u32,
            bitrate: bitrate.clamp(0, u32::MAX as i64) as u32,
            scale: if capture_scale >= 1.5 { 1.0 } else { 0.5 },
            prioritize_speed: self.config.prioritize_speed,
        };
        let sink = Arc::new(CoreSink {
            generation: self.generation,
            server: self.server.clone(),
            events: Mutex::new(self.events_tx.clone()),
            cursor: self.cursor.clone(),
            size: Mutex::new(None),
            ended: AtomicBool::new(false),
        });
        match self.platform.start_stream(config, sink) {
            Ok(stream) => {
                self.stream = Some(stream);
                self.active = source;
                self.catalog.set_active(if let StreamSource::Window(id) = source { Some(id) } else { None });
                self.running = Some(Running { fps, bitrate, away, window_size, window_app, size: None });
                self.server.set_streaming(true);
                self.server.set_pointer_rect(self.stream.as_ref().and_then(|s| s.source_rect()));
                log(&format!(
                    "Streaming {describe} at {} scale, {fps} fps, {} Mbps",
                    if capture_scale >= 1.5 { "full" } else { "half" },
                    bitrate / 1_000_000
                ));
            }
            Err(e) => {
                log(&format!("Could not start streaming {describe}: {e}"));
            }
        }
        self.broadcast_list();
        self.publish_settings();
    }

    // MARK: Viewports

    fn viewport_changed(&mut self, id: ClientId, v: Viewport) {
        self.client_fps.insert(id, v.fps.unwrap_or(60));
        self.viewport = Some(v);
        if self.active == StreamSource::None {
            return;
        }
        // A different rate (a ProMotion device joined, Low Power Mode toggled) needs a new stream.
        if let Some(r) = &self.running {
            if self.effective_fps() != r.fps {
                self.select(self.active, false);
                return;
            }
        }
        if let StreamSource::Window(wid) = self.active {
            if let Some(w) = self.catalog.window(wid) {
                if self.fit_to_viewport(&w).is_some() && self.catalog.refresh() {
                    let list = self.catalog.windows();
                    self.windows_changed(list, None);
                }
            }
        }
    }

    /// Resizes a streamed window to the device's panel at its text scale (`Viewport.scale`), if one
    /// is set and the window is not already there: panel ÷ scale, in logical points. Returns the
    /// size it took, or None when nothing changed.
    ///
    /// `resize` takes and returns logical points, while `Window.width/height` are the backend's
    /// `Rect` units (physical pixels on a HiDPI Windows desktop), so the two are never compared
    /// beyond the ±2 shortcut: a window already fitted to this target (whatever it took) is not
    /// asked again, and nothing is restarted for a size the app refused (the same answer twice).
    fn fit_to_viewport(&mut self, w: &crate::platform::Window) -> Option<(u32, u32)> {
        let v = self.viewport.as_ref()?;
        let scale = v.scale.filter(|s| *s > 0.0)?;
        if v.width <= 0.0 || v.height <= 0.0 {
            return None;
        }
        let (pw, ph) = (v.width, v.height);
        let tw = (v.width / scale).round().max(1.0) as u32;
        let th = (v.height / scale).round().max(1.0) as u32;
        if (w.width as i64 - tw as i64).abs() <= 2 && (w.height as i64 - th as i64).abs() <= 2 {
            return None;
        }
        let last = self.fitted.get(&w.id).copied();
        if let Some((target, _, size)) = last {
            if target == (tw, th) && size == (w.width, w.height) {
                return None; // fitted to this target already, and nothing moved it since
            }
        }
        let actual = self.platform.resize(w.id, tw, th)?;
        let refused = last.map(|(_, got, _)| got == actual).unwrap_or(false) && last.map(|l| l.2 == (w.width, w.height)).unwrap_or(false);
        // The window's size as `windows()` will report it, once the catalog reads it again.
        let after = self.platform.windows().into_iter().find(|x| x.id == w.id).map(|x| (x.width, x.height)).unwrap_or((w.width, w.height));
        self.fitted.insert(w.id, ((tw, th), actual, after));
        if refused {
            return None; // asked again for a size the app already refused
        }
        bump("win.resized");
        log(&format!(
            "Resized {} to {}×{} (asked {tw}×{th} for a {}×{} panel at {scale}×)",
            w.app_name, actual.0, actual.1, pw as i64, ph as i64
        ));
        Some(actual)
    }

    // MARK: Input

    /// A device's input, placed on the source: positions are fractions of the streamed frame,
    /// turned into the source rectangle's coordinates. With nothing streaming it has nowhere to
    /// land; only the up of a key or a button this device holds down still goes, so nothing stays
    /// pressed.
    fn input(&mut self, id: ClientId, e: InputEvent) {
        let rect = self.stream.as_ref().and_then(|s| s.source_rect());
        let place = |r: &Rect, x: f64, y: f64| (r.x + x * r.width, r.y + y * r.height);
        let held = self.held.entry(id).or_default();
        let fallback = self.last_pointer.or_else(|| self.platform.pointer_location()).unwrap_or((0.0, 0.0));
        let input = match (e, rect) {
            (InputEvent::Pointer { action, x, y }, r) => {
                let (px, py) = match &r {
                    Some(r) => place(r, x, y),
                    None => fallback,
                };
                let up = |b: Button| Input::ButtonUp { button: b, x: px, y: py };
                match (action, r.is_some()) {
                    (PointerAction::Move, true) => Input::Move { x: px, y: py },
                    (PointerAction::LeftDown, true) => {
                        held.buttons.insert(button_id(Button::Left));
                        Input::ButtonDown { button: Button::Left, x: px, y: py }
                    }
                    (PointerAction::RightDown, true) => {
                        held.buttons.insert(button_id(Button::Right));
                        Input::ButtonDown { button: Button::Right, x: px, y: py }
                    }
                    (PointerAction::LeftUp, _) if held.buttons.remove(&button_id(Button::Left)) || r.is_some() => up(Button::Left),
                    (PointerAction::RightUp, _) if held.buttons.remove(&button_id(Button::Right)) || r.is_some() => up(Button::Right),
                    _ => return,
                }
            }
            (InputEvent::Key { hid_usage, down, modifiers }, r) => {
                if down {
                    if r.is_none() {
                        return;
                    }
                    held.keys.insert(hid_usage);
                } else if !held.keys.remove(&hid_usage) && r.is_none() {
                    return;
                }
                Input::Key { hid_usage, down, modifiers }
            }
            (_, None) => return,
            (InputEvent::Scroll { x, y, dx, dy }, Some(r)) => {
                let (px, py) = place(&r, x, y);
                Input::Scroll { x: px, y: py, dx: dx * r.width, dy: dy * r.height }
            }
            (InputEvent::ScrollGesture { phase, x, y }, Some(r)) => {
                let (px, py) = place(&r, x, y);
                let phase = match phase {
                    ScrollPhase::Began => PScrollPhase::Began,
                    ScrollPhase::Ended => PScrollPhase::Ended,
                    ScrollPhase::MomentumBegan => PScrollPhase::MomentumBegan,
                    ScrollPhase::MomentumEnded => PScrollPhase::MomentumEnded,
                };
                Input::ScrollPhase { phase, x: px, y: py }
            }
            (InputEvent::Text(t), Some(_)) => Input::Text(t),
        };
        match &input {
            Input::Move { x, y } | Input::ButtonDown { x, y, .. } | Input::ButtonUp { x, y, .. } => {
                self.last_pointer = Some((*x, *y));
                self.server.sill_moved_pointer();
            }
            Input::Scroll { .. } | Input::ScrollPhase { .. } => self.server.sill_moved_pointer(),
            _ => {}
        }
        // The pointer is judged against the source as it is now (a window may have moved).
        self.server.set_pointer_rect(rect);
        bump("in.events");
        self.platform.inject(input);
    }

    /// A device left: let go of every key and button it held, so nothing stays pressed.
    fn release_held(&mut self, id: ClientId) {
        let Some(h) = self.held.remove(&id) else { return };
        let (x, y) = self.last_pointer.or_else(|| self.platform.pointer_location()).unwrap_or((0.0, 0.0));
        for k in h.keys {
            self.platform.inject(Input::Key { hid_usage: k, down: false, modifiers: 0 });
        }
        for b in h.buttons {
            let button = if b == 0 { Button::Left } else { Button::Right };
            self.platform.inject(Input::ButtonUp { button, x, y });
        }
    }

    // MARK: Settings (kinds 16 and 17)

    /// Connection `id`'s state: the pair its controls set (the away pair for a device away), and,
    /// from a host with an identity, `away` (both pairs, whether this connection is away, whether
    /// the away pair is the target).
    fn settings_state(&self, id: ClientId, answering: Option<i64>) -> HostSettingsState {
        let this_away = self.is_away(id);
        HostSettingsState {
            settings: self.config.stream_settings_for(this_away),
            persistent: false,
            virtual_display_available: false,
            virtual_display_note: Some("This host has no virtual display.".into()),
            software_encoder: false,
            stream: self.running.as_ref().and_then(|r| {
                r.size.map(|(w, h)| RunningStream {
                    width: w as i64,
                    height: h as i64,
                    fps: r.fps,
                    mbps: r.bitrate / 1_000_000,
                    on_virtual_display: false,
                })
            }),
            answering,
            away: self.opts.pairing.is_some().then(|| self.config.away_quality(this_away, self.away_wanted())),
            link: None,
        }
    }

    /// To every device its state, when it differs from the last one it was sent.
    fn publish_settings(&mut self) {
        for id in self.server.client_ids() {
            let state = self.settings_state(id, None);
            if self.published.get(&id) == Some(&state) {
                continue;
            }
            // A device whose catalog has not gone out yet gets its state with it.
            if !self.published.contains_key(&id) {
                continue;
            }
            self.published.insert(id, state.clone());
            self.server.send(id, message_now(Kind::HostSettings, &to_json(&state)));
        }
    }

    fn change_settings(&mut self, id: ClientId, payload: &[u8]) {
        // Malformed JSON has no token to answer, so it gets nothing.
        let Some(change) = from_json::<HostSettingsChange>(payload) else { return };
        let who = self.who(id);
        let now = Instant::now();
        let recent = self.settings_arrivals.entry(id).or_default();
        recent.retain(|t| now.duration_since(*t) < Duration::from_secs(1));
        if recent.len() >= 4 {
            let due = self.settings_ignored_line.get(&id).map(|t| now.duration_since(*t) >= Duration::from_secs(1)).unwrap_or(true);
            if due {
                self.settings_ignored_line.insert(id, now);
                log(&format!("Settings from {who} ignored: more than 4 changes a second."));
            }
            let answer = self.settings_state(id, change.token);
            self.server.send(id, message_now(Kind::HostSettings, &to_json(&answer)));
            return;
        }
        recent.push(now);
        let (ok, refused) = accepted(&change);
        if !refused.is_empty() {
            log(&format!("Settings from {who} refused: {}", refused.join(", ")));
        }
        if !ok.is_empty() {
            let before = self.config.clone();
            // A device away from home sets the away quality, never the home one.
            let after = if self.is_away(id) { before.applying_away(&ok) } else { before.applying(&ok) }.validated();
            if after != before {
                log(&format!("Settings from {who}: {}", before.changes(&after)));
                self.config = after.clone();
                let fps_before = self.running.as_ref().map(|r| r.fps);
                let away = self.away_wanted();
                let restart = before.effective(away) != after.effective(away)
                    || before.prioritize_speed != after.prioritize_speed
                    || fps_before.map(|f| f != self.effective_fps()).unwrap_or(false);
                if restart && self.active != StreamSource::None {
                    self.select(self.active, false);
                }
                self.publish_settings();
            }
        }
        // Exactly one answer, to this device alone: the settings as they now stand.
        let answer = self.settings_state(id, change.token);
        self.server.send(id, message_now(Kind::HostSettings, &to_json(&answer)));
    }
}

/// Where a running stream delivers: straight to the server, never through the coordinator.
struct CoreSink {
    generation: u64,
    server: Arc<Server>,
    events: Mutex<Sender<Event>>,
    cursor: Arc<Mutex<Option<Vec<u8>>>>,
    size: Mutex<Option<(u32, u32)>>,
    ended: AtomicBool,
}

impl CoreSink {
    fn current(&self) -> bool {
        self.server.generation.load(Ordering::Acquire) == self.generation
    }
}

impl StreamSink for CoreSink {
    fn frame(&self, frame: EncodedFrame) {
        if !self.current() {
            return;
        }
        {
            let mut s = self.size.lock().unwrap();
            if *s != Some((frame.width, frame.height)) {
                *s = Some((frame.width, frame.height));
                let _ = self.events.lock().unwrap().send(Event::FrameSize(self.generation, frame.width, frame.height));
            }
        }
        let now = now_seconds();
        if let Some(ps) = frame.parameter_sets {
            let payload = ParameterSets::new(ps).encode();
            self.server.broadcast(Kind::ParameterSets, message(Kind::ParameterSets, now, true, &payload));
        }
        bump("enc.out");
        let payload = frame_payload(&frame.nals);
        self.server.broadcast_frame(message(Kind::Frame, now, frame.keyframe, &payload), frame.keyframe);
    }

    fn cursor(&self, shape: CursorShape) {
        if !self.current() {
            return;
        }
        let blob = cursor_blob::encode(shape.hotspot_x, shape.hotspot_y, shape.width, shape.height, &shape.png);
        *self.cursor.lock().unwrap() = Some(blob.clone());
        bump("cursor.shape");
        self.server.broadcast(Kind::CursorShape, message_now(Kind::CursorShape, &blob));
    }

    fn ended(&self, reason: String) {
        if !self.ended.swap(true, Ordering::AcqRel) {
            let _ = self.events.lock().unwrap().send(Event::StreamEnded(self.generation, reason));
        }
    }
}
