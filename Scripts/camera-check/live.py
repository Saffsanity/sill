#!/usr/bin/env python3
"""TEST ONLY: the devices' cameras on the Mac against synthetic test hosts on loopback (docs/camera-plan.md §13.2,
gates H1 to H5 and H7 to H10, H2 as a frame that does not decode). Each case starts .build/release/SillHost
--synthetic --pairing (a throwaway identity in a folder of
the test's own) with SILL_TEST_LOOPBACK, SILL_TEST_SOFTWARE_ENCODER, SILL_TEST_NO_ROUTER and SILL_TEST_NO_SCREEN, so
nothing touches the hardware encoder, the router or ScreenCaptureKit, and SILL_TEST_CAMERA (a counter, or PNGs in a
folder under OUT; its decoder VideoToolbox's software one) with SILL_TEST_CAMERA_DEMAND scripting what Sill Camera's
apps would do. It pairs test clients by the host's links and drives Scripts/sillclient.py's --camera (the fixture,
Scripts/camera/fixture-640x360.bin, made with VideoToolbox's software encoder), --camera-claim, --camera-stop,
--camera-pause, --camera-corrupt and --raw46 against it. No camera, no window, no encoder of this Mac's. Every
host runs under a
minute. Prints a verdict per rule; exits 1 on any FAIL.

    python3 Scripts/camera-check/live.py OUT [live|two|lock|unpaired|hostile|nohook|corrupt|move|stdout|all]

stdout (H9) compares this build's CLI with main's, whose SillHost SILL_MAIN_HOST names (a release build of origin/main
made beside this one); without it, `stdout` fails and `all` skips it, saying so."""
import difflib, os, re, signal, subprocess, sys, threading, time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
HOST = os.path.join(ROOT, ".build/release/SillHost")
CLIENT = os.path.join(ROOT, "Scripts/sillclient.py")
# SILL_CAMERA_FIXTURE: another fixture of the same format, such as the device's own encoder's (encoder.sh OUT.bin).
FIXTURE = os.environ.get("SILL_CAMERA_FIXTURE") or os.path.join(ROOT, "Scripts/camera/fixture-640x360.bin")
BASE_ENV = {"SILL_TEST_LOOPBACK": "1", "SILL_TEST_SOFTWARE_ENCODER": "1", "SILL_TEST_NO_ROUTER": "1", "SILL_TEST_NO_SCREEN": "1"}
verdicts = []


def verdict(ok, what):
    verdicts.append((ok, what))
    print(("ok   " if ok else "FAIL ") + what, flush=True)


