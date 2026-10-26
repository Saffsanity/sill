//! The window switcher's catalog (WindowCatalog.swift): the platform's windows in a stable order
//! (first seen first), polled every 2 s while a device is connected; their thumbnails (kind 3,
//! refreshed each poll, sent when they changed); app icons (kind 4, once per app); the installed
//! apps (kind 5, read once in the background).

use crate::platform::{App, Platform, Window};
use crate::server::Server;
use crate::stats;
use crate::{log, Event};
use sill_protocol::blobs::image_blob;
use sill_protocol::messages::{to_json, AppInfo, WindowInfo};
use sill_protocol::wire::{message_now, Kind};
use std::collections::hash_map::DefaultHasher;
use std::collections::{HashMap, HashSet};
use std::hash::{Hash, Hasher};
use std::sync::atomic::Ordering;
use std::sync::mpsc::Sender;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

#[derive(Default)]
struct State {
    /// Window IDs in the order first seen.
    order: Vec<u32>,
    windows: HashMap<u32, Window>,
    thumbs: HashMap<u32, (u64, Vec<u8>)>,
    icons: HashMap<String, Vec<u8>>,
    icons_tried: HashSet<String>,
    apps: Option<Vec<App>>,
    /// When each window's thumbnail was last taken, and what the window was then.
    stamps: HashMap<u32, (Window, Instant)>,
    active: Option<u32>,
}

/// A window whose title and size have not changed is thumbnailed at most this often.
const STATIC_THUMBNAIL_INTERVAL: Duration = Duration::from_secs(6);

pub struct Catalog {
    platform: Arc<dyn Platform>,
    server: Arc<Server>,
    events: Mutex<Sender<Event>>,
    state: Mutex<State>,
}

pub const POLL_INTERVAL: Duration = Duration::from_secs(2);

impl Catalog {
    pub fn new(platform: Arc<dyn Platform>, server: Arc<Server>, events: Sender<Event>) -> Arc<Catalog> {
        Arc::new(Catalog { platform, server, events: Mutex::new(events), state: Mutex::new(State::default()) })
    }

    /// Starts the poller and the installed-apps read.
    pub fn start(self: &Arc<Catalog>) {
        let me = self.clone();
        std::thread::Builder::new()
            .name("sill-apps".into())
            .spawn(move || {
                let t = Instant::now();
                let mut apps = me.platform.apps();
                apps.sort_by_key(|a| a.name.to_lowercase());
                log(&format!("installed apps: {} in {} ms", apps.len(), t.elapsed().as_millis()));
                me.state.lock().unwrap().apps = Some(apps.clone());
                me.server.broadcast(Kind::AppList, message_now(Kind::AppList, &to_json(&app_infos(&apps))));
            })
            .expect("apps thread");
        let me = self.clone();
        std::thread::Builder::new()
            .name("sill-catalog".into())
            .spawn(move || loop {
                std::thread::sleep(POLL_INTERVAL);
                if me.server.client_count() == 0 {
                    continue;
                }
                if me.refresh() {
                    let list = me.windows();
                    let _ = me.events.lock().unwrap().send(Event::WindowsChanged(list));
                }
                me.refresh_images(true);
            })
            .expect("catalog thread");
    }

    /// Reads the platform's windows now; true when the list changed (windows, titles or sizes).
    pub fn refresh(&self) -> bool {
        let fresh = self.platform.windows();
        let mut st = self.state.lock().unwrap();
        let ids: HashSet<u32> = fresh.iter().map(|w| w.id).collect();
        let before: Vec<Window> = st.order.iter().filter_map(|id| st.windows.get(id).cloned()).collect();
        // An ID that now names another app's window (X11 reuses a window ID right after a client
        // exits) is a new window: it loses the old one's place, thumbnail and stamp.
        let reused: HashSet<u32> =
            fresh.iter().filter(|w| st.windows.get(&w.id).map(|old| old.app_id != w.app_id).unwrap_or(false)).map(|w| w.id).collect();
        st.order.retain(|id| ids.contains(id) && !reused.contains(id));
        for w in &fresh {
            if !st.order.contains(&w.id) {
                st.order.push(w.id);
            }
        }
        st.windows = fresh.into_iter().map(|w| (w.id, w)).collect();
        // Per-window state goes with its window (icons are per app and stay).
        st.thumbs.retain(|id, _| ids.contains(id) && !reused.contains(id));
        st.stamps.retain(|id, _| ids.contains(id) && !reused.contains(id));
        let after: Vec<Window> = st.order.iter().filter_map(|id| st.windows.get(id).cloned()).collect();
        stats::stats().windows.store(after.len(), Ordering::Relaxed);
        before != after
    }

