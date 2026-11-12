#!/usr/bin/env python3
"""TEST ONLY (docs/virtual-desktop-plan.md, phase 1's live gate): the Desktop's stops on a test host, measured.
One synthetic CLI host on loopback (the software encoder, no router, no screen: never this Mac's screen,
displays, encoder or pointer) lists SILL_TEST_DISPLAYS' three stops in place of this Mac's: the main one,
"Built-in Retina Display", 1512x982 @2 at 120 Hz at the origin; "DELL U2723QE", 2560x1440 @1 at 60 Hz to
its right; "LG HDR 4K", 1920x1080 @2 at 30 Hz to its left (30, not 60: the software encoder streams 60 at
most, so a 60 Hz stop would not show the stop's rate at work). Test clients (sillclient.py) step it with
kind 47, tap it (the dry run's log, SILL_TEST_INPUT_LOG, shows where each tap lands) and read its window
lists; the lock is the test's file (SILL_TEST_LOCKED_FILE, with SILL_TEST_LOCK_IGNORE_MAC so this Mac's own
lock never counts). One verdict per rule. A second host without the stops checks that nothing changes there.
Each host is killed at the end; nothing is posted, warped or captured.

    Scripts/desktop-check/live.py OUT

Needs .build/release/SillHost. Exits 1 when a verdict fails."""
import os, re, signal, subprocess, sys, threading, time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
HOST = os.path.join(ROOT, ".build/release/SillHost")
CLIENT = os.path.join(ROOT, "Scripts/sillclient.py")
BASE_ENV = {"SILL_TEST_LOOPBACK": "1", "SILL_TEST_SOFTWARE_ENCODER": "1", "SILL_TEST_NO_ROUTER": "1", "SILL_TEST_NO_SCREEN": "1",
            "SILL_TEST_LOCK_IGNORE_MAC": "1", "SILL_TEST_INPUT_LOG": "1"}
STOPS = "Built-in Retina Display:1512x982@2:120:0,0;DELL U2723QE:2560x1440@1:60:1512,0;LG HDR 4K:1920x1080@2:30:-1920,-200"
NAMES = '["Built-in Retina Display", "DELL U2723QE", "LG HDR 4K"]'
verdicts = []


def verdict(ok, what):
    verdicts.append((ok, what))
    print(("ok   " if ok else "FAIL ") + what, flush=True)


