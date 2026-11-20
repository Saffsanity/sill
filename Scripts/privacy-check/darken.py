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

    Scripts/privacy-check/darken.py OUT [order|home|away|wait|keys|pass|takeback|hold|quit|all]

Needs .build/release/SillHost. Exits 1 when a verdict fails."""
import os, re, signal, subprocess, sys, threading, time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
HOST = os.path.join(ROOT, ".build/release/SillHost")
CLIENT = os.path.join(ROOT, "Scripts/sillclient.py")
BASE_ENV = {"SILL_TEST_LOOPBACK": "1", "SILL_TEST_SOFTWARE_ENCODER": "1", "SILL_TEST_NO_ROUTER": "1", "SILL_TEST_NO_SCREEN": "1",
            "SILL_TEST_LOCK_IGNORE_MAC": "1", "SILL_TEST_PRIVACY_DISPLAYS": "1"}
DARK = "Privacy (dry run): would darken 1 display; nothing is drawn."
LIGHT = "Privacy (dry run): would light this Mac’s screen again; nothing was drawn."
HINT_LOCK = "Privacy (dry run): would show “This Mac is in use from another device. Press any key to lock it.”"
HINT_PASS = "Privacy (dry run): would show “This Mac is in use from another device. To use it here, press Control-Command-Q, then unlock it.”"
DRY_CURTAIN = ("Privacy (dry run): would darken", "Privacy (dry run): would light", "Privacy (dry run): would show")
DRY_START = " A dry run here (only Sill.app itself darkens a Mac’s screen): it says what it would do."
LOCK_DRY = "Privacy (dry run): would lock this Mac now; nothing is locked."

verdicts = []


def verdict(ok, what):
    verdicts.append((ok, what))
    print(("ok   " if ok else "FAIL ") + what, flush=True)


def write(path, text):
    with open(path, "w") as f: f.write(text)


class Host:
    """One synthetic host: its stdout's lines with the time each was read, its port."""
    def __init__(self, out, label, env, args=()):
        self.lines, self.out, self.label = [], out, label
        e = dict(os.environ); e.update(BASE_ENV); e.update(env)
        self.start = time.time()
        self.p = subprocess.Popen(["nice", "-n", "10", HOST, "--synthetic", *args], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                  env=e, start_new_session=True, text=True, bufsize=1)
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
    start = h.find("Privacy: Darken this Mac’s screen is on: while a device away from home is connected; a key or click on this Mac locks it.")
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
    left = h.find("Privacy: the last device left; this Mac’s screen stays dark for 3 s in case it comes back.")
    back = h.find("Privacy: a device came back within 3 s; this Mac’s screen stays dark.")
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
        back = h.find("Privacy: a device came back within 30 s; this Mac’s screen stays dark.")
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


CASES = {"order": case_order, "home": case_home, "away": case_away, "wait": case_wait, "keys": case_keys, "pass": case_pass,
         "takeback": case_takeback, "hold": case_hold, "quit": case_quit}

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
