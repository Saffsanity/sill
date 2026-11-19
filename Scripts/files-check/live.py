#!/usr/bin/env python3
"""TEST ONLY: files between a device and the Mac against synthetic test hosts on loopback (docs/files-plan.md §12.2,
gates H3 to H6). Each case starts .build/release/SillHost --synthetic --pairing (a throwaway identity in a folder of
the test's own) with SILL_TEST_LOOPBACK, SILL_TEST_SOFTWARE_ENCODER, SILL_TEST_NO_ROUTER and SILL_TEST_NO_SCREEN, so
nothing touches the hardware encoder, the router, ScreenCaptureKit or this Mac's Downloads (SILL_TEST_FILES_DIR is a
folder under OUT), pairs a test client by the host's link, and drives Scripts/sillclient.py's --send-file, --raw49,
--raw34 and --cancel-files against it, and for the Mac's files to a device (H6) SILL_TEST_FILES_OFFER and
SILL_TEST_FILES_PICK on the host with the client's --accept-files, --decline-files, --pick-files, --cancel-receive and
--receive-pace. Every host runs under a minute. Prints a verdict per rule; exits 1 on any FAIL.

    python3 Scripts/files-check/live.py OUT [send|refuse|hostile|lock|give|all]
    python3 Scripts/files-check/live.py OUT h2 --base=MAIN_SILLHOST   H2: the CLI's stdout against main's (about 75 s)
    python3 Scripts/files-check/live.py OUT h2 --logs=DIR             H2 judged again on the logs a run saved in DIR"""
import hashlib, json, os, plistlib, random, re, shutil, signal, subprocess, sys, threading, time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
HOST = os.path.join(ROOT, ".build/release/SillHost")
CLIENT = os.path.join(ROOT, "Scripts/sillclient.py")
BASE_ENV = {"SILL_TEST_LOOPBACK": "1", "SILL_TEST_SOFTWARE_ENCODER": "1", "SILL_TEST_NO_ROUTER": "1", "SILL_TEST_NO_SCREEN": "1",
            "SILL_TEST_FILES_LOG": "1"}
verdicts = []


def verdict(ok, what):
    verdicts.append((ok, what))
    print(("ok   " if ok else "FAIL ") + what, flush=True)


