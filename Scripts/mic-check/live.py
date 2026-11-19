#!/usr/bin/env python3
"""TEST ONLY: the devices' microphones on the Mac against synthetic test hosts on loopback (docs/microphone-plan.md
§10.2, the gates M1 to M6, M9 and M10). Each case starts .build/release/SillHost --synthetic --pairing (a throwaway
identity in a folder of the test's own) with SILL_TEST_LOOPBACK, SILL_TEST_SOFTWARE_ENCODER, SILL_TEST_NO_ROUTER and
SILL_TEST_NO_SCREEN, so nothing touches the hardware encoder, the router or ScreenCaptureKit, and SILL_TEST_MIC_SINK
(a WAV under OUT of exactly what Sill Microphone would hear; nothing played, no audio device opened). It pairs test
clients by the host's links and drives Scripts/sillclient.py's --mic (Scripts/mic-check/tone.swift's packets),
--mic-claim, --mic-end, --mic-flood, --mic-formats and --raw48 against it, then finds each of the tone's clicks in
the WAV (analyze). No microphone, no speaker, no window, no encoder of this Mac's. Every host runs under a minute.
Prints a verdict per rule; exits 1 on any FAIL.

    Scripts/mic-check/build.sh OUT/tools && python3 Scripts/mic-check/live.py OUT [nohook|live|two|lock|unpaired|hostile|setup|all]"""
import os, re, signal, subprocess, sys, threading, time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
HOST = os.path.join(ROOT, ".build/release/SillHost")
CLIENT = os.path.join(ROOT, "Scripts/sillclient.py")
BASE_ENV = {"SILL_TEST_LOOPBACK": "1", "SILL_TEST_SOFTWARE_ENCODER": "1", "SILL_TEST_NO_ROUTER": "1", "SILL_TEST_NO_SCREEN": "1"}
verdicts = []


def verdict(ok, what):
    verdicts.append((ok, what))
    print(("ok   " if ok else "FAIL ") + what, flush=True)


class Host:
    """One synthetic --pairing host with a test Sill Microphone: its stdout's lines and its port."""
    def __init__(self, out, label, env=None, sink="file"):
        self.out, self.label, self.lines = out, label, []
        self.wav = os.path.join(out, label + ".wav")
        remote = os.path.join(out, label + ".remote"); os.makedirs(remote, exist_ok=True); os.chmod(remote, 0o700)
        e = dict(os.environ); e.update(BASE_ENV); e.update({"SILL_TEST_REMOTE_DIR": remote, "SILL_TEST_ASK_FROM_THIS_MAC": "1"})
        if sink == "file": e["SILL_TEST_MIC_SINK"] = "file:" + self.wav; e["SILL_TEST_MIC_LOG"] = "1"
        elif sink: e["SILL_TEST_MIC_SINK"] = sink
        e.update(env or {})
        self.start = time.time()
        self.p = subprocess.Popen(["nice", "-n", "10", HOST, "--synthetic", "--pairing"], stdout=subprocess.PIPE,
                                  stderr=subprocess.STDOUT, env=e, start_new_session=True, text=True, bufsize=1)
        threading.Thread(target=self._read, daemon=True).start()
        self.port = None
        for _ in range(100):
            time.sleep(0.1)
            r = subprocess.run(["lsof", "-nP", "-a", "-p", str(self.p.pid), "-iTCP", "-sTCP:LISTEN"], capture_output=True, text=True)
            if re.findall(r"(\*|\[::\]|0\.0\.0\.0):(\d+) \(LISTEN\)", r.stdout): self.stop(); raise SystemExit(f"{label}: a listener not on loopback")
            ports = re.findall(r"127\.0\.0\.1:(\d+) \(LISTEN\)", r.stdout)
            if ports: self.port = ports[0]; break
        if self.port is None: self.stop(); raise SystemExit(f"{label}: no listening port")

    def _read(self):
        for line in self.p.stdout: self.lines.append((time.time(), line.rstrip("\n")))

    def stop(self):
        if self.p.poll() is None:
            os.killpg(self.p.pid, signal.SIGTERM)
            try: self.p.wait(3)
            except subprocess.TimeoutExpired: os.killpg(self.p.pid, signal.SIGKILL); self.p.wait()
        with open(os.path.join(self.out, self.label + ".host.log"), "w") as f:
            for t, l in self.lines: f.write(f"{t - self.start:8.3f} {l}\n")

    def all(self, pattern):
        rx = re.compile(pattern)
        return [l for _, l in self.lines if rx.search(l)]

    def count(self, key):
        """A Stats key summed over every [1s] line."""
        return sum(int(m) for _, l in self.lines for m in re.findall(rf"(?:^|\s){re.escape(key)} (\d+)", l) if l.startswith("[1s]"))

    def next_tick(self, timeout=2.5):
        n = len(self.lines); end = time.time() + timeout
        while time.time() < end:
            if any(l.startswith("[1s]") for _, l in self.lines[n:]): return
            time.sleep(0.1)

    def link(self, after=0):
        for _ in range(60):
            links = [m.group(1) for _, l in self.lines[after:] for m in [re.search(r"(sill://pair\S+)", l)] if m]
            if links: return links[-1]
            time.sleep(0.1)
        return None

    def sample0(self):
        for _, l in self.lines:
            m = re.search(r"Test microphone: the file's sample 0 is at ([\d.]+) \(wall clock\)", l)
            if m: return float(m.group(1))
        return None