    /// The windows in the catalog's order.
    pub fn windows(&self) -> Vec<Window> {
        let st = self.state.lock().unwrap();
        st.order.iter().filter_map(|id| st.windows.get(id).cloned()).collect()
    }

    pub fn window(&self, id: u32) -> Option<Window> {
        self.state.lock().unwrap().windows.get(&id).cloned()
    }

    /// New apps' icons (broadcast once each) and the windows' thumbnails (broadcast when they
    /// changed, or all of them with `only_changed` false).
    pub fn refresh_images(&self, only_changed: bool) {
        let windows = self.windows();
        let wanted: Vec<String> = {
            let mut st = self.state.lock().unwrap();
            let mut v = Vec::new();
            for w in &windows {
                if !w.app_id.is_empty() && st.icons_tried.insert(w.app_id.clone()) {
                    v.push(w.app_id.clone());
                }
            }
            v
        };
        for app in wanted {
            if let Some(png) = self.platform.icon(&app) {
                self.server.broadcast(Kind::AppIcon, message_now(Kind::AppIcon, &image_blob::encode_icon(&app, &png)));
                self.state.lock().unwrap().icons.insert(app, png);
            }
        }
        for w in &windows {
            // WindowCatalog's cadence: every pass for the streamed window and for one whose title or
            // size changed, every 6 s for the rest. Stamped before the capture, so one that fails
            // backs off too.
            {
                let mut st = self.state.lock().unwrap();
                let due = match st.stamps.get(&w.id) {
                    Some((seen, at)) => seen != w || st.active == Some(w.id) || at.elapsed() >= STATIC_THUMBNAIL_INTERVAL,
                    None => true,
                };
                if !due && only_changed {
                    continue;
                }
                st.stamps.insert(w.id, (w.clone(), Instant::now()));
            }
            let Some(jpeg) = self.platform.thumbnail(w.id) else { continue };
            let mut h = DefaultHasher::new();
            jpeg.hash(&mut h);
            let hash = h.finish();
            let changed = {
                let mut st = self.state.lock().unwrap();
                let changed = st.thumbs.get(&w.id).map(|(old, _)| *old != hash).unwrap_or(true);
                st.thumbs.insert(w.id, (hash, jpeg.clone()));
                changed
            };
            if changed || !only_changed {
                self.server
                    .broadcast(Kind::Thumbnail, message_now(Kind::Thumbnail, &image_blob::encode_thumbnail(w.id, &jpeg)));
            }
        }
    }

    /// The catalog's images for a device that just connected: every icon (kind 4), the app list
    /// (kind 5) when it is known, and the thumbnails known so far (kind 3).
    pub fn connect_messages(&self) -> Vec<Vec<u8>> {
        let st = self.state.lock().unwrap();
        let mut out = Vec::new();
        for (id, png) in &st.icons {
            out.push(message_now(Kind::AppIcon, &image_blob::encode_icon(id, png)));
        }
        if let Some(apps) = &st.apps {
            out.push(message_now(Kind::AppList, &to_json(&app_infos(apps))));
        }
        for id in &st.order {
            if let Some((_, jpeg)) = st.thumbs.get(id) {
                out.push(message_now(Kind::Thumbnail, &image_blob::encode_thumbnail(*id, jpeg)));
            }
        }
        out
    }

    /// The streamed window, whose thumbnail refreshes every pass.
    pub fn set_active(&self, id: Option<u32>) {
        self.state.lock().unwrap().active = id;
    }