class Host:
    """One synthetic --pairing host with a test Sill Camera: its stdout's lines and its port."""
    def __init__(self, out, label, env=None, camera="count", binary=HOST):
        self.out, self.label, self.lines = out, label, []
        remote = os.path.join(out, label + ".remote"); os.makedirs(remote, exist_ok=True); os.chmod(remote, 0o700)
        e = dict(os.environ); e.update(BASE_ENV); e.update({"SILL_TEST_REMOTE_DIR": remote, "SILL_TEST_ASK_FROM_THIS_MAC": "1"})
        if camera: e["SILL_TEST_CAMERA"] = camera
        e.update(env or {})
        self.start = time.time()
        self.p = subprocess.Popen(["nice", "-n", "10", binary, "--synthetic", "--pairing"], stdout=subprocess.PIPE,
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
        """Waits for the host's next [1s] line (printed while anything was counted, a client or not), so a count
        read after a client leaves includes what the host did since its last line."""
        n = len(self.lines); end = time.time() + timeout
        while time.time() < end:
            if any(l.startswith("[1s]") for _, l in self.lines[n:]): return
            time.sleep(0.1)

    def link(self, after=0):
        """The newest pairing link printed after `after` lines."""
        for _ in range(60):
            links = [m.group(1) for _, l in self.lines[after:] for m in [re.search(r"(sill://pair\S+)", l)] if m]
            if links: return links[-1]
            time.sleep(0.1)
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
    """A paired device as the host's lines name it: its name, then its model in parentheses ("ipadA (sillclient)")."""
    return re.escape(device) + r" \(sillclient\)"


def states(text):
    return re.findall(r"camera state at [\d.]+s: (\S+)(?: app=(\S+))?(?: holder=(\S+))?", text)


def camera_line(text):
    m = re.search(r"CAMERA sent (\d+) frames \((\d+) keyframes\) in (\d+) epochs; (\d+) demands \((\d+) with a keyframe\)", text)
    return tuple(int(x) for x in m.groups()) if m else None


def case_live(out):
    print("== live (H1): an app opens Sill Camera at 4 s and closes it at 10 s; the paired device's frames decode between", flush=True)
    dump = os.path.join(out, "live.frames"); os.makedirs(dump, exist_ok=True)
    h = Host(out, "live", camera=f"dump:{dump}", env={"SILL_TEST_CAMERA_DEMAND": "4 on 640x360@30 FaceTime; 10 off", "SILL_TEST_CAMERA_LOG": "1"})
    try:
        ident = paired(h, out, "ipad")
        if not ident: return
        text, code = client(h, "session", 14, "--tls", "--stats", "--device=ipad", f"--camera={FIXTURE}",
                            "--expect=cameraState=idle,camera=1", identity=ident)
        verdict(code == 0 and "EXPECT ok" in text, "the session ends idle, its list saying camera=1")
        st = states(text)
        verdict([s[0] for s in st][:3] == ["idle", "inUse", "idle"] and st[1][1] == "FaceTime",
                f"kind 16's camera: idle, inUse with the app's name, idle again: {st}")
        verdict(re.search(r"camera demand at [\d.]+s: 640x360@30 keyframe=1 maxBitrate=625000 token=1", text) is not None,
                "one demand: the app's size and rate, a keyframe, 625 kbit/s at most")
        c = camera_line(text)
        verdict(c is not None and 150 <= c[0] <= 200 and c[2] == 1, f"the client sent about 6 s of frames in one epoch: {c}")
        decoded = h.count("cam.decoded")
        verdict(c is not None and c[0] - 3 <= decoded <= c[0], f"the host decoded every frame sent while wanted ({decoded} of {c and c[0]})")
        verdict(bool(h.all(r"^Camera: .*'s camera is live: 640×360, 30 fps, HEVC, 0\.4 Mbps\.$")), "the live line")
        verdict(bool(h.all(r"^client ipad: .*, camera (2[89]|3[0-2]) fps \d+\.\d Mbps$")), "the client line says the device's camera that second (ClientStats' camera fields)")
        pngs = sorted(f for f in os.listdir(dump) if f.endswith(".png"))
        verdict(len(pngs) >= 5 and pngs[0] == "frame-00001.png", f"every 30th frame dumped as a PNG: {pngs[:3]}…")
        dropped = h.all(r"cam\.(refused|dropped)")
        verdict(not dropped, f"nothing refused or dropped: {dropped[:2]}")
        verdict(bool(h.all(rf"^Test camera: Sill Camera shows {named('ipad')}\.$")), "Sill Camera showed the holder")
    finally:
        h.stop()


def case_two(out):
    print("== two (H3): A offers, B claims and takes the camera, B stops and A has it again", flush=True)
    h = Host(out, "two", env={"SILL_TEST_CAMERA_DEMAND": "2 on 1280x720@30 Zoom"})
    try:
        a = paired(h, out, "ipadA"); b = paired(h, out, "iphoneB")
        if not (a and b): return
        pa = client(h, "A", 20, "--tls", "--device=ipadA", f"--camera={FIXTURE}", identity=a, background=True)
        time.sleep(4)
        pb = client(h, "B", 12, "--tls", "--device=iphoneB", f"--camera={FIXTURE}", "--camera-claim@3", "--camera-stop@8",
                    identity=b, background=True)
        ta, tb = finished(pa), finished(pb)
        sa, sb = [s[0] for s in states(ta)], [s[0] for s in states(tb)]
        verdict(sa[:3] == ["idle", "inUse", "another"] and "inUse" in sa[3:], f"A: idle, in use, another, then in use again: {sa}")
        verdict(any(s[0] == "another" and s[2] == "iphoneB" for s in states(ta)), "A heard the holder's name")
        verdict(sb[:3] == ["another", "inUse", "another"] or sb[:2] == ["another", "inUse"], f"B: another until its claim, then in use: {sb}")
        verdict(bool(h.all(rf"^Camera: {named('iphoneB')} took Sill Camera from {named('ipadA')}\.$")), "the take's line")
        verdict(bool(h.all(rf"^Camera: {named('iphoneB')} stopped sharing its camera\.$"))
                and bool(h.all(rf"^Camera: {named('ipadA')} is Sill Camera now\.$")), "B's stop, and A's return")
        ca, cb = camera_line(ta), camera_line(tb)
        verdict(ca is not None and ca[2] >= 2 and cb is not None and cb[2] == 1, f"A sent two epochs, B one: A {ca}, B {cb}")
    finally:
        h.stop()


def case_lock(out):
    print("== lock (H4): a locked screen drops the camera from the list and kind 16; the unlock brings it back with a keyframe", flush=True)
    f = os.path.join(out, "lock.reading"); open(f, "w").write("0")
    h = Host(out, "lock", env={"SILL_TEST_LOCKED_FILE": f, "SILL_TEST_CAMERA_DEMAND": "1 on 640x360@30"})
    try:
        ident = paired(h, out, "ipad")
        if not ident: return
        p = client(h, "session", 22, "--tls", "--device=ipad", f"--camera={FIXTURE}", "--raw46=020001000000050000000226@9",
                   identity=ident, background=True)
        time.sleep(7); open(f, "w").write("1")
        time.sleep(6); open(f, "w").write("0")
        text = finished(p)
        st = [s[0] for s in states(text)]
        verdict(st[:3] == ["idle", "inUse", "none"] and st[3:4] == ["inUse"], f"kind 16: in use, none while locked, in use again: {st}")
        verdict(re.search(r"windowList: .* locked=1", text) is not None and re.search(r"windowList: [^\n]* camera=1[^\n]* locked=1", text) is None,
                "the locked list says no camera")
        verdict(h.count("cam.refused.locked") >= 1, f"a frame sent while locked refused ({h.count('cam.refused.locked')})")
        demands = re.findall(r"camera demand at ([\d.]+)s: \S+ keyframe=1", text)
        verdict(len(demands) >= 2, f"a keyframe demanded at the start and again after the unlock: {demands}")
        c = camera_line(text)
        verdict(c is not None and c[2] >= 2, f"a new epoch after the unlock: {c}")
    finally:
        h.stop()


def case_unpaired(out):
    print("== unpaired (H5): Require pairing off lets an unpaired device in, never its camera", flush=True)
    h = Host(out, "unpaired", env={"SILL_TEST_REQUIRE_PAIRING": "0", "SILL_TEST_CAMERA_DEMAND": "1 on 640x360@30"})
    try:
        ident = os.path.join(out, "unpaired.stranger.id")
        text, code = client(h, "stranger", 6, "--tls", "--pin=none", "--device=stranger", f"--camera={FIXTURE}", "--camera-claim@2",
                            "--expect=cameraState=unpaired", identity=ident)
        verdict(code == 0 and "EXPECT ok" in text, "kind 16 says unpaired")
        c = camera_line(text)
        verdict(c is not None and c[0] == 0, f"no frame sent: {c}")
        verdict(h.count("cam.refused.unpaired") >= 1 and bool(h.all(r"^Camera: refused from .*: not paired\.$")), "its claim refused, said once")
    finally:
        h.stop()


def case_hostile(out):
    print("== hostile (H7): malformed, unknown, oversized and wrong-way kind 46: dropped and counted, the session kept", flush=True)
    h = Host(out, "hostile", env={"SILL_TEST_CAMERA_DEMAND": "1 on 640x360@30"})
    try:
        ident = paired(h, out, "ipad")
        if not ident: return
        big = "02" + "0001" + "00000000" + "00" * 262_145
        text, code = client(h, "session", 10, "--tls", "--device=ipad", f"--camera={FIXTURE}",
                            "--raw46=01ff@2", "--raw46=09@2.1", "--raw46=03" + "7b7d" + "@2.2", f"--raw46={big}@2.3",
                            "--raw46=01" + "7b227769647468223a31357d" + "@2.4", "--expect=cameraState=inUse", identity=ident)
        verdict(code == 0 and "EXPECT ok" in text and "EOF from host" not in text, "the session kept, still in use")
        verdict(h.count("cam.dropped.malformed") >= 4, f"bad JSON, an unknown type, an oversize frame and an odd width dropped ({h.count('cam.dropped.malformed')})")
        verdict(h.count("cam.dropped.wrongWay") >= 1, "a type 3 from a device dropped")
        h.next_tick()    # the frames decoded after the host's last [1s] line, before the client left
        c = camera_line(text)
        verdict(c is not None and h.count("cam.decoded") >= c[0] - 3, f"its real frames still decoded ({h.count('cam.decoded')} of {c and c[0]})")
    finally:
        h.stop()


def case_nohook(out):
    print("== nohook (H8): a test host without SILL_TEST_CAMERA lists no camera; a kind 46 sent anyway is ignored", flush=True)
    h = Host(out, "nohook", camera=None)
    try:
        ident = paired(h, out, "ipad")
        if not ident: return
        text, code = client(h, "session", 5, "--tls", "--device=ipad", f"--camera={FIXTURE}", "--raw46=01" + "7b7d" + "@2",
                            "--expect=camera=none,cameraState=none", identity=ident)
        verdict(code == 0 and "EXPECT ok" in text and "EOF from host" not in text, "no camera in the list or kind 16; the session kept")
        said = h.all(r"^Camera:|^Test camera:|cam\.")
        verdict(not said, f"the host says nothing of a camera: {said[:2]}")
    finally:
        h.stop()


def case_corrupt(out):
    print("== corrupt (H2): a frame that does not decode: the host asks for a keyframe within a second, and decoding resumes at it", flush=True)
    h = Host(out, "corrupt", env={"SILL_TEST_CAMERA_DEMAND": "1 on 640x360@30"})
    try:
        ident = paired(h, out, "ipad")
        if not ident: return
        text, code = client(h, "session", 9, "--tls", "--device=ipad", f"--camera={FIXTURE}", "--camera-corrupt=40",
                            "--camera-pause=background@6.5", "--expect=cameraState=inUse", identity=ident)
        verdict(code == 0 and "EXPECT ok" in text and "EOF from host" not in text, "the session kept, still in use")
        sent = re.search(r"camera frame 40 \(epoch \d+, seq \d+\) sent corrupted at ([\d.]+)s", text)
        asks = [(float(t), int(tok)) for t, tok in re.findall(r"camera demand at ([\d.]+)s: \S+ keyframe=1 maxBitrate=\d+ token=(\d+)", text)]
        later = [a for a in asks if sent and a[0] >= float(sent.group(1))]
        verdict(sent is not None and len(later) == 1 and later[0][0] - float(sent.group(1)) < 1.0,
                f"one keyframe asked within a second of the frame that did not decode: sent at {sent and sent.group(1)}, asks {asks}")
        verdict(bool(h.all(r"^Camera: a frame from .* did not decode \(-?\d+\); asked for a keyframe\.$")) and h.count("cam.decodeFailed") >= 1,
                f"the host's line, and its count ({h.count('cam.decodeFailed')} failed)")
        h.next_tick()
        c = camera_line(text)
        skipped = h.count("cam.dropped.awaitingKeyframe")
        decoded = h.count("cam.decoded")
        # On loopback the ask comes back before the next frame goes, so none may have to wait for the keyframe.
        verdict(c is not None and decoded >= c[0] - 1 - skipped - 3,
                f"decoding resumed at the keyframe: {decoded} of {c and c[0]} decoded, {skipped} waited for it, the bad one not")
        verdict(h.count("cam.keyframeAsked") == 1, f"one ask, not one per frame that waited ({h.count('cam.keyframeAsked')})")
        verdict(bool(h.all(r"^client ipad: .*, camera paused \(background\)$")), "the client line says the device's pause (ClientStats' cameraPause)")
    finally:
        h.stop()


def case_move(out):
    print("== move (H10): the session's connection goes and the same device comes back within 10 s: it keeps the camera", flush=True)
    h = Host(out, "move", env={"SILL_TEST_CAMERA_DEMAND": "1 on 640x360@30 FaceTime"})
    try:
        ident = paired(h, out, "ipad")
        if not ident: return
        ta, ca = client(h, "first", 5, "--tls", "--device=ipad", f"--camera={FIXTURE}", identity=ident)
        time.sleep(2)                        # the device away for two seconds: its offer stands (CameraHostPolicy.grace)
        tb, cb = client(h, "second", 6, "--tls", "--device=ipad", f"--camera={FIXTURE}", "--expect=cameraState=inUse", identity=ident)
        sa, sb = [s[0] for s in states(ta)], [s[0] for s in states(tb)]
        verdict("inUse" in sa and code_ok(ca), f"the first connection: in use: {sa}")
        verdict(code_ok(cb) and "EXPECT ok" in tb and sb[-1:] == ["inUse"] and "another" not in sb,
                f"the second connection, the same device: in use again, never another's: {sb}")
        verdict(not h.all(r"is gone; Sill Camera is free|is Sill Camera now|took Sill Camera"),
                f"the holder kept through the gap: {h.all(r'is gone|Sill Camera now|took Sill Camera')[:2]}")
        h.next_tick()
        a, b = camera_line(ta), camera_line(tb)
        decoded = h.count("cam.decoded")
        verdict(a is not None and b is not None and b[2] == 1 and decoded >= a[0] + b[0] - 6,
                f"the second connection's new epoch decoded too ({decoded} of {a and a[0]} + {b and b[0]})")
        verdict(len(h.all(r"^Camera: .*'s camera is live: 640×360")) == 2, "a live line for each connection's epoch")
    finally:
        h.stop()


def code_ok(code):
    return code == 0


def normalized(h):
    # A host's lines with what differs from run to run made the same: the pairing's codes and links, keys, every
    # number (ports, counts, times); the periodic lines ([1s], [30s]), the client lines and the installed apps' line,
    # whose count and timing vary, left out. Sorted: two runs of the same build may print two lines in either order.
    out = []
    for _, l in h.lines:
        if l.startswith("[") or re.match(r"client \S+: \d+ fps", l) or l.startswith("installed apps:"): continue
        l = re.sub(r"sill://pair\S+", "LINK", l)
        l = re.sub(r"\(key [^)]*\)", "(key KEY)", l)
        out.append(re.sub(r"\d+", "N", l))
    return sorted(out)


def case_stdout(out):
    print("== stdout (H9): the CLI without the camera's hooks prints what main's prints, at the same flags and the same session", flush=True)
    main = os.environ.get("SILL_MAIN_HOST")
    if not main or not os.path.exists(main):
        # Asked for by name it fails; within `all`, a run without main's build skips it, saying so.
        if sys.argv[2:3] == ["stdout"]: verdict(False, "no build of main to compare with: SILL_MAIN_HOST names none")
        else: print("skipped: SILL_MAIN_HOST names no build of main", flush=True)
        return
    texts = []
    for label, binary in (("stdout-branch", HOST), ("stdout-main", main)):
        h = Host(out, label, camera=None, binary=binary)
        try:
            ident = paired(h, out, "ipad")
            if not ident: return
            text, code = client(h, "session", 5, "--tls", "--device=ipad", f"--camera={FIXTURE}", "--raw46=017b7d@2", identity=ident)
            verdict(code == 0 and "EOF from host" not in text, f"{label}: the session ran its 5 s")
            h.next_tick()
        finally:
            h.stop()
        texts.append(normalized(h))
    diff = [d for d in difflib.unified_diff(texts[1], texts[0], "main", "branch", lineterm="") if d[:1] in "+-" and d[:3] not in ("+++", "---")]
    verdict(not diff and len(texts[0]) >= 8, f"the same {len(texts[0])} lines, numbers, codes, keys and ports aside: {diff[:6]}")


CASES = {"live": case_live, "two": case_two, "lock": case_lock, "unpaired": case_unpaired, "hostile": case_hostile, "nohook": case_nohook,
         "corrupt": case_corrupt, "move": case_move, "stdout": case_stdout}

if __name__ == "__main__":
    if len(sys.argv) < 2: print(__doc__); sys.exit(2)
    out = os.path.abspath(sys.argv[1]); os.makedirs(out, exist_ok=True)
    which = sys.argv[2] if len(sys.argv) > 2 else "all"
    if not os.path.exists(HOST): print(f"no {HOST}: swift build -c release first (through heavy.sh)"); sys.exit(2)
    for name in (CASES if which == "all" else [which]):
        CASES[name](out)
    bad = [w for ok, w in verdicts if not ok]
    print(f"{len(verdicts) - len(bad)} of {len(verdicts)} verdicts ok")
    sys.exit(1 if bad else 0)
