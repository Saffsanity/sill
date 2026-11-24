#!/usr/bin/env python3
"""TEST ONLY (docs/privacy-mode-plan.md, part 2; G4's first cases): Darken this Mac's screen on synthetic test hosts on
loopback, the darkening a dry run, as on every host but Sill.app itself (DarkenPolicy.darkensForReal: PrivacyScreen's
DryCurtain, lines and never a window; the Mac's own input from the SILL_TEST_PRIVACY_INPUT file, never an event
monitor; the lock ScreenLocker's dry run). Each host runs on 127.0.0.1 alone with the software encoder, no router and
no screen (SILL_TEST_LOCK_IGNORE_MAC: the lock's reading is the test's own file, never this Mac's), lives under 30 s
and is killed at the end. One verdict per rule:

  order     the black is up (\"would darken\") before the connect's display wake is counted (rule 5), both stamped
  home      --darken=away and a device at home: nothing darkens; the start line says the switch, and a dry run
  away      --darken=away and a paired device at the remote door: away from a relay on this Mac, it darkens; at home
            (SILL_TEST_REMOTE_ORIGIN=lan), it does not
  wait      --darken=any: dark at the connect, the wait's line at the departure, a return within it, lit at its end
  keys      a pointer move only shows the hint; Sill's own (tagged) key nothing; a key locks (dry), unconfirmed after
            3 s: the ⌃⌘Q hint, and a second key asks no lock
  pass      --darken-keys=pass: a key only shows the ⌃⌘Q hint
  takeback  locked and unlocked at the Mac with no device's input (the lock file): lit, and stays lit
  hold      with --lock-after-session: the dark holds through the lock's wait and its confirmation, lit only after
  quit      SIGTERM while dark: lit before the host exits
  watchdog  SILL_TEST_PRIVACY_STALL=12 while dark: the main thread stops 12 s, the watchdog's dry run says once, 10 s
            into it, that it would quit Sill, and the host goes on after the stall (rule 12; Sill.app itself would end)
  switch    Sill.app's own code for the switches and its Quit, in the bare SillMenuBar binary as a synthetic test host
            (not Sill.app, so the dry run; -requirePairing NO, -virtualDisplay 0, a TLS test client at home): Darken
            this Mac's screen turned on, off (lit at once), on, to only away with the device at home and keys passing
            (lit at once), on again (the ⌃⌘Q hint), the wait to 30 s and the pointer shown while dark (it would show
            it), then Sill's own Quit while dark (lit, then its line); HostSettings saves the five keys in the bare
            binary's defaults domain (SillMenuBar), which the case reads and removes
  pointer   rule 15 (run 6): the dry run would hide the pointer once the black is up (and finds the two private calls
            by name, never calling them), would show it for the lock screen, before the black lifts at the Mac's own
            unlock and at SIGTERM; with --darken-pointer=show it never touches it, and the start line says so
  waits     Settings' wait (run 6), no SILL_TEST_PRIVACY_GRACE: 5 s by default and 30 s with --darken-wait=30, in the
            departure's line, the wait's hint and the start line, and lit that long after the last device left
  keyleft   a key 1 s after the last device left: lit at once, nothing locks; a device back after it: dark again at
            once; a device back inside the next wait: dark goes on; with --lock-after-session a key in the wait locks
            at once, as before, and lights nothing

    Scripts/privacy-check/darken.py OUT [order|home|away|wait|keys|pass|takeback|hold|quit|watchdog|switch|pointer|waits|keyleft|all]

Needs .build/release/SillHost (and .build/release/SillMenuBar for switch). Exits 1 when a verdict fails."""
import os, re, signal, subprocess, sys, threading, time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
HOST = os.path.join(ROOT, ".build/release/SillHost")
APP = os.path.join(ROOT, ".build/release/SillMenuBar")
APP_KEYS = ("darkenScreen", "darkenOnlyAway", "darkenKeysLock", "darkenWait", "darkenHidesPointer")
CLIENT = os.path.join(ROOT, "Scripts/sillclient.py")
BASE_ENV = {"SILL_TEST_LOOPBACK": "1", "SILL_TEST_SOFTWARE_ENCODER": "1", "SILL_TEST_NO_ROUTER": "1", "SILL_TEST_NO_SCREEN": "1",
            "SILL_TEST_LOCK_IGNORE_MAC": "1", "SILL_TEST_PRIVACY_DISPLAYS": "1"}