def client(host, label, seconds, *args, identity=None, background=False):
    cmd = [sys.executable, "-I", CLIENT, host.port, str(seconds), "none", *args, *([f"--identity={identity}"] if identity else [])]
    log = os.path.join(host.out, f"{host.label}-{label}.client.log")
    if background:
        f = open(log, "w")
        return subprocess.Popen(cmd, stdout=f, stderr=subprocess.STDOUT, env={**os.environ, **BASE_ENV}), log
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=seconds + 30, env={**os.environ, **BASE_ENV})
    text = r.stdout + r.stderr + f"\nEXIT {r.returncode}\n"
    open(log, "w").write(text)
    return text, r.returncode


def finished(proc_log):
    p, log = proc_log
    try: p.wait(90)
    except subprocess.TimeoutExpired: p.kill(); p.wait()
    return open(log).read() + f"\nEXIT {p.returncode}\n"


def paired(host, out, name):
    """A client paired by the host's newest link: its identity folder."""
    ident = os.path.join(out, f"{host.label}.{name}.id")
    link = host.link(after=getattr(host, "paired_lines", 0))
    if link is None: verdict(False, f"{host.label}: the host printed no pairing link"); return None
    host.paired_lines = len(host.lines)
    text, _ = client(host, f"pair-{name}", 1, f"--pair-url={link}", f"--device={name}", identity=ident)
    if "PAIR ok" not in text: verdict(False, f"{host.label}: pairing {name} failed: {text[-300:]}"); return None
    time.sleep(0.5)    # the host prints its next link
    return ident


def named(device):
    """A paired device as the host's lines name it: its name, then its model in parentheses ("ipad (sillclient)")."""
    return re.escape(device) + r"(?: \(sillclient\))?"


def states(text):
    """The client's microphone states in order, without repeats: [(seconds, state, device)]."""
    return [(float(t), s, d) for t, s, d in re.findall(r"mic state at ([\d.]+)s: (\S+)(?: device=(\S+))?", text)]


def spans(text):
    """Each epoch's recording as the client sent it: (its sample 0's wall time, the end of its last message)."""
    out = []
    starts = [float(w) for w in re.findall(r"mic epoch \d+: sample 0 at ([\d.]+) \(wall\)", text)]
    counts = [int(n) for n in re.findall(r"mic epoch \d+ stopped at [\d.]+s after (\d+) messages", text)]
    total = re.search(r"MIC sent (\d+) messages", text)
    for i, w0 in enumerate(starts):
        n = counts[i] if i < len(counts) else (int(total.group(1)) - sum(counts) if total else 0)
        out.append((w0, w0 + n * 0.1))
    return out