class Host:
    """One synthetic --pairing host: its stdout's lines, its port, its files folder."""
    def __init__(self, out, label, env=None, args=()):
        self.out, self.label, self.lines = out, label, []
        self.files = os.path.join(out, label + ".files"); os.makedirs(self.files, exist_ok=True)
        remote = os.path.join(out, label + ".remote"); os.makedirs(remote, exist_ok=True); os.chmod(remote, 0o700)
        e = dict(os.environ); e.update(BASE_ENV); e.update({"SILL_TEST_FILES_DIR": self.files, "SILL_TEST_REMOTE_DIR": remote})
        e.update(env or {})
        self.start = time.time()
        self.p = subprocess.Popen(["nice", "-n", "10", HOST, "--synthetic", "--pairing", *args], stdout=subprocess.PIPE,
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

    def link(self):
        for _ in range(50):
            for _, l in self.lines:
                m = re.search(r"(sill://pair\S+)", l)
                if m: return m.group(1)
            time.sleep(0.1)
        return None

    def kept(self):
        return sorted(n for n in os.listdir(self.files) if n != ".Sill Incoming")

    def partials(self):
        d = os.path.join(self.files, ".Sill Incoming")
        return sorted(os.listdir(d)) if os.path.isdir(d) else []


def client(host, label, seconds, *args, identity=None):
    r = subprocess.run([sys.executable, "-I", CLIENT, host.port, str(seconds), "none", *args,
                        *( [f"--identity={identity}"] if identity else [])],
                       capture_output=True, text=True, timeout=seconds + 30, env={**os.environ, **BASE_ENV})
    text = r.stdout + r.stderr + f"\nEXIT {r.returncode}\n"
    open(os.path.join(host.out, f"{host.label}-{label}.client.log"), "w").write(text)
    return text, r.returncode


def paired(host, out):
    """A client paired by the host's link: its identity folder."""
    ident = os.path.join(out, host.label + ".id")
    link = host.link()
    if link is None: verdict(False, f"{host.label}: the host printed no pairing link"); return None
    text, code = client(host, "pair", 1, f"--pair-url={link}", identity=ident)
    if "PAIR ok" not in text: verdict(False, f"{host.label}: pairing failed: {text[-300:]}"); return None
    return ident


def locked_lists(text):
    """(ok, what) for a client that connected to a host whose lock file already said locked: from the first list that
    says locked=1 on, no list says files= (and at least one does say it). A test host reads its SILL_TEST_LOCKED_FILE
    only once a second while a device is connected (SessionLock's polls) and not at all without one, so the list sent
    as the client connects may still be the unlocked one; the real Mac's witnesses are notifications, read at once."""
    lists = re.findall(r"windowList: .*", text)
    first = next((i for i, l in enumerate(lists) if "locked=1" in l), None)
    after = lists[first:] if first is not None else []
    ok = bool(after) and all("files=" not in l for l in after)
    return ok, f"once the host reads the lock, its lists say locked=1 and no files ({len(after)} of {len(lists)} lists)"


def make(folder, name, size, seed=0):
    path = os.path.join(folder, name)
    rnd = random.Random(seed)
    with open(path, "wb") as f: f.write(bytes(rnd.getrandbits(8) for _ in range(size)) if size < 200_000 else os.urandom(size))
    return path


def sha(path): return hashlib.sha256(open(path, "rb").read()).hexdigest()


def xattr(path, name):
    """An extended attribute's bytes (`xattr -px`: hex, so a binary plist such as Where from reads whole), or None."""
    r = subprocess.run(["xattr", "-px", name, path], capture_output=True, text=True)
    return bytes.fromhex("".join(r.stdout.split())) if r.returncode == 0 else None


def where_from(path):
    """The Where from list Finder's Get Info shows (com.apple.metadata:kMDItemWhereFroms, a binary plist), or None."""
    b = xattr(path, "com.apple.metadata:kMDItemWhereFroms")
    try: return plistlib.loads(b) if b is not None else None
    except Exception: return None


def case_send(out):
    print("== send: files to a paired session, kept whole and marked", flush=True)
    src = os.path.join(out, "send.src"); os.makedirs(src, exist_ok=True)
    sizes = [("empty.txt", 0), ("one.bin", 1), ("chunk.bin", 65536), ("chunk-plus-one.bin", 65537), ("three-mb.bin", 3_000_000)]
    paths = [make(src, n, s, i) for i, (n, s) in enumerate(sizes)]
    h = Host(out, "send")
    try:
        ident = paired(h, out)
        if not ident: return
        text, code = client(h, "send", 20, "--tls", "--stats", f"--send-file={src}@2", "--expect-files=done", identity=ident)
        verdict(code == 0 and "EXPECT-FILES ok" in text, f"the session's transfer is done: {re.findall(r'files done: .*', text)[:1]}")
        verdict(re.search(r"windowList: .* files=1", text) is not None, "the list says files=1 (a host with an identity, the switch on)")
        kept = h.kept()
        verdict(kept == sorted(n for n, _ in sizes), f"every file kept under its name: {kept}")
        same = all(os.path.exists(os.path.join(h.files, n)) and sha(os.path.join(h.files, n)) == sha(p) for (n, _), p in zip(sizes, paths))
        verdict(same, "each byte for byte the source")
        q = xattr(os.path.join(h.files, "three-mb.bin"), "com.apple.quarantine")
        q = q.decode("utf-8", "replace") if q is not None else None
        verdict(q is not None and q.split(";")[0] != "", f"quarantined: {q}")
        wf = where_from(os.path.join(h.files, "three-mb.bin"))
        verdict(isinstance(wf, list) and any(isinstance(w, str) and w.endswith(", through Sill") for w in wf), f"a Where from: {wf}")
        mode = oct(os.stat(os.path.join(h.files, "three-mb.bin")).st_mode & 0o777)
        verdict(mode == "0o644", f"mode 0644: {mode}")
        verdict(h.partials() == [], f"nothing left in .Sill Incoming: {h.partials()}")
        saved = h.all(r"^Files: saved 5 files")
        verdict(bool(saved), f"one saved line, counts and sizes: {saved[:1]}")
        names = [n for n, _ in sizes if n != "one.bin"]
        leaked = [l for _, l in h.lines if any(n in l for n in names)]
        verdict(not leaked, f"no file name in the host's output: {leaked[:2]}")
    finally:
        h.stop()
    # A host of its own for the rest, so each runs under a minute.
    h = Host(out, "send500")
    try:
        ident = paired(h, out)
        if not ident: return
        # 500 files of 1 KB in one transfer; 501 refused tooMany.
        many = os.path.join(out, "send.many"); os.makedirs(many, exist_ok=True)
        for i in range(500): make(many, f"f{i:03}.txt", 1000, i)
        text, code = client(h, "500", 25, "--tls", f"--send-file={many}@1", "--expect-files=done", identity=ident)
        verdict(code == 0, f"500 files of 1 KB: done ({re.findall(r'files done: .*', text)[:1]})")
        verdict(len(h.kept()) == 500, f"500 files kept: {len(h.kept())}")
        make(many, "f500.txt", 1000, 500)
        text, code = client(h, "501", 6, "--tls", f"--send-file={many}@1", "--expect-files=answer:tooMany", identity=ident)
        verdict(code == 0, "501 files: refused tooMany before any byte")
        # The same name again: numbered, never replaced.
        text, code = client(h, "again", 8, "--tls", f"--send-file={os.path.join(many, 'f000.txt')}@1", "--expect-files=done", identity=ident)
        verdict(code == 0 and os.path.exists(os.path.join(h.files, "f000 2.txt")), "the same name again: f000 2.txt")
    finally:
        h.stop()


def case_refuse(out):
    print("== refuse: not paired, the switch off, locked, no room", flush=True)
    src = os.path.join(out, "refuse.src"); os.makedirs(src, exist_ok=True)
    one = make(src, "a.bin", 100_000, 1)
    # Require pairing off: an unpaired key is a session, and its files are refused notPaired.
    h = Host(out, "unpaired", {"SILL_TEST_REQUIRE_PAIRING": "0"})
    try:
        text, code = client(h, "u", 6, "--tls", "--pin=none", f"--send-file={one}@1", "--expect-files=answer:notPaired",
                            identity=os.path.join(out, "unpaired.idU"))
        verdict(code == 0 and "paired=0" in text, "an unpaired session: kind 16 says paired=0, its offer refused notPaired")
        verdict(h.kept() == [] and h.partials() == [], "nothing written")
    finally:
        h.stop()
    h = Host(out, "off", args=["--no-files"])
    try:
        ident = paired(h, out)
        if ident:
            text, code = client(h, "off", 6, "--tls", f"--send-file={one}@1", "--expect-files=answer:off", identity=ident)
            verdict(code == 0 and re.search(r"windowList: .* files=0", text) is not None, "--no-files: the list says files=0, an offer refused off")
    finally:
        h.stop()
    h = Host(out, "noroom", {"SILL_TEST_FILES_FREE": "1000"})
    try:
        ident = paired(h, out)
        if ident:
            text, code = client(h, "noroom", 6, "--tls", f"--send-file={one}@1", "--expect-files=answer:noRoom", identity=ident)
            verdict(code == 0 and h.kept() == [], "1,000 bytes free: refused noRoom, nothing written")
            refused = h.all(r"^Files: refused")
            verdict(bool(refused), f"the refusals' line: {refused[:1]}")
    finally:
        h.stop()
    lock = os.path.join(out, "locked.lockfile"); open(lock, "w").write("0")
    h = Host(out, "locked", {"SILL_TEST_LOCKED_FILE": lock})
    try:
        ident = paired(h, out)
        open(lock, "w").write("1"); time.sleep(1.5)
        if ident:
            text, code = client(h, "locked", 8, "--tls", f"--send-file={one}@3", "--expect-files=answer:locked", identity=ident)
            verdict(code == 0, "a locked Mac: the offer refused locked")
            verdict(*locked_lists(text))
            verdict(h.kept() == [], "nothing written")
    finally:
        h.stop()


def case_lock(out):
    print("== lock: the Mac locks mid-transfer, the device leaves mid-file", flush=True)
    src = os.path.join(out, "lock.src"); os.makedirs(src, exist_ok=True)
    big = make(src, "big.bin", 20_000_000, 3)
    lock = os.path.join(out, "midlock.lockfile"); open(lock, "w").write("0")
    h = Host(out, "midlock", {"SILL_TEST_LOCKED_FILE": lock})
    try:
        ident = paired(h, out)
        if ident:
            # One part at a time (a 1-byte window), so the transfer is still on its way when the Mac locks.
            th = threading.Thread(target=lambda: client(h, "midlock", 12, "--tls", "--files-pace=2000000", f"--send-file={big}@1",
                                                        "--expect-files=cancel:locked", identity=ident))
            th.start(); time.sleep(4); open(lock, "w").write("1"); th.join()
            text = open(os.path.join(out, "midlock-midlock.client.log")).read()
            verdict("EXPECT-FILES ok" in text, f"locked mid-transfer: the device told cancel locked ({re.findall(r'files at .*cancel.*', text)[:1]})")
            verdict(h.kept() == [] and h.partials() == [], f"nothing kept, no partial: {h.kept()} {h.partials()}")
            open(lock, "w").write("0"); time.sleep(3.5)
            text, code = client(h, "after", 4, "--tls", identity=ident)
            verdict(h.kept() == [] and h.partials() == [], "after the unlock nothing acts")
    finally:
        h.stop()
    h = Host(out, "leave")
    try:
        ident = paired(h, out)
        if ident:
            client(h, "leave", 4, "--tls", "--files-pace=2000000", f"--send-file={big}@1", identity=ident)
            time.sleep(1.5)
            verdict(h.partials() == [] and h.kept() == [], f"the device left mid-file: its partial deleted ({h.partials()})")
            stopped = h.all(r"^Files: the transfer from .* stopped \(the connection ended\)")
            verdict(bool(stopped), f"one line: {stopped[:1]}")
    finally:
        h.stop()


def case_give(out):
    print("== give: the Mac's files to a device (H6): offered on cue, a pick, declined, the device's cancel, a lock", flush=True)
    src = os.path.join(out, "give.src"); os.makedirs(src, exist_ok=True)
    files = [make(src, n, s, i) for i, (n, s) in enumerate([("report.pdf", 3_000_000), ("empty.txt", 0), ("one.bin", 1),
                                                          ("chunk-plus-one.bin", 65537)])]
    big = make(src, "big.bin", 20_000_000, 9)
    def got(label):
        d = os.path.join(out, f"{label}.got"); os.makedirs(d, exist_ok=True); return d
    def kept_in(d): return sorted(n for n in os.listdir(d) if n != ".incoming")
    def half_written(d): return sorted(os.listdir(os.path.join(d, ".incoming"))) if os.path.isdir(os.path.join(d, ".incoming")) else []
    # Offered on cue, as Sill's menu would, to each device whose hello takes files; one that takes none, nothing.
    h = Host(out, "give", {"SILL_TEST_FILES_OFFER": "2 " + ":".join(files)})
    try:
        ident = paired(h, out)
        if ident:
            d = got("give")
            text, code = client(h, "give", 10, "--tls", f"--accept-files={d}", "--expect-received=4", identity=ident)
            verdict(code == 0 and "EXPECT-RECEIVED ok" in text, f"offered on cue: 4 files kept whole ({re.findall(r'files received: .*', text)[:1]})")
            verdict(kept_in(d) == sorted(os.path.basename(p) for p in files)
                    and all(sha(os.path.join(d, os.path.basename(p))) == sha(p) for p in files), f"each byte for byte the Mac's: {kept_in(d)}")
            verdict(half_written(d) == [], "nothing left half written on the device")
            verdict(re.search(r"windowList: .* files=1", text) is not None, "a host that answers no pick says files=1")
            sent = h.all(r"^Files: sent 4 files")
            verdict(bool(sent), f"the host's sent line, counts and sizes: {sent[:1]}")
            leaked = [l for _, l in h.lines if any(os.path.basename(p) in l for p in files)]
            verdict(not leaked, f"no file name in the host's output: {leaked[:2]}")
            text, code = client(h, "nofiles", 5, "--tls", identity=ident)
            verdict('"op": "offer"' not in text, "a device whose hello takes no files: nothing offered")
            text, code = client(h, "decline", 6, "--tls", "--decline-files", identity=ident)
            verdict(bool(h.all(r"^Files: .* cancelled \(declined\)")), f"declined: the host's line {h.all(r'cancelled')[-1:]}")
    finally:
        h.stop()
    # A device's pick (Get Files): a test host answers it with its TEST ONLY choice, no Open panel; the list says 2.
    h = Host(out, "pick", {"SILL_TEST_FILES_PICK": ":".join(files[:2])})
    try:
        ident = paired(h, out)
        if ident:
            d = got("pick")
            text, code = client(h, "pick", 8, "--tls", "--pick-files@2", f"--accept-files={d}", "--expect-received=2", identity=ident)
            verdict(code == 0 and "(asked for)" in text, f"the pick answered with its files, taken as asked for: {kept_in(d)}")
            verdict(re.search(r"windowList: .* files=2", text) is not None, "a host that answers picks says files=2")
            verdict(bool(h.all(r"^Files: .* asked for files from this Mac\.")), "the pick in the host's log")
            text, code = client(h, "pick-again", 6, "--tls", "--pick-files@1", "--pick-files@2", f"--accept-files={d}", identity=ident)
            verdict('"reason": "rate"' in text, "a second pick within 5 s of the first's end: rate")
    finally:
        h.stop()
    h = Host(out, "pick-unpaired", {"SILL_TEST_FILES_PICK": files[2], "SILL_TEST_REQUIRE_PAIRING": "0"})
    try:
        text, code = client(h, "u", 6, "--tls", "--pin=none", "--pick-files@2", "--expect-files=cancel:notPaired",
                            identity=os.path.join(out, "pick-unpaired.idU"))
        verdict(code == 0, "an unpaired session's pick: notPaired")
    finally:
        h.stop()
    h = Host(out, "pick-off", {"SILL_TEST_FILES_PICK": files[2]}, args=["--no-files"])
    try:
        ident = paired(h, out)
        if ident:
            text, code = client(h, "off", 6, "--tls", "--pick-files@2", "--expect-files=cancel:off", identity=ident)
            verdict(code == 0 and re.search(r"windowList: .* files=0", text) is not None, "--no-files: the list says files=0, a pick refused off")
    finally:
        h.stop()
    # Mid-file: the device's Cancel, then the Mac locking; the device acknowledges 2 MB a second, so each lasts.
    lock = os.path.join(out, "givestop.lockfile"); open(lock, "w").write("0")
    h = Host(out, "givestop", {"SILL_TEST_FILES_OFFER": "1 " + big, "SILL_TEST_LOCKED_FILE": lock})
    try:
        ident = paired(h, out)
        if ident:
            d = got("givestop")
            text, code = client(h, "cancel", 7, "--tls", f"--accept-files={d}", "--receive-pace=2000000", "--cancel-receive@3", identity=ident)
            verdict("sent receive cancel" in text and kept_in(d) == [] and half_written(d) == [], f"the device's cancel mid-file: nothing kept or left ({kept_in(d)})")
            verdict(bool(h.all(r"^Files: .* cancelled \(its person stopped it\)")), "the host's line for it")
            th = threading.Thread(target=lambda: client(h, "locked", 10, "--tls", f"--accept-files={d}", "--receive-pace=2000000",
                                                        "--expect-files=cancel:locked", identity=ident))
            th.start(); time.sleep(4); open(lock, "w").write("1"); th.join()
            text = open(os.path.join(out, "givestop-locked.client.log")).read()
            verdict("EXPECT-FILES ok" in text and kept_in(d) == [], f"the Mac locked mid-file: the device told locked ({re.findall(r'files at .*cancel.*', text)[:1]})")
            stopped = h.all(r"^Files: the transfer to .* stopped \(locked\)")
            verdict(bool(stopped), f"the host's line: {stopped[:1]}")
    finally:
        h.stop()


def case_hostile(out):
    print("== hostile: parts with no offer, another total, a gap, an oversized part, an op not known, names, a flood", flush=True)
    h = Host(out, "hostile")
    try:
        ident = paired(h, out)
        if not ident: return
        text, code = client(h, "nooffer", 5, "--tls", "--raw34=7,10,0,00112233@1", identity=ident)
        verdict(h.kept() == [] and h.partials() == [], "parts with no offer: dropped, nothing written")
        offer = lambda t, files: json.dumps({"op": "offer", "transfer": t, "files": files})
        text, code = client(h, "total", 6, "--tls", f"--raw49={offer(11, [{'id': 1, 'name': 'x', 'size': 10}])}@1",
                            "--raw34=1,99,0,0011@2", "--expect-files=cancel:damaged", identity=ident)
        verdict(code == 0 and h.partials() == [], "a part of another total: cancelled damaged, no partial")
        text, code = client(h, "gap", 6, "--tls", f"--raw49={offer(12, [{'id': 1, 'name': 'x', 'size': 10}])}@1",
                            "--raw34=1,10,2,0011@2", "--expect-files=cancel:damaged", identity=ident)
        verdict(code == 0 and h.partials() == [], "a gap: cancelled damaged")
        text, code = client(h, "big", 6, "--tls", f"--raw49={offer(13, [{'id': 1, 'name': 'x', 'size': 600000}])}@1",
                            "--raw34=1,600000,0,r524289@2", "--expect-files=cancel:damaged", identity=ident)
        verdict(code == 0 and h.partials() == [], "a part over 512 KiB: cancelled damaged")
        text, code = client(h, "unknownop", 4, "--tls", '--raw49={"op":"resume","transfer":3}@1', identity=ident)
        verdict(h.p.poll() is None and not [l for l in text.splitlines() if "files at" in l], "an op not known: ignored, the host serving")
        # Hostile names through a whole transfer: the kept names are FileNames.clean's.
        names = ["../escape.txt", "a\nb.txt", ".hidden", "cv‮fdp.exe", "x" * 300 + ".pdf"]
        files = [{"id": i + 1, "name": n, "size": 3} for i, n in enumerate(names)]
        digest = "ungWv48Bz-pBQUDeXa4iI7ADYaOWF3qctBD_YfIAFa0"   # SHA-256 of "abc", base64url
        steps = [f"--raw49={json.dumps({'op': 'offer', 'transfer': 21, 'files': files})}@1"]
        for i in range(len(names)):
            steps += [f"--raw34={i + 1},3,0,616263@{2 + i * 0.3:.1f}",
                      f"--raw49={json.dumps({'op': 'end', 'transfer': 21, 'file': i + 1, 'sha256': digest})}@{2.1 + i * 0.3:.1f}"]
        text, code = client(h, "names", 8, "--tls", *steps, "--expect-files=done", identity=ident)
        kept = h.kept()
        want = ["File..-escape.txt", "ab.txt", "File.hidden", "cvfdp.exe", "x" * 196 + ".pdf"]
        verdict(code == 0 and sorted(want) == sorted(kept), f"hostile names kept cleaned, all inside the folder: {[k[:30] for k in kept]}")
        verdict(not os.path.exists(os.path.join(out, "escape.txt")) and not os.path.exists(os.path.join(os.path.dirname(h.files), "escape.txt")),
                "nothing outside the folder")
        # Ten offers at once: the rate takes two (the first accepted, the second busy), the rest refused rate.
        flood = [f"--raw49={offer(100 + i, [{'id': 1, 'name': 'f', 'size': 5}])}@1" for i in range(10)]
        text, code = client(h, "flood", 5, "--tls", *flood, identity=ident)
        answers = re.findall(r'"op": "answer".*?"reason": "(\w+)"', text) + re.findall(r'"accept": true', text)
        rates = len(re.findall(r'"reason": "rate"', text))
        verdict(rates == 8, f"ten offers at once: eight refused rate ({rates}), the first taken")
        refused = h.all(r"^Files: refused")
        verdict(1 <= len(refused) <= 2, f"the refusals in one or two lines a minute: {refused[:2]}")
        verdict(h.p.poll() is None, "the host still serving")
        fds = subprocess.run(["lsof", "-p", str(h.p.pid)], capture_output=True, text=True).stdout
        part_fds = [l for l in fds.splitlines() if ".part" in l]
        verdict(len(part_fds) <= 1, f"at most one open staging file: {len(part_fds)}")
    finally:
        h.stop()


def case_h2(out, base):
    """H2: the CLI's stdout is what main's was, idle and with a client that picks the Desktop and sends no file.
    BASE is main's .build/release/SillHost (built from `git archive origin/main`)."""
    print("== h2: the CLI's stdout, this branch's against main's", flush=True)
    if not base or not os.path.exists(base): verdict(False, f"h2 needs main's SillHost: --base=PATH (got {base!r})"); return
    def run(binary, label):
        env = dict(os.environ); env.update({k: v for k, v in BASE_ENV.items() if k != "SILL_TEST_FILES_LOG"})
        p = subprocess.Popen(["nice", "-n", "10", binary, "--synthetic"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=env,
                             start_new_session=True, text=True)
        port = None
        for _ in range(100):
            time.sleep(0.1)
            r = subprocess.run(["lsof", "-nP", "-a", "-p", str(p.pid), "-iTCP", "-sTCP:LISTEN"], capture_output=True, text=True)
            ports = re.findall(r"127\.0\.0\.1:(\d+) \(LISTEN\)", r.stdout)
            if ports: port = ports[0]; break
        time.sleep(20)
        if port: subprocess.run([sys.executable, "-I", CLIENT, port, "15", "desktop"], capture_output=True, text=True, timeout=60,
                                env={**os.environ, **BASE_ENV})
        time.sleep(15)
        os.killpg(p.pid, signal.SIGTERM)
        text = p.communicate(timeout=10)[0]
        open(os.path.join(out, f"h2-{label}.log"), "w").write(text)
        return text
    h2_compare(run(HOST, "branch"), run(base, "main"))


def h2_lines(text):
    """A CLI's stdout as H2 compares it: every line but the per-second counters masked (numbers N, paths PATH), as a set;
    and the per-second counters ([1s] lines) by the names they use, since which counters a second shows is timing's."""
    mask = lambda l: re.sub(r"\d+(\.\d+)?", "N", re.sub(r"(/[^\s]+)+", "PATH", l))
    lines, counters = set(), set()
    for l in text.splitlines():
        if not l.strip(): continue
        if l.startswith("[1s] "): counters |= set(re.findall(r"([A-Za-z][\w.]*) \d", l[5:].split(" · ")[0]))
        else: lines.add(mask(l))
    return lines, counters


def h2_compare(mine_text, theirs_text):
    (mine, mine_c), (theirs, theirs_c) = h2_lines(mine_text), h2_lines(theirs_text)
    extra, missing = sorted(mine - theirs), sorted(theirs - mine)
    verdict(not extra and not missing, f"the same lines, masked: {len(extra)} new ({extra[:2]}), {len(missing)} gone ({missing[:2]})")
    verdict(mine_c <= theirs_c, f"no counter main never prints: {sorted(mine_c - theirs_c)} (main's alone: {sorted(theirs_c - mine_c)})")


def main():
    if len(sys.argv) < 2: raise SystemExit(__doc__)
    out = os.path.abspath(sys.argv[1]); os.makedirs(out, exist_ok=True)
    which = sys.argv[2] if len(sys.argv) > 2 else "all"
    base = next((a.partition("=")[2] for a in sys.argv[3:] if a.startswith("--base=")), None)
    logs = next((a.partition("=")[2] for a in sys.argv[3:] if a.startswith("--logs=")), None)
    if which == "h2" and logs:
        # H2 judged again on the logs an earlier run saved (h2-branch.log, h2-main.log), no host started.
        h2_compare(open(os.path.join(logs, "h2-branch.log")).read(), open(os.path.join(logs, "h2-main.log")).read())
        failed = [w for ok, w in verdicts if not ok]
        print(f"files-check: {len(verdicts) - len(failed)} of {len(verdicts)} rules hold")
        sys.exit(1 if failed else 0)
    if not os.path.exists(HOST): raise SystemExit(f"no {HOST}: swift build -c release first")
    for name, case in [("send", case_send), ("refuse", case_refuse), ("hostile", case_hostile), ("lock", case_lock), ("give", case_give)]:
        if which in (name, "all"): case(out)
    if which == "h2": case_h2(out, base)
    failed = [w for ok, w in verdicts if not ok]
    print(f"files-check: {len(verdicts) - len(failed)} of {len(verdicts)} rules hold")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