DARK = "Privacy (dry run): would darken 1 display; nothing is drawn."
LIGHT = "Privacy (dry run): would light this Mac’s screen again; nothing was drawn."
HINT_LOCK = "Privacy (dry run): would show “This Mac is in use from another device. Press any key or click to lock it.”"
HINT_PASS = "Privacy (dry run): would show “This Mac is in use from another device. To use it here, press Control-Command-Q, then unlock it.”"
DRY_CURTAIN = ("Privacy (dry run): would darken", "Privacy (dry run): would light", "Privacy (dry run): would show")
DRY_START = " A dry run here (only Sill.app itself darkens a Mac’s screen): it says what it would do."
LOCK_DRY = "Privacy (dry run): would lock this Mac now; nothing is locked."
POINTER_HIDE = "Privacy (dry run): would hide this Mac’s pointer (CGSMainConnectionID and CGSSetConnectionProperty found); it stays visible."
POINTER_ANY_HIDE = "Privacy (dry run): would hide this Mac’s pointer"
POINTER_SHOW = "Privacy (dry run): would show this Mac’s pointer again; it was never hidden."
LIT_KEY = "Privacy: someone pressed a key or clicked on this Mac after the last device left; its screen is lit again, and nothing locks."
WATCHDOG_DRY = ("Privacy (dry run): Sill’s main thread hasn’t answered for 10 s while this Mac’s screen was dark; would quit Sill and open "
                "it again; nothing quits.")

verdicts = []


def verdict(ok, what):
    verdicts.append((ok, what))
    print(("ok   " if ok else "FAIL ") + what, flush=True)


def write(path, text):
    with open(path, "w") as f: f.write(text)


class Host:
    """One synthetic host: its stdout's lines with the time each was read, its port. `binary`: SillHost (the CLI), or
    the bare SillMenuBar binary, whose port is the one its "Status: Test Pattern Mode" line names (`port_line`)."""
    def __init__(self, out, label, env, args=(), binary=HOST, port_line=None):
        self.lines, self.out, self.label = [], out, label
        e = dict(os.environ); e.update(BASE_ENV); e.update(env)
        self.start = time.time()
        self.p = subprocess.Popen(["nice", "-n", "10", binary, "--synthetic", *args], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                  env=e, start_new_session=True, text=True, bufsize=1)
        threading.Thread(target=self._read, daemon=True).start()
        self.port = None
        for _ in range(100):
            time.sleep(0.1)
            r = subprocess.run(["lsof", "-nP", "-a", "-p", str(self.p.pid), "-iTCP", "-sTCP:LISTEN"], capture_output=True, text=True)
            if re.findall(r"(\*|\[::\]|0\.0\.0\.0):(\d+) \(LISTEN\)", r.stdout): self.stop(); raise SystemExit(f"{label}: a listener not on loopback")
            ports = re.findall(r"127\.0\.0\.1:(\d+) \(LISTEN\)", r.stdout)
            if port_line:
                named = [m.group(1) for _, l in list(self.lines) for m in [re.search(port_line, l)] if m]
                if named and named[0] in ports: self.port = named[0]; break
            elif ports: self.port = ports[0]; break
        if self.port is None: self.stop(); raise SystemExit(f"{label}: no listening port")

    def _read(self):
        for line in self.p.stdout:
            self.lines.append((time.time() - self.start, line.rstrip("\n")))

    def at(self, t):
        d = self.start + t - time.time()
        if d > 0: time.sleep(d)

    def stop(self, signal_=signal.SIGTERM):
        if self.p.poll() is None:
            os.killpg(self.p.pid, signal_)
            try: self.p.wait(5)
            except subprocess.TimeoutExpired: os.killpg(self.p.pid, signal.SIGKILL); self.p.wait()
        time.sleep(0.2)
        with open(os.path.join(self.out, self.label + ".host.log"), "w") as f:
            for t, l in self.lines: f.write(f"{t:8.3f} {l}\n")

    def find(self, text, after=0.0):
        """Every line containing `text` read at or after `after` s: [(seconds in, index, line)]."""
        return [(t, i, l) for i, (t, l) in enumerate(self.lines) if t >= after and text in l]

    def first(self, text, after=0.0):
        f = self.find(text, after)
        return f[0] if f else (None, None, None)


