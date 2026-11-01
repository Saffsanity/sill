#!/usr/bin/env python3
"""TEST ONLY (docs/locked-mac-plan.md): a locked Mac on a test host, measured. Each run starts one
synthetic CLI host on loopback (the software encoder, no router, no screen: never this Mac's screen,
encoder or clipboard), drives its lock through the TEST ONLY hooks (SILL_TEST_LOCKED_FILE, the screen's
notify name of the test's own, SILL_TEST_LOCK_NOTE's delivered notifications; never a real lock, never a
notification another app hears), runs test clients that save what they receive (sillclient.py --dump),
decodes the keyframes (Scripts/lock-check/frames, the software decoder), and prints one verdict per rule:
the frames stop at the lock, the placeholder is black, the list says why, nothing else of the Mac goes out,
requests are refused, input follows the reading, the unlock waits for its settle, the flap never unlocks.
Each host lives under 60 s and is killed at the end.

    Scripts/lock-check/live.py OUT [poll|start|notify|paired|all]

Needs .build/release/SillHost and .build/lock-check/frames (Scripts/lock-check/build.sh). Exits 1 when a
verdict fails."""
import ctypes, json, os, re, signal, subprocess, sys, threading, time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
HOST = os.path.join(ROOT, ".build/release/SillHost")
CLIENT = os.path.join(ROOT, "Scripts/sillclient.py")
FRAMES = os.path.join(ROOT, ".build/lock-check/frames")
BASE_ENV = {"SILL_TEST_LOOPBACK": "1", "SILL_TEST_SOFTWARE_ENCODER": "1", "SILL_TEST_NO_ROUTER": "1", "SILL_TEST_NO_SCREEN": "1"}

verdicts = []
def verdict(ok, what):
    verdicts.append((ok, what))
    print(("ok   " if ok else "FAIL ") + what, flush=True)


class Host:
    """One synthetic host: its stdout's lines with the epoch time each was read, its port."""
    def __init__(self, out, label, env, args=()):
        self.lines = []
        self.out = out; self.label = label
        e = dict(os.environ); e.update(BASE_ENV); e.update(env)
        self.start = time.time()
        self.p = subprocess.Popen(["nice", "-n", "10", HOST, "--synthetic", *args], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                  env=e, start_new_session=True, text=True, bufsize=1)
        self.reader = threading.Thread(target=self._read, daemon=True); self.reader.start()
        self.port = None
        for _ in range(100):
            time.sleep(0.1)
            r = subprocess.run(["lsof", "-nP", "-a", "-p", str(self.p.pid), "-iTCP", "-sTCP:LISTEN"], capture_output=True, text=True)
            if re.findall(r"(\*|\[::\]|0\.0\.0\.0):(\d+) \(LISTEN\)", r.stdout): self.stop(); raise SystemExit(f"{label}: a listener not on loopback")
            ports = re.findall(r"127\.0\.0\.1:(\d+) \(LISTEN\)", r.stdout)
            if ports: self.port = ports[0]; break
        if self.port is None: self.stop(); raise SystemExit(f"{label}: no listening port")

    def _read(self):
        for line in self.p.stdout:
            self.lines.append((time.time(), line.rstrip("\n")))

    def at(self, t):
        """Sleep until `t` seconds after the host started."""
        d = self.start + t - time.time()
        if d > 0: time.sleep(d)

    def stop(self):
        if self.p.poll() is None:
            os.killpg(self.p.pid, signal.SIGTERM)
            try: self.p.wait(3)
            except subprocess.TimeoutExpired: os.killpg(self.p.pid, signal.SIGKILL); self.p.wait()
        self.reader.join(2)
        with open(os.path.join(self.out, self.label + ".host.log"), "w") as f:
            for t, l in self.lines: f.write(f"{t - self.start:8.3f} {l}\n")

    def first(self, pattern, after=0.0):
        """The first line matching `pattern` read `after` seconds or more after the start: (seconds in, line)."""
        rx = re.compile(pattern)
        for t, l in self.lines:
            if t - self.start >= after and rx.search(l): return t - self.start, l
        return None, None

    def all(self, pattern, after=0.0, before=1e9):
        rx = re.compile(pattern)
        return [(t - self.start, l) for t, l in self.lines if after <= t - self.start < before and rx.search(l)]


