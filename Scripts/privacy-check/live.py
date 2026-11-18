#!/usr/bin/env python3
"""TEST ONLY (docs/privacy-mode-plan.md, part 1): Lock this Mac when the last device leaves, on test hosts. Each case
starts synthetic CLI hosts on loopback (the software encoder, no router, no screen: never this Mac's screen or encoder)
with --lock-after-session, which locks nothing and puts no display to sleep: only Sill.app itself ever does
(PrivacyPolicy.locksForReal), and ScreenLocker's dry run says what it would do ("Privacy (dry run): would lock this Mac
now; nothing is locked."). The wait is shortened with the
TEST ONLY SILL_TEST_PRIVACY_GRACE, this Mac's lock is SILL_TEST_LOCKED_FILE's (its own witnesses ignored:
SILL_TEST_LOCK_IGNORE_MAC), and test clients (Scripts/sillclient.py) come and go. Nothing here locks this Mac, switches
its user, sleeps its display, posts input or a notification another app hears. Each host lives under 60 s.

    Scripts/privacy-check/live.py OUT [off|wait|back|move|locked|offconsole|nodisplay|nosymbol|quit|crash|pairing|gate|nosleep|away|all]

Prints one verdict per rule and exits 1 when one fails. Needs .build/release/SillHost."""
import os, re, signal, subprocess, sys, tempfile, threading, time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
HOST = os.path.join(ROOT, ".build/release/SillHost")
CLIENT = os.path.join(ROOT, "Scripts/sillclient.py")
BASE_ENV = {"SILL_TEST_LOOPBACK": "1", "SILL_TEST_SOFTWARE_ENCODER": "1", "SILL_TEST_NO_ROUTER": "1", "SILL_TEST_NO_SCREEN": "1",
            "SILL_TEST_LOCK_IGNORE_MAC": "1"}
GRACE = 5.0

verdicts = []


def verdict(ok, what):
    verdicts.append((ok, what))
    print(("ok   " if ok else "FAIL ") + what, flush=True)


class Host:
    """One synthetic host: its stdout's lines with the time each was read, and its ports (127.0.0.1 only): `port` the
    first, `ports` all of them once `want_ports` listen (2 with --remote: the home door and the remote door)."""
    def __init__(self, out, label, env, args=("--lock-after-session",), want_ports=1):
        self.lines = []
        self.out = out; self.label = label
        e = dict(os.environ); e.update(BASE_ENV); e.update(env)
        self.start = time.time()
        self.p = subprocess.Popen(["nice", "-n", "10", HOST, "--synthetic", *args], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                  env=e, start_new_session=True, text=True, bufsize=1)
        self.reader = threading.Thread(target=self._read, daemon=True); self.reader.start()
        self.port = None; self.ports = []
        for _ in range(100):
            time.sleep(0.1)
            r = subprocess.run(["lsof", "-nP", "-a", "-p", str(self.p.pid), "-iTCP", "-sTCP:LISTEN"], capture_output=True, text=True)
            if re.findall(r"(\*|\[::\]|0\.0\.0\.0):(\d+) \(LISTEN\)", r.stdout): self.stop(); raise SystemExit(f"{label}: a listener not on loopback")
            ports = sorted(set(re.findall(r"127\.0\.0\.1:(\d+) \(LISTEN\)", r.stdout)))
            if len(ports) >= want_ports: self.port = ports[0]; self.ports = ports; break
        if self.port is None: self.stop(); raise SystemExit(f"{label}: no listening port")

    def _read(self):
        for line in self.p.stdout:
            self.lines.append((time.time(), line.rstrip("\n")))

    def at(self, t):
        d = self.start + t - time.time()
        if d > 0: time.sleep(d)

    def now(self):
        return time.time() - self.start

    def stop(self, sig=signal.SIGTERM):
        if self.p.poll() is None:
            os.killpg(self.p.pid, sig)
            try: self.p.wait(5)
            except subprocess.TimeoutExpired: os.killpg(self.p.pid, signal.SIGKILL); self.p.wait()
        self.reader.join(2)
        with open(os.path.join(self.out, self.label + ".host.log"), "w") as f:
            for t, l in self.lines: f.write(f"{t - self.start:8.3f} {l}\n")

    def first(self, pattern, after=0.0):
        rx = re.compile(pattern)
        for t, l in list(self.lines):
            if t - self.start >= after and rx.search(l): return t - self.start
        return None

    def all(self, pattern, after=0.0, before=1e9):
        rx = re.compile(pattern)
        return [(t - self.start, l) for t, l in list(self.lines) if after <= t - self.start < before and rx.search(l)]

    def wait_for(self, pattern, after=0.0, timeout=10.0):
        """Seconds in when a line matching `pattern` (read `after` seconds in or later) arrives, waiting up to `timeout`."""
        end = time.time() + timeout
        while time.time() < end:
            t = self.first(pattern, after)
            if t is not None: return t
            time.sleep(0.02)
        return None