def client(host, label, seconds, start, extra=()):
    """A sillclient session `start` s after the host's start, for `seconds`, in a thread."""
    def run():
        host.at(start)
        r = subprocess.run([sys.executable, "-I", CLIENT, host.port, str(seconds), "desktop", *extra], capture_output=True, text=True,
                           timeout=seconds + 20, env={**os.environ, **BASE_ENV})
        open(os.path.join(host.out, label + ".client.log"), "w").write(r.stdout + r.stderr + f"\nEXIT {r.returncode}\n")
    th = threading.Thread(target=run); th.start()
    return th


def case_order(out):
    print("== order: the black up before the connect's display wake (rule 5)", flush=True)
    h = Host(out, "order", {"SILL_TEST_PRIVACY_LOG": "1", "SILL_TEST_PRIVACY_GRACE": "2"}, ["--darken=any"])
    c = client(h, "order", 3, 1.0)
    c.join(); h.at(7); h.stop()
    _, dark_i, dark = h.first(DARK)
    _, wake_i, wake = h.first("disp.wakeDry for")
    verdict(dark_i is not None and wake_i is not None and dark_i < wake_i,
            f"the black is up before the wake is counted: {dark!r} (line {dark_i}) before {wake!r} (line {wake_i})")
    verdict(bool(h.find("Privacy: this Mac’s screen is dark while a device is connected (1 display).")), "the dark's line")
    verdict(bool(h.find("(test: ")) and bool(re.search(r"Test privacy: [\d.]+ s disp\.wakeDry", wake or "")), "both stamped")


def case_home(out):
    print("== home: only away, a device at home", flush=True)
    h = Host(out, "home", {}, ["--darken=away"])
    c = client(h, "home", 3, 1.0)
    c.join(); h.at(5); h.stop()
    start = h.find("Privacy: Darken this Mac’s screen is on: while a device away from home is connected and for 5 s after the last one leaves; "
                   "a key or click on this Mac locks it; the pointer is hidden on the black.")
    verdict(bool(start), "the start line says the switch")
    verdict(len(start) == 1 and start[0][2].endswith(DRY_START), "and that it is a dry run here (only Sill.app itself darkens a Mac's screen)")
    dark = [x for p in DRY_CURTAIN for x in h.find(p)]
    verdict(not dark, f"a device at home darkens nothing under only away: {dark[:1]}")


def case_wait(out):
    print("== wait: dark at the connect, the wait, a return, lit at its end", flush=True)
    h = Host(out, "wait", {"SILL_TEST_PRIVACY_GRACE": "3"}, ["--darken=any"])
    c1 = client(h, "wait-1", 2, 1.0)
    c1.join()
    c2 = client(h, "wait-2", 2, 4.5)
    c2.join(); h.at(11); h.stop()
    left = h.find("Privacy: the last device left; this Mac’s screen stays dark for 3 s in case it comes back, or until a key or click on it.")
    back = h.find("Privacy: a device came back; this Mac’s screen stays dark.")
    lit = h.find("Privacy: this Mac’s screen is lit again.")
    verdict(len(h.find(DARK)) == 1, f"darkened once, the return kept it dark: {len(h.find(DARK))} raises")
    verdict(len(left) == 2 and len(back) == 1, f"the wait's line at each departure ({len(left)}), the return's once ({len(back)})")
    gone2 = left[1][0] if len(left) == 2 else None
    verdict(len(lit) == 1 and gone2 is not None and 2.9 <= lit[0][0] - gone2 <= 3.9,
            f"lit 3 s after the last departure: {[round(t - (gone2 or 0), 2) for t, _, _ in lit]}")
    _, light_i, _ = h.first(LIGHT)
    verdict(light_i is not None and light_i > lit[0][1], "and the dry curtain lifts after the line")