def client(host, out, label, seconds, args, start):
    """A sillclient run `start` seconds after the host's start, in a thread; its output saved."""
    def run():
        host.at(start)
        r = subprocess.run([sys.executable, "-I", CLIENT, host.port, str(seconds), *args], capture_output=True, text=True,
                           timeout=seconds + 20, env={**os.environ, **BASE_ENV})
        open(os.path.join(out, label + ".client.log"), "w").write(r.stdout + r.stderr + f"\nEXIT {r.returncode}\n")
    th = threading.Thread(target=run); th.start()
    return th


def messages(out, label, host):
    """A client's dump: [(seconds after the host's start, kind, key, bytes, extra)]."""
    path = os.path.join(out, label, "messages.tsv")
    rows, t0 = [], None
    for line in open(path):
        if line.startswith("# t0 "): t0 = float(line.split()[2]); continue
        parts = line.rstrip("\n").split("\t")
        at = float(parts[0]) + (t0 - host.start if t0 else 0)
        rows.append((at, int(parts[1]), parts[2] == "1", int(parts[3]), parts[4] if len(parts) > 4 else ""))
    return rows


def decoded(out, label, host):
    """The client's keyframes decoded: [(seconds after the host's start, mean luma, max, % above 16, size)]."""
    d = os.path.join(out, label)
    t0 = None
    for line in open(os.path.join(d, "messages.tsv")):
        if line.startswith("# t0 "): t0 = float(line.split()[2]); break
    r = subprocess.run([FRAMES, d], capture_output=True, text=True)
    open(os.path.join(out, label + ".frames.log"), "w").write(r.stdout + r.stderr)
    rows = []
    for line in r.stdout.splitlines():
        m = re.match(r"key-\d+\.bin at ([\d.]+) s: (\d+)×(\d+), \d+ bytes, luma mean ([\d.]+), max (\d+), ([\d.]+)% above 16", line)
        if m: rows.append((float(m.group(1)) + (t0 - host.start), float(m.group(4)), int(m.group(5)), float(m.group(6)), f"{m.group(2)}×{m.group(3)}"))
        elif "did not decode" in line: rows.append((None, None, None, None, line))
    return rows


def lists(rows):
    """The window lists among a dump's rows: [(at, windows, locked, offConsole)]."""
    out = []
    for at, kind, _, _, extra in rows:
        if kind != 2: continue
        m = re.search(r"windows=(\d+) locked=(\d) offConsole=(\d)", extra)
        if m: out.append((at, int(m.group(1)), m.group(2) == "1", m.group(3) == "1"))
    return out


def write(path, text):
    with open(path, "w") as f: f.write(text)


# MARK: The runs