def client(host, out, label, start, seconds, args=("none",), port=None):
    """A sillclient session `start` seconds after the host's start, `seconds` long, in a thread, at `port` (the host's
    first one unless given); its output saved."""
    def run():
        host.at(start)
        r = subprocess.run([sys.executable, "-I", CLIENT, port or host.port, str(seconds), *args], capture_output=True, text=True,
                           timeout=seconds + 20, env={**os.environ, **BASE_ENV})
        open(os.path.join(out, label + ".client.log"), "w").write(r.stdout + r.stderr + f"\nEXIT {r.returncode}\n")
    th = threading.Thread(target=run); th.start()
    return th


def write(path, text):
    with open(path, "w") as f: f.write(text)


LEFT = r"^Privacy: the last device left; this Mac locks in 5 s unless one connects again\.$"
BACK = r"^Privacy: a device connected again within 5 s; this Mac won’t be locked\.$"
LOCKING = r"^Privacy: locking this Mac: the last device left 5 s ago\.$"
WOULD_LOCK = r"^Privacy \(dry run\): would lock this Mac now; nothing is locked\.$"
WOULD_SLEEP = r"^Privacy \(dry run\): would put this Mac’s display to sleep; nothing sleeps\.$"
LOCKED = r"^Privacy: this Mac is locked; its display sleeps\.$"
LOCKED_LIT = r"^Privacy: this Mac is locked\.$"
NOT_AWAY = r"^Privacy: the last device left; none connected from away from home, so this Mac won’t be locked\.$"
ANY_LOCK = r"would lock|^Privacy: locking"


def env(out, label, **extra):
    lock = os.path.join(out, label + ".lock"); write(lock, "0")
    e = {"SILL_TEST_PRIVACY_GRACE": str(GRACE), "SILL_TEST_LOCKED_FILE": lock}
    e.update(extra)
    return e, lock


# MARK: The cases

def run_off(out):
    """The switch off (no --lock-after-session): a device comes and goes, and nothing of the lock is said or done."""
    print("== off: no --lock-after-session", flush=True)
    h = Host(out, "off", {"SILL_TEST_LOCKED_FILE": os.path.join(out, "off.lock")}, args=())
    write(os.path.join(out, "off.lock"), "0")
    c = client(h, out, "off-c", 1.0, 3); c.join()
    h.at(1.0 + 3 + GRACE + 4); h.stop()
    privacy = h.all(r"Privacy|priv\.")
    verdict(not privacy, f"the switch off: no Privacy line and no priv. stat in {h.now():.0f} s ({privacy[:2]})")
    verdict(h.first(r"lock when the last device leaves") is None, "and no start line")