    pub fn counts(&self) -> (usize, usize, usize) {
        let st = self.state.lock().unwrap();
        (st.order.len(), st.icons.len(), st.apps.as_ref().map(|a| a.len()).unwrap_or(0))
    }
}

pub fn window_infos(windows: &[Window]) -> Vec<WindowInfo> {
    windows
        .iter()
        .map(|w| WindowInfo {
            id: w.id,
            title: w.title.clone(),
            app_name: w.app_name.clone(),
            bundle_id: w.app_id.clone(),
            width: w.width as i64,
            height: w.height as i64,
        })
        .collect()
}

pub fn app_infos(apps: &[App]) -> Vec<AppInfo> {
    apps.iter().map(|a| AppInfo { name: a.name.clone(), bundle_id: a.app_id.clone() }).collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::platform::*;
    use std::sync::mpsc::channel;

    struct Fake {
        windows: Mutex<Vec<Window>>,
    }

    fn w(id: u32, app: &str) -> Window {
        Window { id, title: app.into(), app_name: app.into(), app_id: app.into(), width: 400, height: 300 }
    }

    impl Platform for Fake {
        fn machine_name(&self) -> String {
            "fake".into()
        }
        fn windows(&self) -> Vec<Window> {
            self.windows.lock().unwrap().clone()
        }
        fn apps(&self) -> Vec<App> {
            vec![]
        }
        fn thumbnail(&self, window: u32) -> Option<Vec<u8>> {
            let ws = self.windows.lock().unwrap();
            ws.iter().find(|w| w.id == window).map(|w| w.app_id.as_bytes().to_vec())
        }
        fn icon(&self, _: &str) -> Option<Vec<u8>> {
            None
        }
        fn start_stream(&self, _: StreamConfig, _: Arc<dyn StreamSink>) -> Result<Box<dyn Stream>, String> {
            Err("no".into())
        }
        fn inject(&self, _: Input) {}
        fn raise(&self, _: u32) {}
        fn resize(&self, _: u32, _: u32, _: u32) -> Option<(u32, u32)> {
            None
        }
        fn window_command(&self, _: u32, _: WindowCommand) {}
        fn launch(&self, _: &str) -> Result<(), String> {
            Ok(())
        }
        fn pointer_location(&self) -> Option<(f64, f64)> {
            None
        }
        fn advertise(&self, _: &str, _: u16, _: &[(String, String)]) -> Result<Box<dyn Send>, String> {
            Err("no".into())
        }
    }

    /// X11 reuses window IDs: an ID that comes back as another app's window is a new window (last
    /// in the order, its own thumbnail), and a window that left takes its thumbnail with it.
    #[test]
    fn a_reused_window_id_is_a_new_window() {
        let fake = Arc::new(Fake { windows: Mutex::new(vec![w(1, "a"), w(2, "b"), w(3, "c")]) });
        let (tx, _rx) = channel();
        let server = Server::new(tx.clone());
        let cat = Catalog::new(fake.clone(), server, tx);
        assert!(cat.refresh());
        cat.refresh_images(true);
        let ids = |c: &Catalog| c.windows().iter().map(|w| w.id).collect::<Vec<_>>();
        assert_eq!(ids(&cat), vec![1, 2, 3]);
        // Window 1 closes and its ID is taken by another app's new window.
        *fake.windows.lock().unwrap() = vec![w(1, "z"), w(2, "b"), w(3, "c")];
        assert!(cat.refresh());
        assert_eq!(ids(&cat), vec![2, 3, 1]);
        assert!(!cat.state.lock().unwrap().thumbs.contains_key(&1), "the old window's thumbnail is gone");
        cat.refresh_images(true);
        assert_eq!(cat.state.lock().unwrap().thumbs.get(&1).map(|t| t.1.clone()), Some(b"z".to_vec()));
        // A window that leaves takes its thumbnail with it.
        *fake.windows.lock().unwrap() = vec![w(2, "b"), w(3, "c")];
        assert!(cat.refresh());
        assert!(!cat.state.lock().unwrap().thumbs.contains_key(&1));
        assert_eq!(ids(&cat), vec![2, 3]);
    }
}
