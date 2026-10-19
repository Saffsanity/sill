//! The once-a-second stats line (Stats.swift): `[1s] enc.out 58  net.sent 58  net.tick 33 · 1 client`
//! while anything happens, `[30s] idle · 0 clients · N windows` otherwise.

use std::collections::BTreeMap;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant};

pub struct Stats {
    counts: Mutex<BTreeMap<&'static str, u64>>,
    pub clients: AtomicUsize,
    pub windows: AtomicUsize,
}

static STATS: OnceLock<Stats> = OnceLock::new();

pub fn stats() -> &'static Stats {
    STATS.get_or_init(|| Stats { counts: Mutex::new(BTreeMap::new()), clients: AtomicUsize::new(0), windows: AtomicUsize::new(0) })
}

/// Counts one event under `key` for this second's line.
pub fn bump(key: &'static str) {
    add(key, 1);
}

pub fn add(key: &'static str, n: u64) {
    let mut c = stats().counts.lock().unwrap();
    *c.entry(key).or_insert(0) += n;
}

/// Prints the line every second while there is something to say, the heartbeat every 30 s when
/// idle. Runs until the process ends.
pub fn start_printing() {
    std::thread::Builder::new()
        .name("sill-stats".into())
        .spawn(|| {
            let mut last_idle = Instant::now();
            loop {
                std::thread::sleep(Duration::from_secs(1));
                let s = stats();
                let snapshot: BTreeMap<&'static str, u64> = std::mem::take(&mut *s.counts.lock().unwrap());
                let clients = s.clients.load(Ordering::Relaxed);
                if snapshot.is_empty() && clients == 0 {
                    if last_idle.elapsed() >= Duration::from_secs(30) {
                        last_idle = Instant::now();
                        crate::log(&format!("[30s] idle · 0 clients · {} windows", s.windows.load(Ordering::Relaxed)));
                    }
                    continue;
                }
                last_idle = Instant::now();
                let line: Vec<String> = snapshot.iter().map(|(k, v)| format!("{k} {v}")).collect();
                let who = if clients == 1 { "1 client".to_string() } else { format!("{clients} clients") };
                let body = if line.is_empty() { "nothing captured".to_string() } else { line.join("  ") };
                crate::log(&format!("[1s] {body} · {who}"));
            }
        })
        .expect("stats thread");
}