def run_poll(out):
    """The poll's path at the CLI's plain door: screen locked, off console, back, the unlock's settle, the flap."""
    print("== poll: SILL_TEST_LOCKED_FILE, the plain door, two clients", flush=True)
    lock = os.path.join(out, "poll.lock"); write(lock, "0")
    path = os.path.join(out, "poll.pointer")
    write(path, "".join(f"{i * 0.1:.1f} {200 + (i * 7) % 900} {150 + (i * 5) % 600}\n" for i in range(600)))
    env = {"SILL_TEST_LOCKED_FILE": lock, "SILL_TEST_LOCK_LOG": "1", "SILL_TEST_PATTERN": "noise", "SILL_TEST_INPUT_LOG": "1",
           "SILL_TEST_POINTER_PATH": path, "SILL_TEST_PASTEBOARD": f"me.saffer.sill.test.lockcheck.{os.getpid()}", "SILL_TEST_CLIPBOARD_LOG": "1"}
    h = Host(out, "poll", env, args=["--audio"])
    # Times are the client's, which starts 1 s after the host. The test pattern at Standard (1512×948), whose
    # noise square makes every frame of it large; the placeholder's are tiny.
    c1 = client(h, out, "poll-c1", 52, ["desktop", "--stats", "--clipboard", "--audio", "--pointer", f"--dump={out}/poll-c1",
             "--set=captureScale=1@0.3",
             # screen locked (host 5 to 15 s): every kind the lock refuses; off console (15 to 25 s): input again
             "--pick=window:1@8", '--raw7={"bundleID":"me.saffer.sill.test.lockcheck"}@8.5', "--gesture=swipeUp@9", "--copy=while-locked@9.5",
             "--tap=0.5,0.5@10", "--key=4@10.5", "--tap=0.5,0.5@15", "--key=5@15.5",
             # after the last unlock (host about 45 to 46.6 s)
             "--copy=after-the-unlock@46.2", "--tap=0.4,0.4@46.5", "--gesture=swipeDown@46.8"], start=1.0)
    c2 = client(h, out, "poll-c2", 18, ["desktop", "--stats", f"--dump={out}/poll-c2"], start=18.0)
    plan = [(5.0, "1"), (15.0, "2"), (25.0, "1"), (30.0, "0"), (36.0, "2"), (38.0, "0"), (39.2, "1"), (43.0, "0")]
    flips = {}
    for t, v in plan:
        h.at(t); write(lock, v); flips[t] = time.time() - h.start
    c1.join(); c2.join()
    h.at(54.0); h.stop()
    rows1, rows2 = messages(out, "poll-c1", h), messages(out, "poll-c2", h)
    keys1 = decoded(out, "poll-c1", h); keys2 = decoded(out, "poll-c2", h)

    L1, _ = h.first(r"^Locked: this Mac's screen is locked", 4.9)
    L2, _ = h.first(r"^Locked: another user, or the login window", 14.9)
    L3, _ = h.first(r"^Locked: this Mac's screen is locked", 24.9)
    U1, _ = h.first(r"^Unlocked:", 29.9)
    L4, _ = h.first(r"^Locked: another user, or the login window", 35.9)
    U1b, _ = h.first(r"^Unlocked:", 35.9)
    L5, _ = h.first(r"^Locked: this Mac's screen is locked", 39.1)
    U2, _ = h.first(r"^Unlocked:", 42.9)
    verdict(L1 is not None and L1 - 5.0 <= 1.1, f"the screen locked (file 1 at 5.0 s): 'Locked:' at {L1} s, the next poll's")
    verdict(L2 is not None and L2 - 15.0 <= 1.1, f"off console (file 2 at 15.0 s): its line at {L2} s")
    verdict(L3 is not None and L3 - 25.0 <= 1.1, f"back on the console, locked (file 1 at 25.0 s): at {L3} s")
    verdict(U1 is not None and 2.0 <= U1 - 30.0 <= 3.6, f"the unlock (file 0 at 30.0 s) waits for its settle: 'Unlocked:' at {U1} s ({(U1 or 0) - 30.0:.2f} s)")
    verdict(L4 is not None and U1b is not None and U1b >= 43.0 and L5 is not None,
            f"the flap (2 at 36, 0 at 38, 1 at 39.2): off console at {L4} s, screen locked at {L5} s, no unlock between (next 'Unlocked:' at {U1b} s)")
    verdict(U2 is not None and 2.0 <= U2 - 43.0 <= 3.6, f"the last unlock (file 0 at 43.0 s): at {U2} s")

    # The frames: none of the pattern after the lock's line; the placeholder's few; the pattern back after the unlock.
    frames1 = [(at, key, n) for at, kind, key, n, _ in rows1 if kind == 1]
    ps1 = [at for at, kind, _, _, _ in rows1 if kind == 0]
    def big(a, b): return [f for f in frames1 if a <= f[0] < b and f[2] > 4000]
    def count(a, b): return [f for f in frames1 if a <= f[0] < b]
    if L1 and U1:
        late = [f for f in count(L1 + 0.1, U1) if f[2] > 4000]
        verdict(len(big(L1 - 3, L1)) > 5 and not late,
                f"the pattern's frames stop at the lock: {len(big(L1 - 3, L1))} in the 3 s before it, {len(late)} large ones after it until the unlock "
                f"({len(count(L1 + 0.1, U1))} frames in all then, {sum(f[2] for f in count(L1 + 0.1, U1))} bytes)")
        last_big = max([f[0] for f in frames1 if f[0] < L1 + 1 and f[2] > 4000], default=None)
        verdict(last_big is not None and last_big <= L1 + 0.1, f"the last frame of the pattern came {((last_big or 0) - L1) * 1000:.0f} ms after the lock's line")
    if U2:
        back = big(U2, U2 + 3)
        verdict(len(back) > 10, f"the pattern back after the last unlock: {len(back)} large frames in the 3 s after it")
    blacks = [k for k in keys1 if k[0] is not None and L1 and U1 and L1 <= k[0] < U1]
    verdict(bool(blacks) and all(k[1] < 1.0 and k[2] <= 16 and k[3] == 0 for k in blacks),
            f"every keyframe while locked is black: {[(round(k[0], 2), k[1], k[2], k[3], k[4]) for k in blacks]}")
    before = [k for k in keys1 if k[0] is not None and L1 and k[0] < L1]
    verdict(bool(before) and all(k[1] > 50 for k in before), f"the keyframes before the lock are the pattern: {[(round(k[0], 2), k[1]) for k in before]}")
    after = [k for k in keys1 if k[0] is not None and U2 and k[0] > U2]
    verdict(bool(after) and all(k[1] > 50 for k in after), f"the keyframe after the unlock is the pattern again: {[(round(k[0], 2), k[1]) for k in after]}")

    # The lists: why, at each change.
    l1 = lists(rows1)
    # The runner reads a host line a few ms after it is printed: a list may arrive a moment before it.
    def list_after(t): return next((x for x in l1 if t is not None and x[0] >= t - 0.1), None)
    a, b, c, u = list_after(L1), list_after(L2), list_after(L3), list_after(U1)
    verdict(a is not None and a[1] == 0 and a[2] and not a[3] and a[0] - L1 < 0.2, f"a locked list at once after the lock: {a}")
    verdict(b is not None and b[2] and b[3] and b[0] - L2 < 0.2, f"off console the list says offConsole: {b}")
    verdict(c is not None and c[2] and not c[3], f"back on the console: locked, not offConsole: {c}")
    verdict(u is not None and not u[2] and not u[3], f"after the unlock: neither: {u}")
    inside = [x for x in l1 if L1 and U1 and L1 + 0.2 <= x[0] < U1]
    verdict(all(x[1] == 0 and x[2] for x in inside), f"no list while locked has a window or lacks locked ({len(inside)} lists)")

    # Nothing else of the Mac while locked: thumbnails 3, icons 4, apps 5, cursor 14, pointer 26, clipboard 32, sound 43.
    for k, what in [(3, "thumbnails"), (4, "icons"), (5, "the app list"), (14, "cursor shapes"), (26, "the pointer"), (32, "the clipboard"), (43, "sound")]:
        n = [r for r in rows1 if r[1] == k and L1 and U1 and L1 + 0.1 <= r[0] < U1]
        verdict(not n, f"no {what} (kind {k}) to the first client while locked: {len(n)}")
    snd = [r for r in rows1 if r[1] == 43 and r[0] < (L1 or 0)]
    ptr = [r for r in rows1 if r[1] == 26 and r[0] < (L1 or 0)]
    verdict(len(snd) > 20 and len(ptr) > 5, f"…which it got before the lock: {len(snd)} sound messages, {len(ptr)} pointer reports")
    snd2 = [r for r in rows1 if r[1] == 43 and U2 and r[0] > U2 + 1]
    verdict(len(snd2) > 10, f"the sound back after the last unlock: {len(snd2)} messages")

    # The client that connected off console (18 s): the black keyframe, no icons or apps until the unlock.
    keysc2 = [k for k in keys2 if k[0] is not None and U1 and k[0] < U1]
    verdict(bool(keysc2) and all(k[1] < 1.0 for k in keysc2), f"a device connecting off console gets the black keyframe: {[(round(k[0], 2), k[1]) for k in keysc2]}")
    early = [r for r in rows2 if r[1] in (3, 4, 5, 14, 26, 43) and U1 and r[0] < U1]
    late45 = [r for r in rows2 if r[1] in (4, 5) and U1 and r[0] >= U1]
    verdict(not early and late45, f"…none of the Mac's icons, apps, thumbnails, cursor, pointer or sound until the unlock ({len(early)}), then its icons and apps ({len(late45)})")
    l2 = lists(rows2)
    verdict(bool(l2) and l2[0][2] and l2[0][3], f"…and its first list says off console: {l2[0] if l2 else None}")

    # The refusals and the input.
    for pattern, what in [(r"^Locked: refused a window pick", "a window pick"), (r"^Locked: refused an app launch", "an app launch"),
                          (r"^Locked: refused a gesture", "a gesture"), (r"^Locked: dropped a device's clipboard text", "a device's text"),
                          (r"^Locked: dropped an input event", "input from the plain door (unpaired)")]:
        t, line = h.first(pattern, 5.0)
        verdict(t is not None and L1 and U1 and L1 <= t < U1, f"refused while locked: {what} ({t} s: {line})")
    posted = h.all(r"^Test input: ", L1 or 5.0, U1 or 30.0)
    verdict(not posted, f"nothing posted from the plain door while locked: {posted[:3]}")
    posted_after = h.all(r"^Test input: ", (U2 or 45.0), 54.0)
    verdict(bool(posted_after), f"after the unlock its tap is posted: {posted_after[:2]}")
    copy_after = h.all(r"^Test clipboard: .* from ", U2 or 45.0, 54.0)
    copy_during = h.all(r"^Test clipboard: .* from ", L1 or 5.0, U1 or 30.0)
    verdict(bool(copy_after) and not copy_during, f"the clipboard: nothing written while locked ({len(copy_during)}), written after ({copy_after[:1]})")
    gesture_after = h.all(r"^Gesture from ", U2 or 45.0, 54.0)
    verdict(bool(gesture_after), f"a gesture after the unlock is taken: {gesture_after[:1]}")
    placeholder = h.all(r"^Streaming a placeholder")
    verdict(len(placeholder) >= 1, f"the host streamed the placeholder: {placeholder[:2]}")
    withheld = sum(int(m) for _, l in h.all(r"\[1s\]") for m in re.findall(r"lock\.withheld (\d+)", l))
    verdict(True, f"(the server's gate withheld {withheld} messages in all)")


