#!/usr/bin/env python3
"""TEST ONLY (issues #61 and #298; Noah's test of 2026-11-12): when Sill's own Desktop display is made and when it
goes, on a test host. Each run starts one synthetic CLI host on loopback (the software encoder, no router, no screen:
never this Mac's screen, encoder or clipboard) whose displays are a file the run writes (SILL_TEST_HEADLESS: the
host's rules and looks run for real, and Sill's display is only said to be made and removed, never made), drives its
lock through the TEST ONLY lock hooks (SILL_TEST_LOCKED_FILE; SILL_TEST_LOCK_IGNORE_MAC), runs a test client that picks
the Desktop, and prints one verdict per rule:
- switch: tonight's account switch, through the placeholder: off console with two monitors, the stand-in alone, back
  on the console and locked, the monitors back a second later: nothing made.
- view: #340's off-console view: the Desktop asked for off console with the stand-in alone: nothing made.
- screenless: the stand-in alone and steady, the Mac locked (#298): made a second after the Desktop asked; a second
  connection makes no second one; a monitor back with the lid closed and a device connected: gone two seconds after.
- flicker: Sill's display made, a monitor flickering every half second for six seconds: kept; gone two seconds after
  it stays on.
- waiting: a monitor flickering while the Desktop waits for the display: decided once, by three seconds.
Each host lives under 40 s and is killed at the end.

    Scripts/headless-check/live.py OUT [switch|view|screenless|flicker|waiting|all]

Needs .build/release/SillHost (swift build -c release). Exits 1 when a verdict fails."""
import os, re, signal, subprocess, sys, threading, time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
HOST = os.path.join(ROOT, ".build/release/SillHost")
CLIENT = os.path.join(ROOT, "Scripts/sillclient.py")
BASE_ENV = {"SILL_TEST_LOOPBACK": "1", "SILL_TEST_SOFTWARE_ENCODER": "1", "SILL_TEST_NO_ROUTER": "1", "SILL_TEST_NO_SCREEN": "1",
            "SILL_TEST_LOCK_IGNORE_MAC": "1"}
TWO = "real\nreal\nlid closed\n"
STANDIN = "standin\nlid closed\n"
ONE = "real\nlid closed\n"

verdicts = []


def verdict(ok, what):
    verdicts.append((ok, what))
    print(("ok   " if ok else "FAIL ") + what, flush=True)


def write(path, text):
    with open(path + ".new", "w") as f: f.write(text)
    os.replace(path + ".new", path)          # whole, never half a list


class Host:
    """One synthetic host: its stdout's lines with the time each was read, its port."""
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
        d = self.start + t - time.time()
        if d > 0: time.sleep(d)

    def now(self): return time.time() - self.start

    def wait_for(self, pattern, after, limit):
        """Until a line matching `pattern` read `after` s or more after the start, at most until `limit`: its time."""
        while self.now() < limit:
            t, _ = self.first(pattern, after)
            if t is not None: return t
            time.sleep(0.02)
        return None

    def stop(self):
        if self.p.poll() is None:
            os.killpg(self.p.pid, signal.SIGTERM)
            try: self.p.wait(3)
            except subprocess.TimeoutExpired: os.killpg(self.p.pid, signal.SIGKILL); self.p.wait()
        self.reader.join(2)
        with open(os.path.join(self.out, self.label + ".host.log"), "w") as f:
            for t, l in self.lines: f.write(f"{t - self.start:8.3f} {l}\n")

    def first(self, pattern, after=0.0):
        rx = re.compile(pattern)
        for t, l in list(self.lines):
            if t - self.start >= after and rx.search(l): return t - self.start, l
        return None, None

    def all(self, pattern, after=0.0, before=1e9):
        rx = re.compile(pattern)
        return [round(t - self.start, 3) for t, l in list(self.lines) if after <= t - self.start < before and rx.search(l)]