def run_wait(out):
    """The wait, the lock and its confirmation: the dry run says it would lock, the test's lock file then reads locked."""
    print("== wait: the last device leaves; the lock 5 s later; confirmed by the reading", flush=True)
    e, lock = env(out, "wait")
    h = Host(out, "wait", e)
    start = h.first(r"^Privacy: Lock this Mac when the last device leaves is on: 5 s after")
    verdict(start is not None, f"the start line says the switch is on and the 5 s wait ({start} s)")
    verdict(h.first(r"^Test privacy: the wait before the lock is 5 s \(SILL_TEST_PRIVACY_GRACE\)\.$") is not None, "the hook's line")
    c = client(h, out, "wait-c", 1.0, 3)
    c.join()
    L = h.wait_for(LEFT, timeout=5)
    verdict(L is not None and 3.5 <= L <= 6.0, f"the departure starts the wait, said once ({L} s; the client left about 4 s in)")
    K = h.wait_for(LOCKING, timeout=GRACE + 3)
    W = h.wait_for(WOULD_LOCK, timeout=2)
    if W is not None: write(lock, "1")     # macOS's lock, as SessionLock would read it (nothing is locked)
    verdict(L is not None and K is not None and GRACE - 0.05 <= K - L <= GRACE + 0.8,
            f"the lock comes {((K or 0) - (L or 0)):.2f} s after the departure (the wait, 5 s, and a tick)")
    verdict(W is not None and K is not None and W >= K, f"the dry run says it would lock, and locks nothing ({W} s)")
    C = h.wait_for(LOCKED, after=W or 0, timeout=4)
    S = h.wait_for(WOULD_SLEEP, after=W or 0, timeout=2)
    verdict(C is not None and W is not None and C - W <= 3.0, f"the reading says locked: '{LOCKED[1:-3]}' {((C or 0) - (W or 0)):.2f} s after the lock")
    verdict(S is not None and C is not None and S >= C, f"then the display sleep, dry ({S} s)")
    h.at((C or h.now()) + 2); h.stop()
    verdict(len(h.all(WOULD_LOCK)) == 1 and len(h.all(LEFT)) == 1, "one wait, one lock")
    verdict(any("priv.lockDry" in l for _, l in h.lines) and any("priv.sleepDry" in l for _, l in h.lines),
            "the stats count the dry lock and the dry sleep")


def run_back(out):
    """A device back within the wait keeps the Mac unlocked; its departure starts a new wait, whose lock the reading
    never confirms: the failure's line and the display sleep instead."""
    print("== back: a device back within the wait; then a lock the reading never confirms", flush=True)
    e, lock = env(out, "back")
    h = Host(out, "back", e)
    a = client(h, out, "back-a", 1.0, 3); a.join()
    L1 = h.wait_for(LEFT, timeout=4)
    b = client(h, out, "back-b", (L1 or 4) + 2.0, 3)
    B = h.wait_for(BACK, after=L1 or 0, timeout=6)
    verdict(B is not None and L1 is not None and B - L1 < GRACE, f"a device back {((B or 0) - (L1 or 0)):.2f} s into the wait: its line")
    b.join()
    L2 = h.wait_for(LEFT, after=(B or 0) + 0.1, timeout=6)
    verdict(L2 is not None, f"its departure: a new wait ({L2} s)")
    verdict(not h.all(ANY_LOCK, before=(L2 or 1e9)), "no lock for the first departure")
    K = h.wait_for(LOCKING, after=L2 or 0, timeout=GRACE + 3)
    verdict(K is not None and L2 is not None and GRACE - 0.05 <= K - L2 <= GRACE + 0.8, f"the second wait's lock at {((K or 0) - (L2 or 0)):.2f} s")
    F = h.wait_for(r"^Privacy: couldn’t lock this Mac \(it still read unlocked 3 s later\); its display sleeps instead\.$", after=K or 0, timeout=5)
    verdict(F is not None and K is not None and 2.9 <= F - K <= 3.8, f"the reading still unlocked: the failure's line {((F or 0) - (K or 0)):.2f} s after the lock")
    S = h.wait_for(WOULD_SLEEP, after=F or 0, timeout=2)
    verdict(S is not None, "and the display sleep instead, dry")
    h.at((S or h.now()) + 1); h.stop()


def run_move(out):
    """Two sessions that overlap (a device's move: the new connection before the old one leaves): no wait until the
    last one leaves."""
    print("== move: two overlapping sessions", flush=True)
    e, lock = env(out, "move")
    h = Host(out, "move", e)
    a = client(h, out, "move-a", 1.0, 6)
    b = client(h, out, "move-b", 4.0, 6)
    a.join()
    time.sleep(1.0)
    verdict(h.first(LEFT) is None, f"the first leaves while the second stays: no wait ({h.now():.1f} s)")
    b.join()
    L = h.wait_for(LEFT, timeout=4)
    verdict(L is not None and L >= 9.5, f"the last leaves: the wait ({L} s)")
    W = h.wait_for(WOULD_LOCK, after=L or 0, timeout=GRACE + 3)
    if W is not None: write(lock, "1")
    verdict(W is not None, f"and its lock ({W} s)")
    h.wait_for(LOCKED, after=W or 0, timeout=4)
    h.at(h.now() + 1); h.stop()


