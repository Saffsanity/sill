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
Then the Virtual Desktop (phase 2b): a host with --virtual-desktop, two stops and SILL_TEST_VIRTUAL_DESKTOP (said, never
made; its grace SILL_TEST_VD_GRACE=3 s): the stop after the screens, a step onto it (said, at the device's room, 1218×800),
following its turn in place as Noah's probes P2b and P2c measured a display (the said display: 1x first, then the switch,
the Desktop restarted once at 800×1218; back in one step; nothing for a turn back within the settle), stepped away and
its grace, made again, kept while locked and back after the unlock, removed off console, the span after the device left;
a --pairing host with Require pairing off: an unpaired client's "on" refused, a paired one's shown at once, the switch
flipped four times a second making at most one change of the display every 3 s, and off; a host whose said display
refuses every switch (SILL_TEST_VD_STEPS=switch-refused): a turn falls back to the room at 2x and waits for the next make,
the iPad leaves and the iPhone that comes takes it over in place (one applySettings:, no switch), then a device whose
room is beyond the backing waits for the next make; and one whose way back never lands either (switch-refused,stuck):
removed, and made again at the turned size by the Desktop that still shows its stop.
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
    def __init__(self, out, label, env, args=()):
        self.lines, self.out, self.label = [], out, label
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
    virtual(out)
    failed = [w for ok, w in verdicts if not ok]
    print(f"{len(verdicts) - len(failed)} of {len(verdicts)} verdicts held")
    return 0 if not failed else 1


VD_STOPS = "Built-in Retina Display:1512x982@2:120:0,0;DELL U2723QE:2560x1440@1:60:1512,0"
VD_NAMES = '["Built-in Retina Display", "DELL U2723QE", "Virtual Desktop"]'


def vd_lines(host, after=0.0, before=1e9):
    """The Virtual Desktop's makes and removals between two times: [(t, "made"|"removed", line)]."""
    out = []
    for t, l in host.all(r"^Virtual Desktop ", after, before):
        if "said, never made" in l: out.append((t, "made", l))
    for t, l in host.all(r"^Virtual Desktop: .*removed it", after, before):
        out.append((t, "removed", l))
    return sorted(out)