class Host:
    """One synthetic host: its output's lines with the time each was read, and its port (loopback only)."""
    def __init__(self, out, label, env):
        self.lines, self.out, self.label = [], out, label
        e = dict(os.environ); e.update(BASE_ENV); e.update(env)
        self.start = time.time()
        self.p = subprocess.Popen(["nice", "-n", "10", HOST, "--synthetic"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
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
        for line in self.p.stdout: self.lines.append((time.time(), line.rstrip("\n")))

    def at(self, t):
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

    def all(self, pattern, after=0.0, before=1e9):
        rx = re.compile(pattern)
        return [(t - self.start, l) for t, l in self.lines if after <= t - self.start < before and rx.search(l)]


def client(host, out, label, seconds, args, start):
    """A sillclient run `start` seconds after the host's start, in a thread; its output saved and returned."""
    result = {}
    def run():
        host.at(start)
        r = subprocess.run([sys.executable, "-I", CLIENT, host.port, str(seconds), *args], capture_output=True, text=True,
                           timeout=seconds + 30, env={**os.environ, **BASE_ENV})
        result["out"] = r.stdout + r.stderr; result["exit"] = r.returncode
        open(os.path.join(out, label + ".client.log"), "w").write(r.stdout + r.stderr + f"\nEXIT {r.returncode}\n")
    th = threading.Thread(target=run); th.start()
    return th, result


def lists(text):
    """A client's window lists: [(desktopDisplays, desktopDisplay, names, locked)] in order."""
    out = []
    for l in text.splitlines():
        if not l.strip().startswith("windowList:"): continue
        n = re.search(r"desktopDisplays=(\d+)", l); d = re.search(r"desktopDisplay=(\d+)", l); m = re.search(r"names=(\[.*\])", l)
        out.append((int(n.group(1)) if n else None, int(d.group(1)) if d else None, m.group(1) if m else None, "locked=1" in l))
    return out


def lands(host, after, before):
    """Where the dry run's left presses landed between two times: [(x, y)]."""
    return [tuple(int(v) for v in m.groups()) for _, l in host.all(r"Test input: left mouse down", after, before)
            for m in [re.search(r"at (-?\d+),(-?\d+)", l)] if m]


def streams(host, after, before):
    """The Desktop's starts between two times: [(which stop's words, size, fps)]."""
    out = []
    for _, l in host.all(r"^Streaming a synthetic test pattern", after, before):
        m = re.search(r"of display (\d) of 3 \(([^)]*)\).* at (\d+)×(\d+), (\d+) fps", l)
        if m: out.append((int(m.group(1)), m.group(2), f"{m.group(3)}×{m.group(4)}", int(m.group(5))))
    return out


def main(out):
    os.makedirs(out, exist_ok=True)
    lock = os.path.join(out, "lock"); open(lock, "w").write("0")
    h = Host(out, "stops", {"SILL_TEST_DISPLAYS": STOPS, "SILL_TEST_LOCKED_FILE": lock})
    try:
        verdict(bool(h.all(r"^Test displays: 3 in place of this Mac's")), "the host says it lists three test stops")
        # A: steps through the three and back, a tap on each; then a step locked, and the unlock.
        a, ra = client(h, out, "a", 25, ["desktop", "--fps=120", "--tap=0.5,0.5@3", "--next-display@4", "--tap=0.5,0.5@6",
                                          "--next-display@7", "--tap=0.5,0.5@9", "--next-display@10", "--tap=0.5,0.5@12",
                                          "--next-display@13", "--next-display@17", "--tap=0.25,0.25@22"], 1)
        h.at(16); open(lock, "w").write("1")
        h.at(18.5); open(lock, "w").write("0")
        a.join()
        # B: back within the span (6 s after A left): the stop A chose. C: after the span: the main display.
        b, rb = client(h, out, "b", 4, ["desktop", "--expect=desktopDisplay=2,desktopDisplays=3"], 30)
        b.join()
        c, rc = client(h, out, "c", 4, ["desktop", "--expect=desktopDisplay=1,desktopDisplays=3"], 67)
        c.join()
    finally:
        h.stop()
    t0 = 1.0
    s = streams(h, 0, 1e9)
    print("streams:", s)
    first = streams(h, 0, 4.5)
    verdict(bool(first) and first[0][:2] == (1, "Built-in Retina Display") and first[0][2] == "1512×982",
            f"the session starts on the main display, Desktop 1, at its own size: {first[:1]}")
    verdict(bool(first) and first[0][3] == 60, f"the main display's 120 Hz under the software encoder's 60: 60 fps: {first[:1]}")
    steps = h.all(r"^Desktop: display \d of 3")
    want_steps = ["Desktop: display 2 of 3 (DELL U2723QE)", "Desktop: display 3 of 3 (LG HDR 4K)", "Desktop: display 1 of 3 (Built-in Retina Display)",
                  "Desktop: display 2 of 3 (DELL U2723QE)"]
    verdict([l.split(", asked by")[0] for _, l in steps] == want_steps,
            f"four steps: right, the leftmost, back to the main display, right again: {[l for _, l in steps]}")
    verdict(all(", asked by " in l for _, l in steps), "each step names the device that asked")
    dell = streams(h, 4, 6.5); lg = streams(h, 7, 9.5); main_again = streams(h, 10, 12.5)
    verdict(bool(dell) and dell[0][1:] == ("DELL U2723QE", "2560×1440", 60), f"on the 60 Hz stop: its size, 60 fps: {dell}")
    verdict(bool(lg) and lg[0][1:] == ("LG HDR 4K", "1920×1080", 30), f"on the 30 Hz stop, with a 120 Hz client: 30 fps: {lg}")
    verdict(bool(main_again) and main_again[0][:2] == (1, "Built-in Retina Display"), f"the wrap: back to the main display: {main_again}")
    taps = lands(h, 0, 14.5)
    verdict(taps == [(756, 491), (2792, 720), (-960, 340), (756, 491)],
            f"each tap lands at the centre of the stop it shows, in its own space: {taps}")
    locked = streams(h, 16, 18.5)
    verdict(bool(locked) and locked[0][:2] == (1, "Built-in Retina Display"),
            f"locked on Desktop 2: the Desktop moves to the main display (its lock screen): {locked}")
    verdict(not h.all(r"^Desktop: display", 16.5, 18.5), "a step while locked: refused, no step")
    unlocked = streams(h, 18.5, 26)
    verdict(bool(unlocked) and unlocked[-1][:2] == (2, "DELL U2723QE"), f"unlocked: the stop chosen comes back: {unlocked}")
    late_tap = lands(h, 19.5, 26.5)
    verdict(late_tap == [(2152, 360)], f"a tap after the unlock lands on Desktop 2 again: {late_tap}")
    la = lists(ra.get("out", ""))
    verdict(any(l[:3] == (3, 1, NAMES) for l in la), "A's lists say three stops, Desktop 1, and their names")
    verdict(any(l[3] and l[0] is None and l[1] is None and l[2] is None for l in la), "a locked list says no stops and no names")
    verdict(any(l[:2] == (3, 2) and not l[3] for l in la[-3:]), "after the unlock the lists say Desktop 2 again")
    verdict(rb.get("exit") == 0 and "EXPECT ok" in rb.get("out", ""), "B, 4 s after A left: Desktop 2, the stop chosen (the span)")
    verdict(rc.get("exit") == 0 and "EXPECT ok" in rc.get("out", ""), "C, 33 s after B left: Desktop 1, the main display (the span over)")
    verdict(bool(streams(h, 66, 72)) and streams(h, 66, 72)[0][:2] == (1, "Built-in Retina Display"), "C's Desktop streams the main display")
    verdict(not h.all(r"CGWarp|warp", 0, 1e9), "nothing warped")

    # Without the stops: no list fields, kind 47 ignored, the test pattern as before.
    h2 = Host(out, "plain", {})
    try:
        d, rd = client(h2, out, "d", 6, ["desktop", "--fps=120", "--next-display@3", "--expect=desktopDisplay=none,desktopDisplays=none"], 1)
        d.join()
    finally:
        h2.stop()
    verdict(rd.get("exit") == 0 and "EXPECT ok" in rd.get("out", ""), "a host without the stops: no desktopDisplays or desktopDisplay")
    verdict(not h2.all(r"^Desktop: display"), "a host without the stops ignores kind 47")
    verdict(bool(h2.all(r"^Streaming a synthetic test pattern( \(software encoder\))? at 1512×94\d, 60 fps")), "a host without the stops streams the plain test pattern")
    verdict(not h2.all(r"^Test displays"), "a host without the stops says nothing of them")
    failed = [w for ok, w in verdicts if not ok]
    print(f"{len(verdicts) - len(failed)} of {len(verdicts)} verdicts held")
    return 0 if not failed else 1


if __name__ == "__main__":
    if len(sys.argv) != 2: raise SystemExit(__doc__)
    sys.exit(main(sys.argv[1]))