def run_not_locking(out, label, file_value, line, extra=None):
    e, lock = env(out, label, **(extra or {}))
    h = Host(out, label, e)
    c = client(h, out, label + "-c", 1.0, 3)
    if file_value is not None:
        h.at(2.0); write(lock, file_value)
    c.join()
    L = h.wait_for(LEFT, timeout=4)
    N = h.wait_for(line, after=L or 0, timeout=GRACE + 3)
    h.at((N or h.now()) + 2); h.stop()
    return L, N, h


def run_locked(out):
    print("== locked: this Mac locked already at the wait's end", flush=True)
    L, N, h = run_not_locking(out, "locked", "1", r"^Privacy: not locking this Mac: it is locked already\.$")
    verdict(N is not None and L is not None and GRACE - 0.05 <= N - L <= GRACE + 0.8, f"locked already: its line {((N or 0) - (L or 0)):.2f} s after the departure")
    verdict(not h.all(ANY_LOCK) and not h.all(WOULD_SLEEP), "no lock and no display sleep")


def run_offconsole(out):
    print("== offconsole: another user on the screen at the wait's end", flush=True)
    L, N, h = run_not_locking(out, "offconsole", "2", r"^Privacy: not locking this Mac: another user, or the login window, is on its screen\.$")
    verdict(N is not None, f"another user on the screen: its line ({N} s)")
    verdict(not h.all(ANY_LOCK) and not h.all(WOULD_SLEEP), "no lock and no display sleep")


def run_nodisplay(out):
    print("== nodisplay: no display to type the password at (#298)", flush=True)
    L, N, h = run_not_locking(out, "nodisplay", None, r"^Privacy: not locking this Mac: it has no display to type its password at \(issue #298\)\.$",
                              {"SILL_TEST_PRIVACY_DISPLAYS": "0"})
    verdict(h.first(r"^Test privacy: this Mac counts as having 0 displays") is not None, "the hook's line")
    verdict(N is not None, f"no display to type at: its line ({N} s)")
    verdict(not h.all(ANY_LOCK) and not h.all(WOULD_SLEEP), "no lock and no display sleep")


def run_nosymbol(out):
    print("== nosymbol: the lock call unavailable (a macOS without SACLockScreenImmediate)", flush=True)
    e, lock = env(out, "nosymbol", SILL_TEST_PRIVACY_NO_SYMBOL="1")
    h = Host(out, "nosymbol", e)
    c = client(h, out, "nosymbol-c", 1.0, 3); c.join()
    W = h.wait_for(WOULD_LOCK, timeout=GRACE + 5)
    F = h.wait_for(r"^Privacy: couldn’t lock this Mac \(macOS has no SACLockScreenImmediate\); its display sleeps instead\.$", after=W or 0, timeout=2)
    S = h.wait_for(WOULD_SLEEP, after=F or 0, timeout=2)
    h.at(h.now() + 1); h.stop()
    verdict(F is not None and W is not None and F - W < 0.5, f"the call unavailable: the failure's line at once ({((F or 0) - (W or 0)):.3f} s)")
    verdict(S is not None, "and the display sleep instead, dry")


def run_quit(out):
    print("== quit: SIGTERM during the wait", flush=True)
    e, lock = env(out, "quit")
    h = Host(out, "quit", e)
    c = client(h, out, "quit-c", 1.0, 3); c.join()
    L = h.wait_for(LEFT, timeout=4)
    h.at((L or 4) + 2.0)
    h.stop(signal.SIGTERM)
    Q = h.first(r"^Privacy: Sill is quitting; this Mac won’t be locked\.$")
    verdict(Q is not None and L is not None and Q > L, f"a quit during the wait: its line ({Q} s)")
    verdict(not h.all(ANY_LOCK), "no lock")


def run_crash(out):
    print("== crash: SIGKILL during the wait, then a new launch", flush=True)
    e, lock = env(out, "crash")
    h = Host(out, "crash", e)
    c = client(h, out, "crash-c", 1.0, 3); c.join()
    L = h.wait_for(LEFT, timeout=4)
    h.at((L or 4) + 2.0)
    h.stop(signal.SIGKILL)
    verdict(L is not None and not h.all(ANY_LOCK), "killed during the wait: no lock (nothing is left behind to make one)")
    h2 = Host(out, "crash-relaunch", e)
    h2.at(GRACE * 2 + 2)
    h2.stop()
    verdict(not h2.all(ANY_LOCK) and not h2.all(LEFT), f"the next launch, no device for {GRACE * 2 + 2:.0f} s: no wait and no lock")