def run_start(out):
    """A host that starts on a Mac already locked: its reading at its first look, the settle at its unlock."""
    print("== start: a host started on a locked Mac (SILL_TEST_LOCKED_FILE holding 1 from the start)", flush=True)
    lock = os.path.join(out, "start.lock"); write(lock, "1")
    h = Host(out, "start", {"SILL_TEST_LOCKED_FILE": lock, "SILL_TEST_LOCK_LOG": "1", "SILL_TEST_PATTERN": "noise"})
    c1 = client(h, out, "start-c1", 11, ["desktop", "--stats", f"--dump={out}/start-c1", "--set=captureScale=1@0.3"], start=1.0)
    h.at(6.0); write(lock, "0")
    c1.join()
    h.at(13.0); h.stop()
    rows = messages(out, "start-c1", h)
    keys = decoded(out, "start-c1", h)
    L, _ = h.first(r"^Locked: this Mac's screen is locked")
    U, _ = h.first(r"^Unlocked:", 5.9)
    verdict(L is not None and L < 1.0, f"its first look's line: 'Locked: this Mac's screen is locked' at {L} s")
    first = lists(rows)[:1]
    verdict(bool(first) and first[0][2] and not first[0][3], f"the first list a device gets says locked, not another user: {first}")
    verdict(U is not None and 2.0 <= U - 6.0 <= 3.6, f"its unlock (file 0 at 6.0 s) waits for the settle: 'Unlocked:' at {U} s")
    early = [k for k in keys if k[0] is not None and U and k[0] < U]
    late = [k for k in keys if k[0] is not None and U and k[0] >= U]
    verdict(bool(early) and all(k[1] < 1.0 for k in early) and bool(late) and all(k[1] > 50 for k in late),
            f"black keyframes before the unlock {[(round(k[0], 2), k[1]) for k in early]}, the pattern after {[(round(k[0], 2), k[1]) for k in late]}")