def case_keys(out):
    print("== keys: the pointer, Sill's own key, a key that locks (dry) and does not confirm", flush=True)
    f = os.path.join(out, "keys.input")
    h = Host(out, "keys", {"SILL_TEST_PRIVACY_INPUT": f}, ["--darken=any"])
    c = client(h, "keys", 14, 1.0)
    h.at(3.0); write(f, "move")
    h.at(4.5); write(f, "key tagged")
    h.at(6.0); write(f, "key")
    h.at(11.0); write(f, "key")
    c.join(); h.at(16); h.stop()
    hints = h.find(HINT_LOCK, after=2.9)
    verdict(any(3.0 <= t < 4.4 for t, _, _ in hints), f"a pointer move shows the hint: {[round(t, 2) for t, _, _ in hints]}")
    early = [x for x in h.find(LOCK_DRY) if x[0] < 6.0]
    verdict(not early, f"neither the move nor Sill's own key locks: {early[:1]}")
    tagged = h.find("(tagged: Sill’s own)")
    verdict(bool(tagged), "Sill's own key was read (and did nothing)")
    locking = h.find("Privacy: locking this Mac: someone pressed a key or clicked on it.")
    locks = h.find(LOCK_DRY)
    verdict(len(locking) == 1 and len(locks) == 1 and 6.0 <= locks[0][0] < 7.0, f"a key locks once (dry): {[round(t, 2) for t, _, _ in locks]}")
    failed = h.find("Privacy: couldn’t lock this Mac (it still read unlocked 3 s later); its screen now says to press Control-Command-Q.")
    verdict(len(failed) == 1 and 2.9 <= failed[0][0] - locks[0][0] <= 3.9 if locks else False,
            f"unconfirmed 3 s later: {[round(t, 2) for t, _, _ in failed]}")
    passes = h.find(HINT_PASS, after=9.0)
    verdict(len(passes) >= 2, f"the hint says ⌃⌘Q then, and at the next key: {[round(t, 2) for t, _, _ in passes]}")


def case_pass(out):
    print("== pass: --darken-keys=pass", flush=True)
    f = os.path.join(out, "pass.input")
    h = Host(out, "pass", {"SILL_TEST_PRIVACY_INPUT": f}, ["--darken=any", "--darken-keys=pass"])
    c = client(h, "pass", 6, 1.0)
    h.at(4.0); write(f, "key")
    c.join(); h.at(8); h.stop()
    verdict(bool(h.find("keys and clicks on this Mac reach its apps.")), "the start line says keys pass")
    verdict(bool(h.find(HINT_PASS, after=3.9)) and not h.find(LOCK_DRY), "a key only shows the ⌃⌘Q hint, no lock")


def case_takeback(out):
    print("== takeback: locked and unlocked at the Mac, no device typed", flush=True)
    lock = os.path.join(out, "takeback.lock"); write(lock, "0")
    h = Host(out, "takeback", {"SILL_TEST_LOCKED_FILE": lock}, ["--darken=any"])
    c = client(h, "takeback", 13, 1.0)
    h.at(3.5); write(lock, "1")
    h.at(6.0); write(lock, "0")
    c.join(); h.at(15); h.stop()
    lifts = h.find(LIGHT)
    verdict(not [x for x in lifts if x[0] < 6.0], "the lock alone lifts nothing (the black sits under the lock screen)")
    back = h.find("Privacy: unlocked on this Mac itself; its screen stays lit until every device has left.")
    verdict(len(back) == 1 and back[0][0] >= 6.0, f"the unlock (after its settle) is the Mac's own: {[round(t, 2) for t, _, _ in back]}")
    verdict(len(lifts) == 1 and len(h.find(DARK)) == 1, f"lit once, and not darkened again while the device stays ({len(lifts)} lifts)")


def case_hold(out):
    print("== hold: the dark holds through the lock's wait and confirmation", flush=True)
    h = Host(out, "hold", {"SILL_TEST_PRIVACY_GRACE": "3"}, ["--darken=any", "--lock-after-session"])
    c = client(h, "hold", 2, 1.0)
    c.join(); h.at(12); h.stop()
    asked, _, _ = h.first("Privacy (dry run): would lock this Mac now")
    outcome, _, _ = h.first("Privacy: couldn’t lock this Mac (it still read unlocked 3 s later); its display sleeps instead.")
    lit, _, _ = h.first(LIGHT)
    verdict(asked is not None and outcome is not None and lit is not None and lit >= outcome >= asked,
            f"the lock asked at {asked}, its outcome at {outcome}, and only then lit at {lit}")
    verdict(lit is not None and asked is not None and lit - asked <= 3 + 1.5, "lit within the confirmation and a tick")