def run_pairing(out):
    """--pairing's TLS home door: a connection that only pairs (sill-pair/1) never registers: no wait without a
    session, and none cancelled during one."""
    print("== pairing: a connection that only pairs", flush=True)
    d = tempfile.mkdtemp(prefix="privacy-pairing-", dir=out); os.chmod(d, 0o700)
    ident = os.path.join(out, "pairing-id"); os.makedirs(ident, exist_ok=True)
    e, lock = env(out, "pairing", SILL_TEST_REMOTE_DIR=d, SILL_TEST_REQUIRE_PAIRING="0")
    h = Host(out, "pairing", e, args=("--lock-after-session", "--pairing"))
    p1 = client(h, out, "pairing-ask1", 1.0, 3, args=("none", "--pair-ask", f"--identity={ident}")); p1.join()
    time.sleep(1.0)
    asked = "pairResult" in open(os.path.join(out, "pairing-ask1.client.log")).read()
    verdict(asked and h.first(LEFT) is None, f"a pairing connection alone (its kind 20 came back: {asked}): no wait ({h.now():.1f} s)")
    s = client(h, out, "pairing-session", h.now() + 0.5, 3, args=("none", "--tls", f"--identity={ident}", "--pin=none")); s.join()
    L = h.wait_for(LEFT, timeout=4)
    verdict(L is not None, f"a TLS session's departure: the wait ({L} s)")
    p2 = client(h, out, "pairing-ask2", (L or h.now()) + 1.5, 2, args=("none", "--pair-ask", f"--identity={ident}"))
    K = h.wait_for(LOCKING, after=L or 0, timeout=GRACE + 3)
    p2.join()
    asked2 = "pairResult" in open(os.path.join(out, "pairing-ask2.client.log")).read()
    verdict(asked2 and K is not None and L is not None and GRACE - 0.05 <= K - L <= GRACE + 0.8 and not h.all(BACK),
            f"a pairing connection during the wait (answered: {asked2}) ends nothing: the lock {((K or 0) - (L or 0)):.2f} s after the departure")
    h.at(h.now() + 4); h.stop()


def run_gate(out):
    """The device gate refuses a device below its floor before it registers: such a device never ends a wait."""
    print("== gate: a device the device gate refuses", flush=True)
    e, lock = env(out, "gate", SILL_TEST_MIN_DEVICE_VERSION="1.2")
    h = Host(out, "gate", e)
    a = client(h, out, "gate-a", 1.0, 3, args=("none", "--hello=1.3")); a.join()
    L = h.wait_for(LEFT, timeout=4)
    verdict(L is not None, f"an admitted device's departure: the wait ({L} s)")
    r = client(h, out, "gate-refused", (L or h.now()) + 1.5, 2, args=("none", "--hello=0.6"))
    K = h.wait_for(LOCKING, after=L or 0, timeout=GRACE + 3)
    r.join()
    refused = h.first(r"Refused|refused", after=L or 0)
    verdict(refused is not None, f"the older device is refused ({refused} s)")
    verdict(K is not None and L is not None and GRACE - 0.05 <= K - L <= GRACE + 0.8 and not h.all(BACK),
            f"and ends nothing: the lock {((K or 0) - (L or 0)):.2f} s after the departure")
    h.at(h.now() + 4); h.stop()


def run_nosleep(out):
    """Turn off its display too off (--lock-after-session=nosleep): the wait and the lock as ever, confirmed, and no
    display sleep."""
    print("== nosleep: the lock with its display left on", flush=True)
    e, lock = env(out, "nosleep")
    h = Host(out, "nosleep", e, args=("--lock-after-session=nosleep",))
    start = h.first(r"^Privacy: Lock this Mac when the last device leaves is on: 5 s after the last device leaves, Sill locks this Mac\. "
                    r"A dry run here \(only Sill\.app itself locks a Mac\): it says what it would do\.$")
    verdict(start is not None, f"the start line: the lock without the display sleep, and the dry run said ({start} s)")
    c = client(h, out, "nosleep-c", 1.0, 3); c.join()
    L = h.wait_for(LEFT, timeout=5)
    W = h.wait_for(WOULD_LOCK, after=L or 0, timeout=GRACE + 3)
    if W is not None: write(lock, "1")
    C = h.wait_for(LOCKED_LIT, after=W or 0, timeout=4)
    verdict(L is not None and W is not None and C is not None and GRACE - 0.05 <= W - L <= GRACE + 0.8 and C - W <= 3.0,
            f"the wait, the lock {((W or 0) - (L or 0)):.2f} s after the departure, its confirmation {((C or 0) - (W or 0)):.2f} s later: '{LOCKED_LIT[1:-3]}'")
    h.at((C or h.now()) + 2); h.stop()
    verdict(not h.all(WOULD_SLEEP) and not h.all(LOCKED), "no display sleep, and no line that says one")