def run_notify(out):
    """The immediate paths: the screen's notify state (a name of the test's own) and a delivered notification."""
    print("== notify: SILL_TEST_LOCK_NOTIFY and SILL_TEST_LOCK_NOTE", flush=True)
    lib = ctypes.CDLL("/usr/lib/libSystem.B.dylib")
    name = f"me.saffer.sill.test.lockcheck.{os.getpid()}".encode()
    token = ctypes.c_int(0)
    assert lib.notify_register_check(name, ctypes.byref(token)) == 0
    lib.notify_set_state(token, ctypes.c_uint64(0))
    env = {"SILL_TEST_LOCK_NOTIFY": name.decode(), "SILL_TEST_LOCK_NOTE": "14 sessionDidResignActive; 22 sessionDidBecomeActive",
           "SILL_TEST_LOCK_LOG": "1", "SILL_TEST_PATTERN": "noise"}
    h = Host(out, "notify", env)
    c1 = client(h, out, "notify-c1", 28, ["desktop", "--stats", f"--dump={out}/notify-c1", "--set=captureScale=1@0.3"], start=1.0)
    h.at(5.0); lib.notify_set_state(token, ctypes.c_uint64(1)); lib.notify_post(name); posted_lock = time.time() - h.start
    h.at(9.0); lib.notify_set_state(token, ctypes.c_uint64(0)); lib.notify_post(name); posted_unlock = time.time() - h.start
    c1.join()
    h.at(29.5); h.stop()
    lib.notify_cancel(token)
    rows = messages(out, "notify-c1", h)
    L1, _ = h.first(r"^Locked: this Mac's screen is locked", 4.5)
    U1, _ = h.first(r"^Unlocked:", 8.5)
    N, _ = h.first(r"^Test lock: com.apple|^Test lock: NSWorkspace", 13.5)
    L2, _ = h.first(r"^Locked: another user", 13.5)
    U2, _ = h.first(r"^Unlocked:", 21.5)
    verdict(L1 is not None and (L1 - posted_lock) < 0.05,
            f"the screen's notify state set and posted at {posted_lock:.3f} s: 'Locked:' at {L1} s, {((L1 or 99) - posted_lock) * 1000:.1f} ms later (no poll)")
    verdict(U1 is not None and 2.0 <= U1 - posted_unlock <= 2.6, f"its unlock posted at {posted_unlock:.3f} s: 'Unlocked:' at {U1} s, after the settle")
    verdict(N is not None and L2 is not None and 0 <= L2 - N < 0.05, f"a delivered sessionDidResignActive at {N} s: off console at {L2} s, at once")
    verdict(U2 is not None and 2.0 <= U2 - 22.0 <= 2.8, f"sessionDidBecomeActive at 22 s: 'Unlocked:' at {U2} s, after the settle")
    frames = [(at, n) for at, kind, _, n, _ in rows if kind == 1]
    for L, label in [(L1, "the notify lock"), (L2, "the delivered notification")]:
        if L is None: continue
        last_big = max([f[0] for f in frames if f[0] < L + 1 and f[1] > 4000], default=None)
        verdict(last_big is not None and last_big <= L + 0.1, f"after {label}: the last frame of the pattern {((last_big or 0) - L) * 1000:.0f} ms after the line")
        late = [f for f in frames if L + 0.1 <= f[0] < L + 2 and f[1] > 4000]
        verdict(not late, f"after {label}: no large frame in the 2 s after it ({len(late)})")