def virtual(out):
    """The Virtual Desktop on two test hosts (phase 2b), nothing made: see the docstring."""
    lock = os.path.join(out, "vd.lock"); open(lock, "w").write("0")
    env = {"SILL_TEST_DISPLAYS": VD_STOPS, "SILL_TEST_VIRTUAL_DESKTOP": "1", "SILL_TEST_VD_GRACE": "3", "SILL_TEST_LOCKED_FILE": lock}
    h = Host(out, "vd", env, args=["--virtual-desktop"])
    try:
        verdict(bool(h.all(r"^Test Virtual Desktop: this host can have it .* its grace 3 s\.")), "VD: the host says the hook and its 3 s grace")
        verdict(bool(h.all(r"^Virtual Desktop on for this run \(Resolution: Match the device, Refresh Rate: Match the device\): ")),
                "VD: --virtual-desktop's line, the device's size and rate")
        # A: two steps (DELL, then the Virtual Desktop), its turn held (a line after 1 s), back (nothing: the display has
        # that size), a turn and back within the settle (no line), a step away (its grace), back onto it (made again), a
        # lock and unlock, off console.
        a, ra = client(h, out, "vd-a", 41, ["desktop", "--fps=60", "--room=1133x744", "--device=iPad mini",
                                            "--next-display@2", "--next-display@4", "--room-after=744x1133@7", "--room-after=1133x744@10",
                                            "--room-after=744x1133@13", "--room-after=1133x744@13.5", "--next-display@15",
                                            "--next-display@20", "--next-display@21"], 1)
        h.at(23); open(lock, "w").write("1")
        h.at(29); open(lock, "w").write("0")
        h.at(35); open(lock, "w").write("2")
        h.at(38); open(lock, "w").write("0")
        a.join()
        # B, 4 s after A left: the Desktop back on the Virtual Desktop's stop (the span), made again; then none for its grace.
        b, rb = client(h, out, "vd-b", 6, ["desktop", "--fps=60", "--room=1133x744", "--device=iPad mini",
                                           "--expect=desktopVirtual=3,desktopDisplay=3,virtualDesktop=1,virtualDesktopShown=1"], 46)
        b.join()
        h.at(57)
    finally:
        h.stop()
    la = lists(ra.get("out", ""))
    verdict(any(re.search(r"desktopDisplays=3 desktopDisplay=1 desktopVirtual=3 names=" + re.escape(VD_NAMES), l)
                for l in ra.get("out", "").splitlines()), "VD: the list says three stops, the Virtual Desktop the third")
    steps = [l.split(", asked by")[0] for _, l in h.all(r"^Desktop: display \d of 3", 0, 23)]
    verdict(steps[:2] == ["Desktop: display 2 of 3 (DELL U2723QE)", "Desktop: display 3 of 3 (Virtual Desktop)"],
            f"VD: a step past the screens lands on it: {steps[:2]}")
    made = vd_lines(h, 4.5, 6.5)
    verdict(len(made) == 1 and made[0][1] == "made" and "1218×800 pt @2× at 60 Hz" in made[0][2] and "for iPad mini (its screen)" in made[0][2],
            f"VD: made (said) at the device's room grown to 800 points, 60 Hz: {made}")
    on_vd = streams(h, 4.5, 7)
    # Its size in points, as every test stop's test pattern (the capture scale's 1× on a test host; probe of 6329077e).
    verdict(bool(on_vd) and on_vd[0][:2] == (3, "Virtual Desktop") and on_vd[0][2] == "1218×800" and on_vd[0][3] == 60,
            f"VD: the Desktop on it, at its size, 60 fps: {on_vd}")
    # The turn held 1 s: in place (Noah's probes P2b and P2c, 2026-11-23), the said display as they measured one: its
    # pixels at 1x, then the switch to 800×1218 at 2x, about 650 ms; the Desktop restarted once, at the turn. Turned back
    # 3 s later: in place in one step (the made orientation), about 320 ms. A turn and back within the settle: nothing.
    follows = h.all(r"^Virtual Desktop: iPad mini (turned|changed its room)", 5, 15.5)
    def took(l):
        m = re.search(r"followed in place in (\d+) ms: (\d+×\d+) pt @2× at 60 Hz\.$", l)
        return (int(m.group(1)), m.group(2)) if m else None
    got = [(round(t, 1), took(l)) for t, l in follows]
    verdict(len(follows) == 2 and 8.8 <= follows[0][0] <= 10.8 and took(follows[0][1]) is not None and took(follows[0][1])[1] == "800×1218"
            and 600 <= took(follows[0][1])[0] <= 1200,
            f"VD: a turn held 1 s: followed in place, 1x then the switch, in about 650 ms: {got}")
    verdict(len(follows) == 2 and 12.2 <= follows[1][0] <= 13.6 and took(follows[1][1]) is not None and took(follows[1][1])[1] == "1218×800"
            and 250 <= took(follows[1][1])[0] <= 900,
            f"VD: turned back 3 s later: in place in one step, about 320 ms: {got}")
    detail = h.all(r"^Virtual Desktop: in place \(TEST ONLY: said, the display as the probes measured it\): applySettings: with 800×1218 alone", 5, 10.8)
    verdict(len(detail) == 1 and "at 1600×2436 @1×" in detail[0][1] and "switch to 800×1218 @2×: complete 0" in detail[0][1],
            f"VD: its steps said before it, TEST ONLY: {detail}")
    turned = streams(h, 8.8, 12)
    verdict(bool(turned) and turned[0][:3] == (3, "Virtual Desktop", "800×1218") and len([x for x in streams(h, 7.5, 12) if x[1] == "Virtual Desktop"]) == 1,
            f"VD: the Desktop restarted once, at the turn: {streams(h, 7.5, 12)}")
    lying = streams(h, 12.2, 13.6)
    verdict(bool(lying) and lying[-1][:3] == (3, "Virtual Desktop", "1218×800"), f"VD: and once at the room again: {lying}")
    verdict(not h.all(r"^Virtual Desktop: iPad mini", 13.6, 15.5), "VD: a turn and back within the settle: nothing")
    gone = vd_lines(h, 15, 20)
    verdict(len(gone) == 1 and gone[0][1] == "removed" and 17.5 <= gone[0][0] <= 19.8 and "no device has shown it for 3 s" in gone[0][2]
            and "(TEST ONLY: none was made.)" in gone[0][2], f"VD: stepped away, removed after its 3 s grace: {gone}")
    again = vd_lines(h, 20, 23)
    verdict(len(again) == 1 and again[0][1] == "made", f"VD: stepped onto again: made again: {again}")
    locked = streams(h, 23, 26)
    verdict(bool(locked) and locked[0][:2] == (1, "Built-in Retina Display"), f"VD: locked, the Desktop on the main display: {locked}")
    verdict(not vd_lines(h, 23, 29), "VD: kept while locked, past its grace")
    verdict(bool(h.all(r"^Virtual Desktop: kept while this Mac is locked; it goes 3 s after the unlock", 25, 29.5)),
            "VD: the kept-while-locked line, once its grace had passed")
    back = streams(h, 29, 35)
    verdict(bool(back) and back[-1][:2] == (3, "Virtual Desktop"), f"VD: unlocked, back on it: {back}")
    off = vd_lines(h, 35, 38)
    verdict(len(off) == 1 and off[0][1] == "removed" and "this session is off the console" in off[0][2] and off[0][0] < 36.5,
            f"VD: off console, removed at once: {off}")
    verdict(any(l[3] for l in la), "VD: a locked list (no stop fields)")
    verdict(not any(l[3] and "desktopVirtual" in raw for l, raw in zip(la, [x for x in ra.get("out", "").splitlines() if x.strip().startswith("windowList:")])),
            "VD: no locked list says desktopVirtual")
    span = [x for x in vd_lines(h, 46, 52) if x[1] == "made"]
    verdict(rb.get("exit") == 0 and "EXPECT ok" in rb.get("out", "") and len(span) == 1,
            f"VD: B within the span: back on its stop, made again, shown: {span}")
    end = [x for x in vd_lines(h, 52, 58) if x[1] == "removed"]
    verdict(len(end) == 1 and "no device has shown it for 3 s" in end[0][2], f"VD: B gone: removed after its grace: {end}")
    changes = [t for t, _, _ in vd_lines(h)]
    verdict(all(b2 - b1 >= 2.95 for b1, b2 in zip(changes, changes[1:])), f"VD: never two changes within 3 s: {[round(t, 1) for t in changes]}")

    # The switch from a device: --pairing, Require pairing off; P paired by the host's link, U not.
    remote = os.path.join(out, "vdp.remote"); os.makedirs(remote, exist_ok=True); os.chmod(remote, 0o700)
    env = {"SILL_TEST_DISPLAYS": VD_STOPS, "SILL_TEST_VIRTUAL_DESKTOP": "1", "SILL_TEST_VD_GRACE": "3", "SILL_TEST_REMOTE_DIR": remote,
           "SILL_TEST_REQUIRE_PAIRING": "0"}
    h2 = Host(out, "vdp", env, args=["--pairing"])
    try:
        h2.at(1.0)
        link = next((re.search(r"(sill://pair\S+)", l).group(1) for _, l in h2.lines if re.search(r"sill://pair\S+", l)), None)
        idp, idu = os.path.join(out, "vdp.idP"), os.path.join(out, "vdp.idU")
        if link:
            pair = subprocess.run([sys.executable, "-I", CLIENT, h2.port, "2", "none", f"--pair-url={link}", f"--identity={idp}"],
                                  capture_output=True, text=True, timeout=30, env={**os.environ, **BASE_ENV})
            open(os.path.join(out, "vdp-pair.client.log"), "w").write(pair.stdout + pair.stderr)
        # U (from 3.2 s, after the pairing above, for 2 s) leaves before P turns it on (at 6 s): the switch is the Mac's, so
        # U's last answer would be P's otherwise.
        u, ru = client(h2, out, "vdp-u", 2, ["none", "--tls", f"--identity={idu}", "--pin=none", "--device=Unpaired iPad",
                                             "--set=virtualDesktop=1@0.8", "--expect=virtualDesktop=0,sessionPaired=0"], 3.2)
        flips = [f"--set=virtualDesktop={1 if i % 2 else 0}@{6 + 0.25 * i:g}" for i in range(8)]
        pc, rp = client(h2, out, "vdp-p", 18, ["desktop", "--tls", f"--identity={idp}", "--fps=60", "--room=1133x744", "--device=Paired iPad",
                                               "--set=virtualDesktop=1@2", *flips, "--set=virtualDesktop=0@14",
                                               "--expect=virtualDesktop=0,sessionPaired=1,virtualDesktopAvailable=1"], 4)
        u.join(); pc.join()
        h2.at(24)
    finally:
        h2.stop()
    verdict(bool(link), "VD: the --pairing host printed its link")
    verdict(ru.get("exit") == 0 and "EXPECT ok" in ru.get("out", "")
            and bool(h2.all(r"^Settings from Unpaired iPad refused: virtual desktop \(only a paired device\)")),
            "VD: an unpaired device's on: refused, named, its switch back off")
    shown = h2.all(r"^Desktop: Virtual Desktop, turned on by Paired iPad\.", 5, 7)
    first = vd_lines(h2, 5, 7)
    verdict(bool(shown) and len(first) == 1 and first[0][1] == "made" and "for Paired iPad (its screen)" in first[0][2],
            f"VD: a paired device's on: shown to it at once, made at its room: {first}")
    pstreams = streams(h2, 5, 8)
    verdict(any(x[:2] == (3, "Virtual Desktop") for x in pstreams), f"VD: the Desktop on it: {pstreams}")
    churn = vd_lines(h2, 6, 14)
    ct = [t for t, _, _ in vd_lines(h2)]
    verdict(len(churn) <= 3 and all(b2 - b1 >= 2.95 for b1, b2 in zip(ct, ct[1:])),
            f"VD: the switch flipped four times a second: at most one change every 3 s: {[(round(t, 1), k) for t, k, _ in vd_lines(h2)]}")
    verdict(rp.get("exit") == 0 and "EXPECT ok" in rp.get("out", ""), "VD: the paired device's last word (off) stands, and it says available")
    last = vd_lines(h2)
    verdict(bool(last) and last[-1][1] == "removed", f"VD: off at the end: removed: {last[-1:] if last else last}")
    in_place(out)