def run_away(out):
    """Only after a device away from home (--lock-after-session=away, with --remote): a session at the home door leaves
    and no wait starts; one at the remote door (from this Mac: a relay on it, away from home as AwayPolicy says)
    leaves, and the wait and the lock follow."""
    print("== away: only after a device away from home", flush=True)
    e, lock = env(out, "away")
    h = Host(out, "away", e, args=("--lock-after-session=away", "--remote"), want_ports=2)
    rx = re.compile(r"^Remote access for this run on port (\d+) .*Pair with .* or (sill://pair\S+)$")
    h.wait_for(rx.pattern, timeout=5)
    m = next((rx.match(l) for _, l in h.lines if rx.match(l)), None)
    if m is None or m.group(1) not in h.ports:
        h.stop(); verdict(False, f"the remote door's port and link ({m and m.group(1)}, listening {h.ports})"); return
    remote_port, url = m.group(1), m.group(2)
    home_port = next(p for p in h.ports if p != remote_port)
    start = h.first(r"^Privacy: Lock this Mac when the last device leaves is on: 5 s after the last device leaves, when one connected from away from home, ")
    verdict(start is not None, f"the start line says only after a device away from home ({start} s)")
    a = client(h, out, "away-home", 1.0, 3, port=home_port); a.join()
    N = h.wait_for(NOT_AWAY, timeout=4)
    verdict(N is not None and h.first(LEFT) is None, f"a session at the home door alone leaves: no wait, its line ({N} s)")
    ident = os.path.join(out, "away-id"); os.makedirs(ident, exist_ok=True)
    b = client(h, out, "away-remote", (N or h.now()) + 0.5, 3, args=("none", f"--identity={ident}", f"--pair-url={url}"), port=remote_port)
    b.join()
    paired = "PAIR ok" in open(os.path.join(out, "away-remote.client.log")).read()
    L = h.wait_for(LEFT, after=N or 0, timeout=5)
    verdict(paired and L is not None, f"a session away from home (paired by the link, then the remote door's session) leaves: the wait ({L} s)")
    W = h.wait_for(WOULD_LOCK, after=L or 0, timeout=GRACE + 3)
    if W is not None: write(lock, "1")
    verdict(W is not None and L is not None and GRACE - 0.05 <= W - L <= GRACE + 0.8, f"and the lock {((W or 0) - (L or 0)):.2f} s after it")
    C = h.wait_for(LOCKED, after=W or 0, timeout=4)
    verdict(C is not None, f"confirmed, the display sleep after it ({C} s)")
    h.at(h.now() + 1); h.stop()
    verdict(len(h.all(WOULD_LOCK)) == 1 and len(h.all(NOT_AWAY)) == 1, "one lock, and one visit at home said")


CASES = {"off": run_off, "wait": run_wait, "back": run_back, "move": run_move, "locked": run_locked, "offconsole": run_offconsole,
         "nodisplay": run_nodisplay, "nosymbol": run_nosymbol, "quit": run_quit, "crash": run_crash, "pairing": run_pairing, "gate": run_gate,
         "nosleep": run_nosleep, "away": run_away}

if __name__ == "__main__":
    if len(sys.argv) < 2 or not os.path.exists(HOST):
        raise SystemExit(__doc__)
    out = os.path.abspath(sys.argv[1]); os.makedirs(out, exist_ok=True)
    which = sys.argv[2:] or ["all"]
    names = list(CASES) if "all" in which else which
    for n in names:
        if n not in CASES: raise SystemExit(f"no case {n}: {', '.join(CASES)}")
        CASES[n](out)
    failed = [w for ok, w in verdicts if not ok]
    print(f"privacy-check: {len(verdicts) - len(failed)} of {len(verdicts)} verdicts hold" + (f"; FAILED: {failed}" if failed else ""))
    sys.exit(1 if failed else 0)