def case_away(out):
    print("== away: only away, a paired device at the remote door (from a relay on this Mac: away; SILL_TEST_REMOTE_ORIGIN=lan: home)", flush=True)
    for origin, away in (("", True), ("lan", False)):
        label = "away" if away else "away-lan"
        d = os.path.join(out, label + ".remote"); os.makedirs(d, exist_ok=True); os.chmod(d, 0o700)
        env = {"SILL_TEST_REMOTE_DIR": d}
        if origin: env["SILL_TEST_REMOTE_ORIGIN"] = origin
        h = Host(out, label, env, ["--remote", "--darken=away"])
        h.at(1.5)
        _, _, door = h.first("Remote access: listening on port")
        _, _, offer = h.first("sill://pair")
        port = re.search(r"port (\d+)", door or "")
        link = re.search(r"(sill://pair\S+)", offer or "")
        if not port or not link:
            h.stop(); verdict(False, f"{label}: no remote door or pairing link ({door!r}, {offer!r})"); continue
        ident = os.path.join(out, label + ".id")
        pair = subprocess.run([sys.executable, "-I", CLIENT, port.group(1), "2", "none", f"--pair-url={link.group(1)}", f"--identity={ident}"],
                              capture_output=True, text=True, timeout=30, env={**os.environ, **BASE_ENV})
        open(os.path.join(out, label + "-pair.client.log"), "w").write(pair.stdout + pair.stderr + f"\nEXIT {pair.returncode}\n")
        session = subprocess.run([sys.executable, "-I", CLIENT, port.group(1), "3", "desktop", "--tls", f"--identity={ident}"],
                                 capture_output=True, text=True, timeout=30, env={**os.environ, **BASE_ENV})
        open(os.path.join(out, label + ".client.log"), "w").write(session.stdout + session.stderr + f"\nEXIT {session.returncode}\n")
        h.at(time.time() - h.start + 1.0); h.stop()
        # The pairing client stays for its 2 s as a session of its own: away too, so the dark comes with it, and the
        # session after it comes back within the wait.
        dark = h.find(DARK)
        line = h.find("Privacy: this Mac’s screen is dark while a device away from home is connected (1 display).")
        back = h.find("Privacy: a device came back; this Mac’s screen stays dark.")
        if away:
            verdict(len(dark) == 1 and bool(line) and bool(back),
                    f"a paired device at the remote door from a relay on this Mac (away) darkens it: {len(dark)} raise, its session back within the wait")
        else:
            verdict(not dark and not line, f"the same device from this network (at home) darkens nothing: {len(dark)} raises")


def case_quit(out):
    print("== quit: SIGTERM while dark", flush=True)
    h = Host(out, "quit", {}, ["--darken=any"])
    c = client(h, "quit", 10, 1.0)
    h.at(3.5); h.stop()
    c.join()
    q = h.find("Privacy: Sill is quitting; this Mac’s screen is lit again.")
    lit = h.find(LIGHT)
    verdict(bool(q) and bool(lit) and lit[0][1] < q[0][1], f"lit, then its line, as the host quits: {len(lit)} lifts, {len(q)} lines")


def case_watchdog(out):
    print("== watchdog: the main thread stops 12 s while dark (SILL_TEST_PRIVACY_STALL)", flush=True)
    h = Host(out, "watchdog", {"SILL_TEST_PRIVACY_STALL": "12", "SILL_TEST_PRIVACY_GRACE": "2"}, ["--darken=any"])
    c = client(h, "watchdog", 20, 1.0)
    c.join(); h.at(26); h.stop()
    dark, _, _ = h.first(DARK)
    stops, _, _ = h.first("Test privacy: the main thread stops for 12 s in 1 s (SILL_TEST_PRIVACY_STALL).")
    goes, _, _ = h.first("Test privacy: the main thread goes on after 12 s (SILL_TEST_PRIVACY_STALL).")
    dog = h.find(WATCHDOG_DRY)
    verdict(dark is not None and stops is not None and stops >= dark, f"the black up at {dark}, the stall announced at {stops}")
    into = [round(t - (stops + 1), 2) for t, _, _ in dog] if stops is not None else []
    # The last beat comes up to a second before the stall, and the watchdog looks once a second: 9 to 11 s into it.
    verdict(len(dog) == 1 and 8.5 <= into[0] <= 12.5, f"the watchdog's dry run says once, 10 s after the last beat: {into} s into the stall")
    verdict(goes is not None and bool(dog) and goes > dog[0][0], f"the stall ends after it ({goes}) and nothing quits: the host goes on")
    left = h.find("Privacy: the last device left;")
    verdict(bool(left) and goes is not None and left[0][0] > goes and bool(h.find(LIGHT)),
            "the device's departure after the stall starts the wait and the screen is lit: the host still runs")