def client(host, out, label, seconds, args, start):
    """A sillclient run `start` seconds after the host's start, in a thread; its output saved."""
    def run():
        host.at(start)
        r = subprocess.run([sys.executable, "-I", CLIENT, host.port, str(seconds), *args], capture_output=True, text=True,
                           timeout=seconds + 20, env={**os.environ, **BASE_ENV})
        open(os.path.join(out, label + ".client.log"), "w").write(r.stdout + r.stderr + f"\nEXIT {r.returncode}\n")
    th = threading.Thread(target=run); th.start()
    return th


CREATED, REMOVED = r"^Headless display: created ", r"^Headless display: a display is online again; removed"
LOOKING, NONE = r"^Headless display: no real screen; looking again", r"^Headless display: a real screen works again; none made"


def files(out, label, displays, lock):
    d, l = os.path.join(out, f"{label}.displays"), os.path.join(out, f"{label}.lock")
    write(d, displays); write(l, lock)
    return d, l


def run_switch(out):
    print("== switch: off console with two monitors, the stand-in alone, back and locked, the monitors back 1 s later", flush=True)
    d, l = files(out, "switch", TWO, "0")
    h = Host(out, "switch", {"SILL_TEST_HEADLESS": d, "SILL_TEST_LOCKED_FILE": l})
    c = client(h, out, "switch-c1", 24, ["desktop"], start=1.0)
    h.at(4.0); write(l, "2")                     # another user on the screen: the placeholder
    h.at(8.0); write(d, STANDIN)                 # back from the switch: macOS's stand-in alone
    h.at(9.0); write(l, "1")                     # this session back on the console, locked
    back = h.wait_for(r"^Locked: this Mac's screen is locked", 8.9, 14.0)
    if back is not None:
        h.at(back + 1.0); write(d, TWO)          # the monitors back a second after the return
    c.join(); h.at(26.0); h.stop()
    verdict(h.first(r"^Locked: another user", 3.9)[0] is not None, "off console at 4 s: the placeholder's line")
    verdict(back is not None, f"back on the console, locked: at {back} s")
    looked = h.first(LOOKING, (back or 99) - 0.05)[0]
    verdict(looked is not None and looked - back < 0.5, f"the Desktop asked at the return and waited: 'looking again' at {looked} s")
    none = h.first(NONE, (back or 99))[0]
    verdict(none is not None, f"the monitors came back before the second look: 'none made' at {none} s")
    verdict(not h.all(CREATED), f"nothing made: {h.all(CREATED)}")


def run_view(out):
    print("== view: #340's off-console view, the Desktop asked for off console with the stand-in alone", flush=True)
    d, l = files(out, "view", TWO, "0")
    h = Host(out, "view", {"SILL_TEST_HEADLESS": d, "SILL_TEST_LOCKED_FILE": l}, args=["--off-console-view"])
    c = client(h, out, "view-c1", 16, ["desktop", "--hello=0.6.1", "--off-console-view", "--pick=none@5.5", "--pick=desktop@6"], start=1.0)
    h.at(4.0); write(l, "2")
    h.at(5.0); write(d, STANDIN)
    c.join(); h.at(19.0); h.stop()
    viewed = h.first(r"own desktop and windows instead", 3.9)[0]
    verdict(viewed is not None, f"off console with the view at {viewed} s")
    verdict(len(h.all(r"^Streaming a synthetic test pattern", 6.5)) >= 1, "the Desktop asked again off console, and streamed")
    verdict(not h.all(r"^Headless display"), f"no Headless display line at all: {h.all(r'^Headless display')}")


