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
- sleep: Noah's test at 03:56 (2026-11-12): the lid closed, two monitors, locked, a device on the Desktop; the screens
  go to sleep (macOS's display sleep: both monitors online and asleep, `screens asleep`), the Desktop is asked for again
  as after the capture's stop, later they wake: nothing made, one "asleep, not gone" line, nothing declared after the
  connect (the device is idle).
- goneasleep: the only monitor unplugged while the screens sleep: nothing made while they sleep (one line), made two
  seconds after they wake.
- dropoff: a Mac mini whose monitor drops off as the screens sleep and is back 1.2 s after they wake: nothing made.
- after: a device connects to a closed-lid Mac whose monitors sleep: nothing made (a Mac's connect wakes them).
- nodevice: no device; the screens sleep, a monitor goes, they wake: no Headless display line at all.
- lidclose: the lid closed with nothing attached (#61), macOS having said the screens slept while its stand-in draws: a
  display working is awake, so Sill's display is made as before.
- tapwake: the only monitor gone while the screens sleep, unlocked; a tap on the device is a person's activity, which
  wakes them on a Mac: made two seconds after it, though the file still says asleep.
Phase 2a (virtual-desktop-2a, 2026-11-18; Noah: "should default to resolution and refresh of client device"):
- size: a screenless Mac, locked (#298); an iPad mini's viewport (1133×744 at 30 Hz, a rate the software encoder can
  show held) asks for the Desktop: made at 1218×800 at 30 Hz for it; an iPhone at 60 joins: the Desktop stays at 30.
- nosize: a client that sends no viewport: #200's 1920×1080 at 60, and the line says no device's screen is known.
- guard: the guard for #380 (SILL_TEST_MAKE_GUARD, a folder of the test's own): the last run left a marker with one
  stop kept: two in a row, it holds; the Desktop with no real screen makes nothing, one line; the marker taken.
- guardok: one stop kept and no marker: made as before, the marker gone, the count back to 0.
- offconsole: Sill's display made on a screenless Mac, then another user on the screen: removed at once (it would be
  their displays); back on the console with no screen: made again after the return's two seconds.
- kept: Sill's display made, then the device leaves: kept with no device connected (Watch.release keeps it while no real
  screen works, which Settings' words say); a monitor back with nobody connected: gone two seconds after.
- switchoff: its switch off (--no-headless-display; Sill.app's Settings › Virtual Display): a screenless, locked Mac's
  Desktop, asked twice, makes nothing, waits for nothing and says why once; the Desktop streams as before.
Each host lives under 40 s and is killed at the end.

    Scripts/headless-check/live.py OUT [switch|view|screenless|flicker|waiting|sleep|goneasleep|dropoff|after|nodevice|
                                        lidclose|tapwake|size|nosize|guard|guardok|offconsole|kept|
                                        switchoff|all]

Needs .build/release/SillHost (swift build -c release), or another build's in HEADLESS_CHECK_HOST. Exits 1 when a verdict
fails."""
import os, re, signal, subprocess, sys, threading, time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
HOST = os.environ.get("HEADLESS_CHECK_HOST") or os.path.join(ROOT, ".build/release/SillHost")   # another build's CLI to compare
CLIENT = os.path.join(ROOT, "Scripts/sillclient.py")
BASE_ENV = {"SILL_TEST_LOOPBACK": "1", "SILL_TEST_SOFTWARE_ENCODER": "1", "SILL_TEST_NO_ROUTER": "1", "SILL_TEST_NO_SCREEN": "1",
            "SILL_TEST_LOCK_IGNORE_MAC": "1"}
TWO = "real\nreal\nlid closed\n"
STANDIN = "standin\nlid closed\n"
ONE = "real\nlid closed\n"
TWO_ASLEEP = "real asleep\nreal asleep\nlid closed\nscreens asleep\n"   # macOS's display sleep: online, asleep

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
ASLEEP_NOT_GONE = r"^Headless display: the (\d+ screens are|screen is) asleep, not gone; none made"
WAITS_FOR_WAKE = r"^Headless display: no real screen, and the screens are asleep; none made until they wake\.$"
STREAMING = r"^Streaming a synthetic test pattern"


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


def dry_wakes(h, after=0.0, before=1e9):
    """The seconds whose stats line counts a declaration a test host only counts (disp.wakeDry)."""
    return h.all(r"\[1s\].*disp\.wakeDry", after, before)


def run_sleep(out):
    print("== sleep: 03:56, the screens asleep with the lid closed and a device on the Desktop; the Desktop asked again", flush=True)
    d, l = files(out, "sleep", TWO, "1")
    h = Host(out, "sleep", {"SILL_TEST_HEADLESS": d, "SILL_TEST_LOCKED_FILE": l})
    # The capture's stop (the host selects nothing) and the device's own request for the Desktop at once, as at 03:56:20.
    c = client(h, out, "sleep-c1", 22, ["desktop", "--pick=none@5.0", "--pick=desktop@5.05"], start=1.0)
    h.at(5.5); write(d, TWO_ASLEEP)              # the lock screen's idle timer: both monitors asleep, the screens asleep
    asked = h.wait_for(STREAMING, 5.6, 9.5)      # the Desktop started again, the screens asleep
    h.at(14.0); write(d, TWO)                    # a key at the Mac, or a tap on the device: awake, the monitors working
    c.join(); h.at(25.0); h.stop()
    verdict(h.first(r"^Locked: this Mac's screen is locked")[0] is not None, "locked from the start, on the console")
    verdict(asked is not None, f"the Desktop asked again while the screens slept: streaming again at {asked} s")
    lines = h.all(ASLEEP_NOT_GONE)
    verdict(len(lines) == 1 and asked is not None and lines[0] >= 5.5, f"one 'asleep, not gone' line, at the request: {lines}")
    verdict(not h.all(LOOKING) and not h.all(CREATED) and not h.all(REMOVED),
            f"nothing made or removed, no wait for one: looking {h.all(LOOKING)}, created {h.all(CREATED)}, removed {h.all(REMOVED)}")
    connect = dry_wakes(h, 0, 4.0)
    verdict(len(connect) >= 1 and not dry_wakes(h, 4.0), f"a declaration counted at the connect ({connect}) and none after (idle: {dry_wakes(h, 4.0)})")


def run_goneasleep(out):
    print("== goneasleep: the only monitor unplugged while the screens sleep; they wake with no monitor", flush=True)
    d, l = files(out, "goneasleep", ONE, "1")
    h = Host(out, "goneasleep", {"SILL_TEST_HEADLESS": d, "SILL_TEST_LOCKED_FILE": l})
    c = client(h, out, "goneasleep-c1", 22, ["desktop", "--pick=none@6.0", "--pick=desktop@6.05"], start=1.0)
    h.at(4.0); write(d, "real asleep\nlid closed\nscreens asleep\n")
    h.at(5.0); write(d, "standin asleep\nlid closed\nscreens asleep\n")   # unplugged while asleep: the stand-in alone, dark
    h.at(12.0); write(d, STANDIN)                # the screens awake (a person's tap on a real Mac), still no monitor
    woke = 12.0
    c.join(); h.at(25.0); h.stop()
    waits = h.all(WAITS_FOR_WAKE)
    verdict(len(waits) == 1 and 6.5 <= waits[0] < woke, f"the Desktop asked while they slept: one 'none made until they wake' line: {waits}")
    created = h.all(CREATED)
    verdict(not [t for t in created if t < woke], f"nothing made while the screens slept: created {created}")
    looked = h.first(LOOKING, woke)[0]
    verdict(looked is not None and looked - woke < 0.6, f"the wake asked again: 'looking again' at {looked} s")
    verdict(len(created) == 1 and 1.9 <= created[0] - woke <= 2.7, f"made two seconds after the wake (12 s): {created}")
    verdict(not h.all(REMOVED), f"kept: removed {h.all(REMOVED)}")


def run_dropoff(out):
    print("== dropoff: a Mac mini's monitor drops off as the screens sleep, back 1.2 s after they wake", flush=True)
    d, l = files(out, "dropoff", "real\n", "0")
    h = Host(out, "dropoff", {"SILL_TEST_HEADLESS": d, "SILL_TEST_LOCKED_FILE": l})
    c = client(h, out, "dropoff-c1", 20, ["desktop", "--pick=none@5.0", "--pick=desktop@5.05"], start=1.0)
    h.at(4.0); write(d, "screens asleep\n")      # asleep, and its monitor gone from the list
    h.at(10.0); write(d, "")                     # awake, nothing online yet
    h.at(11.2); write(d, "real\n")               # the monitor back
    c.join(); h.at(23.0); h.stop()
    waits = h.all(WAITS_FOR_WAKE)
    verdict(len(waits) == 1 and waits[0] < 10.0, f"asked while asleep: one 'none made until they wake' line: {waits}")
    looked, none = h.first(LOOKING, 10.0)[0], h.first(NONE, 10.0)[0]
    verdict(looked is not None and none is not None and none > 11.2,
            f"the wake asked again and waited: 'looking again' at {looked}, 'none made' at {none} (the monitor back at 11.2)")
    verdict(not h.all(CREATED) and not h.all(REMOVED), f"nothing made or removed: {h.all(CREATED)}, {h.all(REMOVED)}")


def run_after(out):
    print("== after: a device connects to a closed-lid Mac whose monitors sleep", flush=True)
    d, l = files(out, "after", TWO_ASLEEP, "1")
    h = Host(out, "after", {"SILL_TEST_HEADLESS": d, "SILL_TEST_LOCKED_FILE": l})
    c = client(h, out, "after-c1", 10, ["desktop"], start=2.0)
    c.join(); h.at(14.0); h.stop()
    verdict(len(dry_wakes(h, 1.5, 5.0)) >= 1, f"the connect's declaration counted (a Mac's wakes the monitors): {dry_wakes(h, 1.5, 5.0)}")
    verdict(len(h.all(ASLEEP_NOT_GONE)) == 1, f"one 'asleep, not gone' line: {h.all(ASLEEP_NOT_GONE)}")
    verdict(not h.all(LOOKING) and not h.all(CREATED), f"nothing made, no wait: {h.all(LOOKING)}, {h.all(CREATED)}")


def run_nodevice(out):
    print("== nodevice: no device; the screens sleep, the monitors go, they wake, the monitors back", flush=True)
    d, l = files(out, "nodevice", TWO, "1")
    h = Host(out, "nodevice", {"SILL_TEST_HEADLESS": d, "SILL_TEST_LOCKED_FILE": l})
    h.at(3.0); write(d, TWO_ASLEEP)
    h.at(6.0); write(d, "standin asleep\nlid closed\nscreens asleep\n")
    h.at(9.0); write(d, STANDIN)
    h.at(12.0); write(d, TWO)
    h.at(15.0); h.stop()
    verdict(not h.all(r"^Headless display"), f"no Headless display line at all: {h.all(r'^Headless display')}")
    verdict(not h.all(r"^Client connected"), "no device connected")


def run_lidclose(out):
    print("== lidclose: the lid closed with nothing attached (#61), macOS saying the screens slept while its stand-in draws", flush=True)
    d, l = files(out, "lidclose", "standin\nlid closed\nscreens asleep\n", "1")
    h = Host(out, "lidclose", {"SILL_TEST_HEADLESS": d, "SILL_TEST_LOCKED_FILE": l})
    c = client(h, out, "lidclose-c1", 8, ["desktop"], start=1.0)
    c.join(); h.at(11.0); h.stop()
    looked, created = h.first(LOOKING)[0], h.all(CREATED)
    verdict(not h.all(WAITS_FOR_WAKE), f"a display working (the stand-in) is awake: no 'until they wake' line: {h.all(WAITS_FOR_WAKE)}")
    verdict(looked is not None and len(created) == 1 and 0.9 <= created[0] - looked <= 2.6,
            f"made as before, by two seconds after the Desktop asked (the connect's wake counts): looking at {looked}, created {created}")


def run_tapwake(out):
    print("== tapwake: the only monitor gone while the screens sleep, unlocked; a tap on the device is their wake", flush=True)
    d, l = files(out, "tapwake", ONE, "0")
    h = Host(out, "tapwake", {"SILL_TEST_HEADLESS": d, "SILL_TEST_LOCKED_FILE": l})
    c = client(h, out, "tapwake-c1", 18, ["desktop", "--pick=none@6.0", "--pick=desktop@6.05", "--tap=0.5,0.5@10.0"], start=1.0)
    h.at(4.0); write(d, "real asleep\nlid closed\nscreens asleep\n")
    h.at(5.0); write(d, "standin asleep\nlid closed\nscreens asleep\n")   # the file says asleep from here to the end
    c.join(); h.at(22.0); h.stop()
    waits = h.all(WAITS_FOR_WAKE)
    verdict(len(waits) == 1 and waits[0] < 10.5, f"the Desktop asked while they slept: one 'until they wake' line: {waits}")
    tap = dry_wakes(h, 10.5, 13.0)
    verdict(len(tap) >= 1, f"the tap's declaration counted (a Mac's wakes the screens): {tap}")
    created = h.all(CREATED)
    verdict(len(created) == 1 and 1.9 <= created[0] - 11.0 <= 3.0,
            f"the tap is the wake: made two seconds after it (about 11 s), the file still asleep: {created}")


# Phase 2a (virtual-desktop-2a, 2026-11-18): the display sized to the device that asked, its rate held, the guard for #380.
TEST_LINE = r"\(TEST ONLY: none made, SILL_TEST_HEADLESS\)"
GUARD_HELD = r"^Headless display: no real screen, but Sill stopped while making its displays 2 runs in a row"


def streaming_fps(h, after=0.0):
    """Each 'Streaming a synthetic test pattern … at W×H, N fps' line's rate, from `after` on."""
    rx = re.compile(r"^Streaming a synthetic test pattern.* at \d+×\d+, (\d+) fps")
    return [int(m.group(1)) for t, l in list(h.lines) if t - h.start >= after and (m := rx.search(l))]


def run_size(out):
    print("== size: a screenless Mac, locked (#298); an iPad mini's viewport at 30 Hz, then an iPhone at 60 joins", flush=True)
    d, l = files(out, "size", STANDIN, "1")
    h = Host(out, "size", {"SILL_TEST_HEADLESS": d, "SILL_TEST_LOCKED_FILE": l})
    ipad = '{"width":1133,"height":744,"fps":30}'
    iphone = '{"width":852,"height":393,"fps":60}'
    c1 = client(h, out, "size-c1", 16, ["desktop", "--hello=0.6.3", "--device=iPad mini", f"--raw9={ipad}@0.2"], start=1.0)
    c2 = client(h, out, "size-c2", 8, ["desktop", "--hello=0.6.3", "--device=iPhone", f"--raw9={iphone}@0.2"], start=8.0)
    c1.join(); c2.join(); h.at(19.0); h.stop()
    created = h.first(CREATED)
    verdict(created[1] is not None and created[1].startswith("Headless display: created 1218×800 pt @2× at 30 Hz ")
            and re.search(TEST_LINE + r" for iPad mini, its screen\.$", created[1]) is not None,
            f"made at the asking iPad mini's size, grown to 800, at its 30 Hz: {created[1]!r}")
    rates = streaming_fps(h, created[0] or 99)
    verdict(rates and all(r == 30 for r in rates), f"the Desktop's rate held to Sill's display's 30 Hz, the iPhone's 60 joining too: {rates}")
    verdict(len(h.all(CREATED)) == 1, f"one display for both: {h.all(CREATED)}")


def run_nosize(out):
    print("== nosize: a screenless Mac; a client that sends no viewport", flush=True)
    d, l = files(out, "nosize", STANDIN, "0")
    h = Host(out, "nosize", {"SILL_TEST_HEADLESS": d, "SILL_TEST_LOCKED_FILE": l})
    c = client(h, out, "nosize-c1", 8, ["desktop"], start=1.0)
    c.join(); h.at(11.0); h.stop()
    created = h.first(CREATED)[1]
    verdict(created == "Headless display: created 1920×1080 pt @2× at 60 Hz (TEST ONLY: none made, SILL_TEST_HEADLESS) at 1920×1080: no device's screen known yet.",
            f"no viewport: #200's 1920×1080 at 60, said so: {created!r}")


def run_guard(out):
    print("== guard: the last two runs ended while making a display (#380): none made by itself", flush=True)
    d, l = files(out, "guard", STANDIN, "1")
    g = os.path.join(out, "guard.dir")
    os.makedirs(g, exist_ok=True)
    write(os.path.join(g, "making-display"), "desktop 2026-11-18T11:06:40Z\n")
    write(os.path.join(g, "display-make-stops"), "1\n")
    h = Host(out, "guard", {"SILL_TEST_HEADLESS": d, "SILL_TEST_LOCKED_FILE": l, "SILL_TEST_MAKE_GUARD": g})
    c = client(h, out, "guard-c1", 8, ["desktop", "--pick=none@4.0", "--pick=desktop@4.05"], start=1.0)
    c.join(); h.at(11.0); h.stop()
    verdict(h.first(r"^Test guard: .*2 stops in a row: it holds\.$")[0] is not None, "the test's folder taken: two stops, it holds")
    launch = h.first(r"^Sill stopped while making a display last time")[1]
    verdict(launch == "Sill stopped while making a display last time (2 runs in a row: its Desktop display, 2026-11-18T11:06:40Z); "
                      "it makes none by itself until you choose Try Again in Settings › Virtual Display.", f"the launch's line: {launch!r}")
    held = h.all(GUARD_HELD)
    verdict(len(held) == 1, f"the Desktop with no real screen: one line, asked twice: {held}")
    verdict(not h.all(CREATED) and not h.all(LOOKING), f"nothing made, nothing waited for: {h.all(CREATED)} {h.all(LOOKING)}")
    verdict(not os.path.exists(os.path.join(g, "making-display")), "the marker taken at launch")
    stops = open(os.path.join(g, "display-make-stops")).read().strip()
    verdict(stops == "2", f"the count kept: {stops}")


def run_guardok(out):
    print("== guardok: one stop kept and no marker: made as before, inside the marker, and the count back to 0", flush=True)
    d, l = files(out, "guardok", STANDIN, "0")
    g = os.path.join(out, "guardok.dir")
    os.makedirs(g, exist_ok=True)
    for f in ("making-display",):
        try: os.remove(os.path.join(g, f))
        except FileNotFoundError: pass
    write(os.path.join(g, "display-make-stops"), "1\n")
    h = Host(out, "guardok", {"SILL_TEST_HEADLESS": d, "SILL_TEST_LOCKED_FILE": l, "SILL_TEST_MAKE_GUARD": g})
    c = client(h, out, "guardok-c1", 8, ["desktop"], start=1.0)
    c.join(); h.at(11.0); h.stop()
    verdict(h.first(r"^Test guard: .*1 stop in a row\.$")[0] is not None, "the test's folder taken: one stop, not holding")
    verdict(h.first(r"^Sill stopped while making")[0] is None, "no marker left: no launch line")
    verdict(len(h.all(CREATED)) == 1 and not h.all(GUARD_HELD), f"made as before: {h.all(CREATED)}")
    verdict(not os.path.exists(os.path.join(g, "making-display")), "the marker gone once it was made")
    stops = open(os.path.join(g, "display-make-stops")).read().strip()
    verdict(stops == "0", f"a display that came up resets the count: {stops}")


OFF_CONSOLE_REMOVED = r"^Headless display: this session is off the console; removed Sill's display"


def run_offconsole(out):
    print("== offconsole: Sill's display made on a screenless Mac, then another user on the screen, then back", flush=True)
    d, l = files(out, "offconsole", STANDIN, "1")
    h = Host(out, "offconsole", {"SILL_TEST_HEADLESS": d, "SILL_TEST_LOCKED_FILE": l})
    c = client(h, out, "offconsole-c1", 22, ["desktop"], start=1.0)
    made = h.wait_for(CREATED, 1.0, 8.0)
    h.at(9.0); write(l, "2")                     # another user on the screen
    h.at(15.0); write(l, "1")                    # back on the console, locked: the stand-in alone still
    c.join(); h.at(25.0); h.stop()
    verdict(made is not None, f"made on the screenless, locked Mac: {made}")
    gone = h.all(OFF_CONSOLE_REMOVED)
    verdict(len(gone) == 1 and 9.0 <= gone[0] <= 10.5, f"off console: removed at once, once: {gone}")
    verdict(not h.all(CREATED, 9.0, 15.0), f"none made off console: {h.all(CREATED, 9.0, 15.0)}")
    back = h.all(CREATED, 15.0)
    verdict(len(back) == 1 and 15.9 <= back[0] <= 18.5, f"back on the console with no screen: made again after the return's settle: {back}")



def run_kept(out):
    print("== kept: Sill's display made, the device leaves: kept with nobody connected; a monitor back: gone 2 s later", flush=True)
    d, l = files(out, "kept", STANDIN, "1")
    h = Host(out, "kept", {"SILL_TEST_HEADLESS": d, "SILL_TEST_LOCKED_FILE": l})
    c = client(h, out, "kept-c1", 5, ["desktop"], start=1.0)
    c.join()                                     # the device gone at about 6 s
    h.at(12.0); write(d, ONE)                    # a monitor back, nobody connected
    h.at(17.0); h.stop()
    made = h.all(CREATED)
    verdict(len(made) == 1 and made[0] < 6.0, f"made while the device showed the Desktop: {made}")
    left = h.first(r"^Client left", 5.0)[0]
    verdict(not h.all(REMOVED, 0.0, 12.0), f"kept after the device left ({left} s), nobody connected, no real screen: {h.all(REMOVED, 0.0, 12.0)}")
    gone = h.all(REMOVED)
    verdict(len(gone) == 1 and 13.9 <= gone[0] <= 15.0, f"a monitor back at 12 s with nobody connected: gone two seconds after: {gone}")


SWITCHED_OFF = r"^Headless display: no real screen, but Sill's display for a Mac with no screen is turned off; none made\.$"


def run_switchoff(out):
    print("== switchoff: its switch off (--no-headless-display); a screenless Mac, locked (#298), the Desktop asked twice", flush=True)
    d, l = files(out, "switchoff", STANDIN, "1")
    h = Host(out, "switchoff", {"SILL_TEST_HEADLESS": d, "SILL_TEST_LOCKED_FILE": l}, args=["--no-headless-display"])
    c = client(h, out, "switchoff-c1", 8, ["desktop", "--pick=none@4.0", "--pick=desktop@4.05"], start=1.0)
    c.join(); h.at(11.0); h.stop()
    off = h.all(SWITCHED_OFF)
    verdict(len(off) == 1, f"no real screen and the switch off: one line, asked twice: {off}")
    verdict(not h.all(CREATED) and not h.all(LOOKING), f"nothing made, nothing waited for: {h.all(CREATED)} {h.all(LOOKING)}")
    verdict(len(h.all(STREAMING, 1.0)) >= 2, f"the Desktop streams as before, at each ask: {h.all(STREAMING, 1.0)}")


def main():
    if len(sys.argv) < 2: sys.exit(__doc__)
    out = os.path.abspath(sys.argv[1]); os.makedirs(out, exist_ok=True)
    which = sys.argv[2] if len(sys.argv) > 2 else "all"
    if not os.path.exists(HOST): sys.exit(f"live.py: no {HOST} (swift build -c release)")
    for name, run in (("switch", run_switch), ("view", run_view), ("screenless", run_screenless), ("flicker", run_flicker),
                      ("waiting", run_waiting), ("sleep", run_sleep), ("goneasleep", run_goneasleep), ("dropoff", run_dropoff),
                      ("after", run_after), ("nodevice", run_nodevice), ("lidclose", run_lidclose), ("tapwake", run_tapwake),
                      ("size", run_size), ("nosize", run_nosize), ("guard", run_guard), ("guardok", run_guardok),
                      ("offconsole", run_offconsole), ("kept", run_kept), ("switchoff", run_switchoff)):
        if which in (name, "all"): run(out)
    bad = [w for ok, w in verdicts if not ok]
    print(f"{len(verdicts) - len(bad)} of {len(verdicts)} verdicts passed")
    sys.exit(1 if bad else 0)


main()