def app_defaults():
    """The darkening's keys the bare binary has saved in its defaults domain (SillMenuBar): {key: value}."""
    out = {}
    for k in APP_KEYS:
        r = subprocess.run(["defaults", "read", "SillMenuBar", k], capture_output=True, text=True)
        if r.returncode == 0: out[k] = r.stdout.strip()
    return out


def case_switch(out):
    print("== switch: Settings' switches and Sill's own Quit, in the bare SillMenuBar binary (a synthetic test host: the dry run)", flush=True)
    if not os.path.exists(APP):
        verdict(False, f"no {APP}: swift build -c release first"); return
    before = app_defaults()
    if before:
        verdict(False, f"the bare binary's defaults already hold {before} (another run's?): left alone, case not run"); return
    steps = ("2 darkenScreen=any; 8 darkenScreen=off; 10 darkenScreen=any; 13 darkenScreen=away,darkenKeysLock=0; 16 darkenScreen=any; "
             "17.5 darkenWait=30,darkenHidesPointer=0")
    try:
        h = Host(out, "switch", {}, ["-requirePairing", "NO", "-virtualDisplay", "0", "-SillLogFile", os.path.join(out, "switch.sill.log"),
                                     "-SillSetAfter", steps, "-SillQuitAfter", "19"], binary=APP, port_line=r"test clients connect to port (\d+)")
    except SystemExit as e:
        verdict(False, f"the bare binary as a test host: {e}")
        h = None
    if h is not None:
        c = client(h, "switch", 16, 4.0, ["--tls", "--identity=" + os.path.join(out, "switch.id"), "--pin=none"])
        h.at(23); h.stop(); c.join()
    saved = app_defaults()
    for k in saved: subprocess.run(["defaults", "delete", "SillMenuBar", k], capture_output=True)
    left = app_defaults()
    if h is None: return
    set_lines = h.find("SillSetAfter ")
    verdict(len(set_lines) == 6, f"the bare binary took the six changes (not Sill.app, which ignores them): {len(set_lines)}")
    dark = h.find(DARK)
    verdict(len(dark) == 3 and dark[0][0] >= 4.0, f"dark at the connect, and again at each switch back on: {[round(t, 2) for t, _, _ in dark]}")
    off_t, off_i, _ = h.first("Privacy: Darken this Mac’s screen is off; this Mac’s screen is lit again.")
    _, off_lit_i, _ = h.first(LIGHT, after=off_t or 0)
    verdict(off_t is not None and 8.0 <= off_t < 9.5 and off_lit_i is not None and off_lit_i > off_i,
            f"turned off: lit at once, its line, then the dry curtain lifts ({off_t})")
    scope_t, scope_i, _ = h.first("Privacy: Darken this Mac’s screen changed, and no device it darkens for is connected; this Mac’s screen is lit again.")
    _, scope_lit_i, _ = h.first(LIGHT, after=scope_t or 0)
    verdict(scope_t is not None and 13.0 <= scope_t < 14.5 and scope_lit_i is not None and scope_lit_i > scope_i,
            f"only away with the device at home: lit at once, with its line ({scope_t})")
    verdict(bool(h.find(HINT_PASS, after=15.9)), "keys passing: the hint at the next dark says ⌃⌘Q")
    quit_t, quit_i, _ = h.first("Privacy: Sill is quitting; this Mac’s screen is lit again.")
    _, quit_lit_i, _ = h.first(LIGHT, after=17.5)
    verdict(quit_t is not None and quit_t >= 19.0 and quit_lit_i is not None and quit_lit_i < quit_i,
            f"Sill's own Quit while dark: lit first, then its line ({quit_t})")
    verdict(len(h.find(LIGHT)) == 3, f"lit three times in all: {[round(t, 2) for t, _, _ in h.find(LIGHT)]}")
    shows = h.find(POINTER_SHOW, after=17.0)
    verdict(bool(shows) and shows[0][0] < 19.0 and not h.find(POINTER_ANY_HIDE, after=17.0),
            f"Hide the pointer too off while dark: it would show the pointer at once, and hides it no more ({[round(t, 2) for t, _, _ in shows]})")
    verdict(saved == {"darkenScreen": "1", "darkenOnlyAway": "0", "darkenKeysLock": "0", "darkenWait": "30", "darkenHidesPointer": "0"},
            f"HostSettings saved the switches as Settings would (on; whenever, so only away off; keys passing; 30 s; the pointer shown): {saved}")
    verdict(not left, f"and the case removed them from the bare binary's defaults: {left}")