def analyze(host, tools, spans_):
    s0 = host.sample0()
    if s0 is None or not spans_: return None, "no file or no recording"
    arg = ",".join(f"{a:.6f}:{b:.6f}" for a, b in spans_ if b - a >= 1.5)
    if not arg: return None, "no recording long enough"
    r = subprocess.run([os.path.join(tools, "analyze"), host.wav, f"{s0:.6f}", arg], capture_output=True, text=True, timeout=120)
    open(os.path.join(host.out, host.label + ".clicks.txt"), "w").write(r.stdout + r.stderr)
    m = re.search(r"CLICKS found (\d+) of (\d+); delay median ([\d.na]+) ms, min ([\d.na-]+), max ([\d.na-]+); after the first 2 s of each span "
                  r"within ±([\d.na]+) ms of the median; zero runs over 2 ms between the first and last click: (\d+)", r.stdout)
    if not m: return None, r.stdout[-300:]
    found, expected = int(m.group(1)), int(m.group(2))
    return {"found": found, "expected": expected, "median": float(m.group(3)), "spread": float(m.group(6)) if m.group(6) != "nan" else 1e9,
            "zeros": int(m.group(7))}, m.group(0)


def case_nohook(out, tools):
    print("== nohook (M1): a host without SILL_TEST_MIC_SINK takes no microphone and says nothing of one", flush=True)
    h = Host(out, "nohook", sink=None)
    try:
        ident = paired(h, out, "ipad")
        if not ident: return
        text, code = client(h, "session", 6, "--tls", "--stats", "--device=ipad", f"--mic={tools}/tone.packets@1", identity=ident)
        verdict(code == 0 and "microphone=" not in text, "its window lists say nothing of the microphone")
        verdict(" mic=-" in text and " mic=idle" not in text, "its kind 16 says nothing of it (mic=-)")
        h.next_tick()
        verdict(not h.all(r"Microphone") and not h.all(r"mic\."), "no Microphone line, no mic. count: the kind 48 it was sent is ignored")
    finally:
        h.stop()


def case_live(out, tools):
    print("== live (M2, M9): a paired device's tone through the file sink; its end", flush=True)
    h = Host(out, "live")
    try:
        ident = paired(h, out, "ipad")
        if not ident: return
        text, code = client(h, "session", 16, "--tls", "--stats", "--device=ipad", f"--mic={tools}/tone.packets@1", "--mic-end@13",
                            "--expect-mic=idle", identity=ident)
        st = [s for _, s, _ in states(text)]
        verdict(code == 0 and st[:3] == ["idle", "inUse", "idle"], f"kind 16: idle, inUse once it offers (an app always uses the test sink), idle after its end: {st}")
        verdict("microphone=1" in text, "its window lists say microphone=1")
        verdict(bool(h.all(r"^Microphone: " + named("ipad") + r" is Sill Microphone’s input now \(AAC-ELD 48 kHz mono, 64 kbps\)\.$")), "the live line")
        verdict(bool(h.all(r"^Microphone: " + named("ipad") + r" stopped\.$")), "the end's line")
        time.sleep(1.2); h.next_tick()
        sp = spans(text)
        res, line = analyze(h, tools, sp)
        verdict(res is not None and res["found"] == res["expected"] and res["expected"] >= 9, f"every click sent was heard: {line}")
        verdict(res is not None and 90 <= res["median"] <= 200, f"the delay from capture to Sill Microphone, 90 to 200 ms: {res and res['median']} ms")
        verdict(res is not None and res["spread"] <= 5, f"steady after the first 2 s, within ±5 ms: ±{res and res['spread']} ms")
        verdict(res is not None and res["zeros"] == 0, f"no gap inside the sound: {res and res['zeros']} runs of silence")
        late = h.count("mic.late"); taken = h.count("mic.in")
        verdict(late == 0 and taken >= 100, f"the playout placed every packet message in time: {taken} taken, {late} late")
        jumps = h.all(r"^Test microphone: jump")
        verdict(not jumps, f"no jump: {jumps[:2]}")
    finally:
        h.stop()