def run_screenless(out):
    print("== screenless: the stand-in alone and steady, locked; a second connection; a monitor back with a device", flush=True)
    d, l = files(out, "screenless", STANDIN, "1")
    h = Host(out, "screenless", {"SILL_TEST_HEADLESS": d, "SILL_TEST_LOCKED_FILE": l})
    c1 = client(h, out, "screenless-c1", 4, ["desktop"], start=1.0)
    c1.join()
    c2 = client(h, out, "screenless-c2", 14, ["desktop"], start=7.0)
    h.at(14.0); write(d, ONE)                    # a monitor back, the lid closed, a device connected, locked
    c2.join(); h.at(23.0); h.stop()
    looked, created = h.first(LOOKING)[0], h.first(CREATED)[0]
    verdict(h.first(r"^Locked: this Mac's screen is locked")[0] is not None, "locked from the start (#298's Mac)")
    verdict(looked is not None and created is not None and 0.9 <= created - looked <= 1.5,
            f"made a second after the Desktop asked: looking at {looked}, created at {created}")
    verdict(len(h.all(CREATED)) == 1, f"one display for both connections: {h.all(CREATED)}")
    removed = h.all(REMOVED)
    verdict(len(removed) == 1 and 1.9 <= removed[0] - 14.0 <= 2.6, f"the monitor back at 14 s: gone at {removed} (two seconds after)")
    verdict(len(h.all(r"^Streaming a synthetic test pattern", 14.0)) >= 1, "the Desktop moved off it (restarted) when it went")


def run_flicker(out):
    print("== flicker: Sill's display made, a monitor flickering 6 s, then staying", flush=True)
    d, l = files(out, "flicker", STANDIN, "0")
    h = Host(out, "flicker", {"SILL_TEST_HEADLESS": d, "SILL_TEST_LOCKED_FILE": l})
    c = client(h, out, "flicker-c1", 20, ["desktop"], start=1.0)
    for k in range(12):
        h.at(6.0 + 0.5 * k); write(d, ONE if k % 2 == 0 else STANDIN)
    h.at(12.0); write(d, ONE)
    c.join(); h.at(23.0); h.stop()
    created, removed = h.all(CREATED), h.all(REMOVED)
    verdict(len(created) == 1, f"made once: {created}")
    verdict(len(removed) == 1 and 13.9 <= removed[0] <= 14.7, f"kept through the flicker, gone two seconds after it stayed (12 s): {removed}")


def run_waiting(out):
    print("== waiting: a monitor flickering while the Desktop waits for the display", flush=True)
    d, l = files(out, "waiting", STANDIN, "0")
    h = Host(out, "waiting", {"SILL_TEST_HEADLESS": d, "SILL_TEST_LOCKED_FILE": l})
    c = client(h, out, "waiting-c1", 12, ["desktop"], start=1.0)
    k = 0
    while h.now() < 9.0:
        h.at(1.2 + 0.5 * k); write(d, ONE if k % 2 == 0 else STANDIN); k += 1
    write(d, STANDIN)
    c.join(); h.at(15.0); h.stop()
    looked, created = h.first(LOOKING)[0], h.all(CREATED)
    verdict(looked is not None, f"the Desktop waited: 'looking again' at {looked}")
    verdict(len(created) <= 1 and all(t - looked <= 3.3 for t in created), f"decided once, by three seconds: created {created}")
    verdict(not h.all(REMOVED), f"nothing made and removed in a loop: removed {h.all(REMOVED)}")


def main():
    if len(sys.argv) < 2: sys.exit(__doc__)
    out = os.path.abspath(sys.argv[1]); os.makedirs(out, exist_ok=True)
    which = sys.argv[2] if len(sys.argv) > 2 else "all"
    if not os.path.exists(HOST): sys.exit(f"live.py: no {HOST} (swift build -c release)")
    for name, run in (("switch", run_switch), ("view", run_view), ("screenless", run_screenless), ("flicker", run_flicker),
                      ("waiting", run_waiting)):
        if which in (name, "all"): run(out)
    bad = [w for ok, w in verdicts if not ok]
    print(f"{len(verdicts) - len(bad)} of {len(verdicts)} verdicts passed")
    sys.exit(1 if bad else 0)


main()