def case_pointer(out):
    print("== pointer: hidden after the black, shown for the lock screen, before the lift and at SIGTERM; never with it off", flush=True)
    lock = os.path.join(out, "pointer.lock"); write(lock, "0")
    h = Host(out, "pointer", {"SILL_TEST_LOCKED_FILE": lock}, ["--darken=any"])
    c = client(h, "pointer", 12, 1.0)
    h.at(3.5); write(lock, "1")
    h.at(6.0); write(lock, "0")
    c.join(); h.at(15); h.stop()
    _, dark_i, _ = h.first(DARK)
    hides = h.find(POINTER_ANY_HIDE)
    verdict(dark_i is not None and len(hides) == 1 and hides[0][1] > dark_i,
            f"the pointer hidden once, after the black is up: {[round(t, 2) for t, _, _ in hides]}")
    verdict(len(hides) == 1 and hides[0][2].startswith(POINTER_HIDE),
            f"the two private calls found by name on this Mac, never called: {hides[0][2] if hides else None!r}")
    shows = h.find(POINTER_SHOW)
    lit = h.find(LIGHT)
    verdict(len(shows) == 1 and 3.4 <= shows[0][0] < 6.0, f"shown for the lock screen, the black staying under it: {[round(t, 2) for t, _, _ in shows]}")
    verdict(len(lit) == 1 and lit[0][0] >= 6.0 and bool(shows) and shows[0][1] < lit[0][1],
            "lit at the Mac's own unlock, the pointer shown before it and not hidden again")
    q = Host(out, "pointer-quit", {}, ["--darken=any"])
    cq = client(q, "pointer-quit", 10, 1.0)
    q.at(3.5); q.stop()
    cq.join()
    _, qshow, _ = q.first(POINTER_SHOW)
    _, qlit, _ = q.first(LIGHT)
    _, qquit, _ = q.first("Privacy: Sill is quitting; this Mac’s screen is lit again.")
    verdict(None not in (qshow, qlit, qquit) and qshow < qlit < qquit, "SIGTERM while dark: the pointer shown, then lit, then the quit's line")
    v = Host(out, "pointer-off", {}, ["--darken=any", "--darken-pointer=show"])
    cv = client(v, "pointer-off", 3, 1.0)
    cv.join(); v.at(11); v.stop()
    verdict(bool(v.find(DARK)) and bool(v.find(LIGHT)) and not v.find(POINTER_ANY_HIDE) and not v.find(POINTER_SHOW),
            "--darken-pointer=show: dark and lit, the pointer never touched")
    verdict(bool(v.find("; the pointer stays visible on the black.")), "and the start line says so")


def case_waits(out):
    print("== waits: Settings' wait, 5 s by default and 30 s with --darken-wait=30 (no SILL_TEST_PRIVACY_GRACE)", flush=True)
    for wait, args in ((5, []), (30, ["--darken-wait=30"])):
        label = f"waits-{wait}"
        h = Host(out, label, {}, ["--darken=any", *args])
        c = client(h, label, 2, 1.0)
        c.join(); h.at(1.0 + 2 + wait + 3); h.stop()
        left = h.find(f"Privacy: the last device left; this Mac’s screen stays dark for {wait} s in case it comes back, or until a key or click on it.")
        hint = h.find(f"Privacy (dry run): would show “This Mac’s screen comes back within {wait} seconds. Press any key or click to bring it back now.”")
        lit = h.find("Privacy: this Mac’s screen is lit again.")
        start = h.find(f"while a device is connected and for {wait} s after the last one leaves;")
        verdict(len(start) == 1, f"{wait} s: the start line says the wait")
        verdict(len(left) == 1 and len(hint) == 1 and hint[0][0] >= left[0][0], f"{wait} s: the departure's line, then the wait's hint, say it")
        gap = round(lit[0][0] - left[0][0], 2) if lit and left else None
        verdict(len(lit) == 1 and gap is not None and wait - 0.1 <= gap <= wait + 1.0, f"lit {wait} s after the last device left: {gap} s")