def case_two(out, tools):
    print("== two (M3): a second device's claim takes Sill Microphone over; the first is told", flush=True)
    h = Host(out, "two")
    try:
        a = paired(h, out, "ipad"); b = paired(h, out, "iphone")
        if not (a and b): return
        pa = client(h, "ipad", 15, "--tls", "--stats", "--device=ipad", f"--mic={tools}/tone.packets@1", identity=a, background=True)
        time.sleep(0.5)
        pb = client(h, "iphone", 14, "--tls", "--stats", "--device=iphone", f"--mic={tools}/tone.packets@6", identity=b, background=True)
        ta, tb = finished(pa), finished(pb)
        sa, sb = states(ta), states(tb)
        verdict([s for _, s, _ in sa][:2] == ["idle", "inUse"] and any(s == "another" and d == "iphone" for _, s, d in sa),
                f"the first: idle, inUse, then another naming the second: {[(s, d) for _, s, d in sa]}")
        verdict(any(s == "another" and d == "ipad" for _, s, d in sb) and any(s == "inUse" for _, s, _ in sb),
                f"the second: another naming the first, then inUse after its claim: {[(s, d) for _, s, d in sb]}")
        verdict(len(h.all(r"^Microphone: " + named("iphone") + " took over from " + named("ipad") + r"\.$")) == 1, "one took-over line")
        res, line = analyze(h, tools, spans(ta) + spans(tb))
        verdict(res is not None and res["found"] >= res["expected"] - 2 and res["found"] >= 8, f"both devices' clicks heard, each in its turn: {line}")
    finally:
        h.stop()


def case_lock(out, tools):
    print("== lock (M4): locked at 5 s, unlocked at 9 s: nothing taken while locked, the same device again after", flush=True)
    lock = os.path.join(out, "lock.file"); open(lock, "w").write("0")
    h = Host(out, "lock", env={"SILL_TEST_LOCKED_FILE": lock})
    try:
        ident = paired(h, out, "ipad")
        if not ident: return
        p = client(h, "session", 18, "--tls", "--stats", "--device=ipad", f"--mic={tools}/tone.packets@1", identity=ident, background=True)
        start = time.time()
        time.sleep(max(0, start + 5.5 - time.time())); open(lock, "w").write("1"); locked_at = time.time()
        time.sleep(max(0, start + 9.5 - time.time())); open(lock, "w").write("0"); unlocked_at = time.time()
        text = finished(p)
        st = [s for _, s, _ in states(text)]
        verdict(st[:4] == ["idle", "inUse", "none", "inUse"], f"kind 16: inUse, nothing while locked, inUse after the unlock: {st}")
        verdict("locked=1" in text, "the list said locked")
        sp = spans(text)
        verdict(len(sp) == 2, f"two recordings, one each side of the lock: {[(round(a, 1), round(b - a, 1)) for a, b in sp]}")
        s0 = h.sample0()
        res, line = analyze(h, tools, sp)
        verdict(res is not None and res["found"] >= res["expected"] - 1, f"the clicks of both recordings heard: {line}")
        # Nothing heard while locked: the clicks the client stamped in the lock's seconds were never sent, and nothing
        # it sent before reached the file after the gate read locked.
        clicks = open(os.path.join(out, "lock.clicks.txt")).read() if os.path.exists(os.path.join(out, "lock.clicks.txt")) else ""
        heard = [int(x) for x in re.findall(r"click (\d+): heard", clicks)]
        verdict(not [c for c in heard if locked_at + 0.6 < c < unlocked_at + 2], f"no click heard between the lock and the unlock's settle: {heard}")
        verdict(h.count("mic.in") > 0, "packets were taken before and after")
    finally:
        h.stop()


def case_unpaired(out, tools):
    print("== unpaired: Require pairing off lets an unpaired device in, never its microphone", flush=True)
    h = Host(out, "unpaired", env={"SILL_TEST_REQUIRE_PAIRING": "0"})
    try:
        ident = os.path.join(out, "unpaired.guest.id")
        text, code = client(h, "session", 6, "--tls", "--pin=none", "--stats", "--device=guest", f"--mic={tools}/tone.packets@1",
                            "--expect-mic=unpaired", identity=ident)
        verdict(code == 0 and "EXPECT-MIC ok" in text, "kind 16 says unpaired")
        verdict("paired=0" in text, "the session is unpaired (kind 16's sessionPaired)")
        h.next_tick()
        verdict(bool(h.all(r"^Microphone: refused from .*: it isn’t paired with this Mac\.$")), "one refusal line")
        verdict(h.count("mic.in") == 0 and h.sample0() is None, "nothing taken, nothing in Sill Microphone")
    finally:
        h.stop()