def in_place(out):
    """The follow in place where a step fails, another device, the backing (TEST ONLY knobs: SILL_TEST_VD_STEPS)."""
    env = {"SILL_TEST_DISPLAYS": VD_STOPS, "SILL_TEST_VIRTUAL_DESKTOP": "1", "SILL_TEST_VD_GRACE": "3",
           "SILL_TEST_VD_STEPS": "switch-refused"}
    h = Host(out, "vd-in", env, args=["--virtual-desktop"])
    try:
        # P, an iPad mini: onto it (made at 1218×800, its backing 3072×3072: no larger device connected), turned at 7
        # (the switch refused: back to the room), gone at 10. Q, an iPhone, at 11: its Desktop back on the stop, the
        # Virtual Desktop its own in place (no switch needed). Q gone at 16; R, a room 1900×800 pt wide, at 17: beyond.
        p, rp = client(h, out, "vdin-p", 9, ["desktop", "--fps=60", "--room=1133x744", "--device=iPad mini",
                                             "--next-display@1", "--next-display@3", "--room-after=744x1133@6"], 1)
        p.join()
        q, rq = client(h, out, "vdin-q", 5, ["desktop", "--fps=120", "--room=735x393", "--device=iPhone"], 11)
        q.join()
        r, rr = client(h, out, "vdin-r", 4, ["desktop", "--fps=60", "--room=1900x800", "--device=Wide iPad"], 17)
        r.join()
        h.at(22)
    finally:
        h.stop()
    verdict(bool(h.all(r"^Test Virtual Desktop: its said display's steps: switch-refused \(SILL_TEST_VD_STEPS\)")),
            "VD in place: the host says its said display's steps")
    made = vd_lines(h, 3, 6)
    verdict(len(made) == 1 and made[0][1] == "made" and "1218×800 pt @2× at 60 Hz" in made[0][2], f"VD in place: made for the iPad mini: {made}")
    back = h.all(r"^Virtual Desktop: iPad mini turned; ", 6, 11)
    verdict(len(back) == 1 and "not followed in place: macOS refused the switch to its 2x mode (complete 1001); back at 1218×800 pt @2× in " in back[0][1]
            and back[0][1].endswith("; the next one is made at 800×1218 pt."),
            f"VD in place: a turn whose switch is refused: back to the room at 2x, the next make: {back}")
    steps = h.all(r"^Virtual Desktop: in place \(TEST ONLY", 6, 11)
    verdict(len(steps) == 1 and "switch to 800×1218 @2×: complete 1001" in steps[0][1] and "applySettings: with 1218×800 alone answered YES" in steps[0][1],
            f"VD in place: its steps said, the way back by applySettings: with the room alone: {steps}")
    verdict(not [x for x in streams(h, 6, 11) if x[2] == "800×1218"], "VD in place: no picture at the turn it did not take")
    iphone = h.all(r"^Virtual Desktop: iPhone shows it now; ", 11, 16.5)
    m = re.search(r"followed in place in (\d+) ms: 1496×800 pt @2× at (60|120) Hz\.$", iphone[0][1]) if len(iphone) == 1 else None
    verdict(m is not None and 250 <= int(m.group(1)) <= 900,
            f"VD in place: the iPad gone, the iPhone that comes takes it over in place, one step: {iphone}")
    verdict(not [l for _, l in h.all(r"^Virtual Desktop: in place \(TEST ONLY", 11, 16.5) if "switch to" in l],
            "VD in place: the iPhone's size of the same orientation: no switch")
    on_q = [x for x in streams(h, 11, 16.5) if x[1] == "Virtual Desktop"]
    verdict(bool(on_q) and on_q[-1][2] == "1496×800", f"VD in place: the Desktop at the iPhone's size: {on_q}")
    wide = h.all(r"^Virtual Desktop: Wide iPad shows it now; ", 17, 22)
    verdict(len(wide) == 1 and wide[0][1] == "Virtual Desktop: Wide iPad shows it now; 1900×800 pt @2× is beyond the backing it was made with "
            "(3072×3072 px); the next one is made at 1900×800 pt.", f"VD in place: a room beyond the backing: the next make: {wide}")
    verdict(not [x for x in streams(h, 17, 22) if x[2] == "1900×800"], "VD in place: no picture at a size it did not take")
    verdict(len([x for x in vd_lines(h) if x[1] == "made"]) == 1, f"VD in place: made once, never again: {vd_lines(h)}")

    env = dict(env); env["SILL_TEST_VD_STEPS"] = "switch-refused,stuck"
    h = Host(out, "vd-stuck", env, args=["--virtual-desktop"])
    try:
        p, rp = client(h, out, "vdstuck-p", 16, ["desktop", "--fps=60", "--room=1133x744", "--device=iPad mini",
                                                 "--next-display@1", "--next-display@3", "--room-after=744x1133@6"], 1)
        p.join()
        h.at(21)
    finally:
        h.stop()
    gone = [x for x in vd_lines(h, 6, 13) if x[1] == "removed"]
    verdict(len(gone) == 1 and "not followed in place: macOS refused the switch to its 2x mode (complete 1001), and it did not come back to "
            "1218×800 pt @2×; removed it: the next one is made at 800×1218 pt." in gone[0][2] and "(TEST ONLY: none was made.)" in gone[0][2],
            f"VD stuck: the way back never landed: removed, never left at 1x: {gone}")
    again = [x for x in vd_lines(h, 6, 18) if x[1] == "made"]
    verdict(len(again) == 1 and bool(gone) and again[0][0] - gone[0][0] >= 2.95 and "800×1218 pt @2× at 60 Hz" in again[0][2],
            f"VD stuck: made again at the turn by the Desktop that shows its stop, 3 s after: {again}")
    on_up = [x for x in streams(h, 12, 18) if x[1] == "Virtual Desktop"]
    verdict(bool(on_up) and on_up[-1][2] == "800×1218", f"VD stuck: the Desktop on it, upright: {on_up}")


if __name__ == "__main__":
    if len(sys.argv) != 2: raise SystemExit(__doc__)
    sys.exit(main(sys.argv[1]))