def run_paired(out):
    """Who types: a paired session at a locked screen does; nobody off console but the up of a held key; an unpaired one never."""
    print("== paired: --pairing, Require pairing off, a paired and an unpaired client", flush=True)
    lock = os.path.join(out, "paired.lock"); write(lock, "0")
    path = os.path.join(out, "paired.pointer")
    write(path, "".join(f"{i * 0.1:.1f} {300 + (i * 3) % 500} {200 + (i * 2) % 400}\n" for i in range(600)))
    remote = os.path.join(out, "paired.remote"); os.makedirs(remote, exist_ok=True); os.chmod(remote, 0o700)
    env = {"SILL_TEST_LOCKED_FILE": lock, "SILL_TEST_REMOTE_DIR": remote, "SILL_TEST_REQUIRE_PAIRING": "0", "SILL_TEST_INPUT_LOG": "1",
           "SILL_TEST_POINTER_PATH": path}
    h = Host(out, "paired", env, args=["--pairing"])
    h.at(1.0)
    _, line = h.first(r"sill://pair")
    link = re.search(r"(sill://pair\S+)", line or "")
    if not link: h.stop(); verdict(False, "the host printed no pairing link"); return
    idp, idu = os.path.join(out, "paired.idP"), os.path.join(out, "paired.idU")
    pair = subprocess.run([sys.executable, "-I", CLIENT, h.port, "2", "none", f"--pair-url={link.group(1)}", f"--identity={idp}"],
                          capture_output=True, text=True, timeout=30, env={**os.environ, **BASE_ENV})
    open(os.path.join(out, "paired-pair.client.log"), "w").write(pair.stdout + pair.stderr)
    h.at(4.0); write(lock, "1")
    # host 6: both connect; P taps at 8 and 8.5 (screen locked: posted), holds a key 9 to 13 (down posted,
    # its up off console: let go), taps at 12 and 12.5 (off console: dropped), 19 (unlocked: posted). U taps at 8.2, 8.7.
    cp = client(h, out, "paired-P", 15, ["desktop", "--tls", f"--identity={idp}", "--stats",
                "--tap=0.5,0.5@2", "--tap=0.5,0.5@2.5", "--key=4,4@3", "--tap=0.6,0.6@6", "--tap=0.6,0.6@6.5", "--tap=0.3,0.3@13"], start=6.0)
    cu = client(h, out, "paired-U", 9, ["desktop", "--tls", f"--identity={idu}", "--pin=none", "--stats",
                "--tap=0.5,0.5@2.2", "--tap=0.5,0.5@2.7"], start=6.0)
    h.at(11.0); write(lock, "2")
    h.at(14.0); write(lock, "0")
    cp.join(); cu.join()
    h.at(22.5); h.stop()
    posted_locked = h.all(r"^Test input: left mouse (down|up)", 7.5, 9.5)
    verdict(len(posted_locked) >= 2, f"at a locked screen the paired session's taps are posted: {len(posted_locked)} button events")
    key_down = h.all(r"^Test input: key \d+ down", 8.5, 9.8)
    key_up = h.all(r"^Test input: key \d+ up", 12.5, 13.8)
    verdict(bool(key_down) and bool(key_up), f"its key held across the switch away: down posted ({key_down[:1]}), its up let go off console ({key_up[:1]})")
    off = h.all(r"^Test input: left mouse", 11.6, 14.0)
    verdict(not off, f"off console none of its taps is posted: {off[:2]}")
    after = h.all(r"^Test input: left mouse", 16.5, 22.0)
    verdict(bool(after), f"after the unlock its tap is posted again: {after[:1]}")
    dropped = h.all(r"^Locked: dropped (an input event|\d+ input events)")
    verdict(bool(dropped), f"the unpaired session's taps and the paired one's off console dropped: {dropped[:2]}")
    pclient = open(os.path.join(out, "paired-P.client.log")).read()
    uclient = open(os.path.join(out, "paired-U.client.log")).read()
    verdict("paired=1" in pclient and "paired=0" in uclient, "the host said which session is paired (kind 16's sessionPaired: 1 and 0)")


def main():
    if len(sys.argv) < 2: sys.exit(__doc__)
    out = os.path.abspath(sys.argv[1]); os.makedirs(out, exist_ok=True)
    which = sys.argv[2] if len(sys.argv) > 2 else "all"
    for f in (HOST, FRAMES):
        if not os.path.exists(f): sys.exit(f"live.py: no {f} (swift build -c release; Scripts/lock-check/build.sh)")
    if which in ("poll", "all"): run_poll(out)
    if which in ("start", "all"): run_start(out)
    if which in ("notify", "all"): run_notify(out)
    if which in ("paired", "all"): run_paired(out)
    bad = [w for ok, w in verdicts if not ok]
    print(f"{len(verdicts) - len(bad)} of {len(verdicts)} verdicts passed")
    sys.exit(1 if bad else 0)

main()