def case_hostile(out, tools):
    print("== hostile (M6): too much sound a second, malformed messages, too many recordings", flush=True)
    h = Host(out, "hostile")
    try:
        a = paired(h, out, "ipad"); b = paired(h, out, "iphone")
        if not (a and b): return
        pa = client(h, "flood", 12, "--tls", "--stats", "--device=ipad", f"--mic={tools}/tone.packets@1", "--mic-flood@5",
                    "--raw48=@2", "--raw48=02ffff@2.2", "--raw48=0301@2.4", "--raw48=05aa@2.6", "--raw48=017b22636f646563223a226f707573227d@2.8",
                    identity=a, background=True)
        pb = client(h, "formats", 10, "--tls", "--stats", "--device=iphone", "--mic-formats=8@3", identity=b, background=True)
        ta, tb = finished(pa), finished(pb)
        verdict(any(s == "refused" for _, s, _ in states(ta)), f"the flooding device: refused: {[s for _, s, _ in states(ta)]}")
        verdict(bool(h.all(r"^Microphone: " + named("ipad") + r" sent [\d.]+ s of sound in a second: refused for a minute\.$")), "its line")
        h.next_tick()
        verdict(h.count("mic.dropped.malformed") >= 4, f"the malformed kind 48s dropped: {h.count('mic.dropped.malformed')}")
        verdict(bool(h.all(r"^Microphone: " + named("iphone") + r" started more than 6 recordings in a minute: refused for a minute\.$")),
                "the device starting 8 recordings at once: refused, its line")
        verdict(h.p.poll() is None, "the host still runs")
    finally:
        h.stop()


def case_setup(out, tools):
    print("== setup (M10): Sill Microphone not set up, then set up; no app, then one", flush=True)
    setup = os.path.join(out, "setup.state"); open(setup, "w").write("missing")
    app = os.path.join(out, "setup.app"); open(app, "w").write("0")
    h = Host(out, "setup", env={"SILL_TEST_MIC_SETUP": setup, "SILL_TEST_MIC_APP": app})
    try:
        ident = paired(h, out, "ipad")
        if not ident: return
        p = client(h, "session", 12, "--tls", "--stats", "--device=ipad", f"--mic={tools}/tone.packets@1", identity=ident, background=True)
        start = time.time()
        time.sleep(max(0, start + 3 - time.time())); open(setup, "w").write("ok")
        time.sleep(max(0, start + 6 - time.time())); open(app, "w").write("1")
        text = finished(p)
        st = [s for _, s, _ in states(text)]
        verdict(st[:3] == ["notReady", "idle", "inUse"], f"kind 16: notReady, idle once set up, inUse once an app uses it: {st}")
        verdict("microphone=0" in text and "microphone=1" in text, "the list said 0, then 1")
        verdict(h.count("mic.in") > 0 and len(spans(text)) == 1, "the device recorded only once an app used it")
    finally:
        h.stop()


CASES = {"nohook": case_nohook, "live": case_live, "two": case_two, "lock": case_lock, "unpaired": case_unpaired,
         "hostile": case_hostile, "setup": case_setup}

if __name__ == "__main__":
    if len(sys.argv) < 2: raise SystemExit(__doc__)
    out = os.path.abspath(sys.argv[1]); os.makedirs(out, exist_ok=True)
    which = sys.argv[2] if len(sys.argv) > 2 else "all"
    tools = os.environ.get("MIC_TOOLS", os.path.join(out, "tools"))
    if not os.path.exists(os.path.join(tools, "tone.packets")): raise SystemExit(f"no tools in {tools}: Scripts/mic-check/build.sh {tools}")
    if not os.path.exists(HOST): raise SystemExit(f"no {HOST}: swift build -c release")
    for name, case in CASES.items():
        if which in (name, "all"): case(out, tools)
    failed = [w for ok, w in verdicts if not ok]
    print(f"{len(verdicts) - len(failed)} of {len(verdicts)} verdicts ok" + ("" if not failed else f"; FAILED: {failed}"))
    sys.exit(1 if failed else 0)