def case_keyleft(out):
    print("== keyleft: a key after the last device left lights the screen at once and locks nothing; a device back", flush=True)
    f = os.path.join(out, "keyleft.input")
    h = Host(out, "keyleft", {"SILL_TEST_PRIVACY_INPUT": f}, ["--darken=any"])
    c1 = client(h, "keyleft-1", 2, 1.0)
    c1.join()
    h.at(4.0); write(f, "key")
    c2 = client(h, "keyleft-2", 2, 6.0)
    c2.join()
    c3 = client(h, "keyleft-3", 2, 9.5)
    c3.join(); h.at(18.5); h.stop()
    left = h.find("Privacy: the last device left;")
    lit_key = h.find(LIT_KEY)
    verdict(len(lit_key) == 1 and bool(left) and 0 < lit_key[0][0] - left[0][0] < 2.0,
            f"a key 1 s after the last device left: lit at once ({[round(t - left[0][0], 2) for t, _, _ in lit_key] if left else None} s after)")
    verdict(not h.find(LOCK_DRY) and not h.find("Privacy: locking this Mac"), "and nothing locks, then or after")
    darks = h.find(DARK)
    verdict(len(darks) == 2 and darks[1][0] >= 6.0, f"a device back after the key: dark again at once ({[round(t, 2) for t, _, _ in darks]})")
    back = h.find("Privacy: a device came back; this Mac’s screen stays dark.")
    verdict(len(back) == 1 and back[0][0] >= 9.5, f"a device back inside the next wait: dark goes on ({[round(t, 2) for t, _, _ in back]})")
    lifts = h.find(LIGHT)
    verdict(len(lifts) == 2 and lifts[0][0] < 5.0 and lifts[1][0] > 14.0, f"lit twice: at the key, and 5 s after the last device left ({[round(t, 2) for t, _, _ in lifts]})")
    f2 = os.path.join(out, "keyleft-lock.input")
    g = Host(out, "keyleft-lock", {"SILL_TEST_PRIVACY_INPUT": f2, "SILL_TEST_PRIVACY_GRACE": "6"}, ["--darken=any", "--lock-after-session"])
    c4 = client(g, "keyleft-lock", 2, 1.0)
    c4.join()
    g.at(4.0); write(f2, "key")
    g.at(14); g.stop()
    gleft = g.find("Privacy: the last device left;")
    locking = g.find("Privacy: locking this Mac: someone pressed a key or clicked on it.")
    verdict(bool(gleft) and len(locking) == 1 and 0 < locking[0][0] - gleft[0][0] < 2.0 and not g.find(LIT_KEY),
            "with --lock-after-session a key in the wait locks at once, as before, and lights nothing")
    verdict(bool(gleft) and "and then while a lock is under way" in gleft[0][2], "the departure's line says a lock may follow")


CASES = {"order": case_order, "home": case_home, "away": case_away, "wait": case_wait, "keys": case_keys, "pass": case_pass,
         "takeback": case_takeback, "hold": case_hold, "quit": case_quit, "watchdog": case_watchdog, "switch": case_switch,
         "pointer": case_pointer, "waits": case_waits, "keyleft": case_keyleft}

if __name__ == "__main__":
    if len(sys.argv) < 2: raise SystemExit(__doc__)
    out = os.path.abspath(sys.argv[1]); os.makedirs(out, exist_ok=True)
    names = sys.argv[2:] or ["all"]
    if names == ["all"]: names = list(CASES)
    if not os.path.exists(HOST): raise SystemExit(f"no {HOST}: swift build -c release first")
    for n in names: CASES[n](out)
    bad = [w for ok, w in verdicts if not ok]
    print(f"darken live: {len(verdicts) - len(bad)} of {len(verdicts)} verdicts ok")
    sys.exit(1 if bad else 0)
