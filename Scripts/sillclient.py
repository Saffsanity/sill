#!/usr/bin/env python3
r"""Minimal Sill wire-format client for testing a host without a device.

usage: sillclient.py PORT [seconds] [desktop|none|window:ID] [flags...]
  --junk             also send two unknown message kinds (the host must skip them)
  --fps=N            send a viewport asking for N fps right after the select
  --fps-after=N@T    send a second viewport asking for N fps after T seconds
  --set=K=V[,K=V]@T  send a settings change (kind 17) T seconds in, with integer tokens 1, 2, 3...
                     in send order. Keys: maxFPS, bitrate, captureScale, prioritizeSpeed,
                     virtualDisplay, directWireless; booleans accept 1/0/true/false/on/off
  --raw17=JSON@T     send this literal kind 17 payload T seconds in (split on the last @)
  --pick=SRC@T       a timed selectSource: none, desktop or window:ID
  --stats            send ClientStats (kind 12) once a second as device "sillclient", so the host
                     logs a name for this client
  --expect=K=V[,...] at exit, compare the last kind 16's settings (and its top-level persistent
                     and virtualDisplayAvailable): prints EXPECT ok or EXPECT FAIL, exits 1 on failure
  --host=H           connect to H instead of 127.0.0.1 (an IPv4 or IPv6 address, or a name)
  --device=NAME      the name ClientStats reports (implies --stats); \n, \t, \xHH and \uXXXX escapes
                     are decoded, so control and bidi characters can be sent
  --big-payload=N    right after the select, send a header of an unknown kind announcing N payload
                     bytes (and none of them); the host should close the connection
  --flood=N          before the session, open N connections to the same door and reset each one
                     (SO_LINGER 0) before sending a byte
  --stop-ping@T      from T seconds in, send no more pings and no stats: a silent client
  --stop-read@T      from T seconds in, read nothing more (pings go on): a client that stopped draining
  --pairing-wanted@T send kind 21 ("show your pairing code") T seconds in
  --hello=VER[,PROTO] send a hello (kind 23) first, before the select, as a device from 2026-09-25 on does:
                     {"appVersion": VER, "protocol": PROTO, "device": the --device name, else "sillclient"};
                     --hello=none sends {} (a hello with nothing in it). Without it no hello is sent: an
                     older device, which a host with a device floor above 0 refuses
  --hello-delay=S    with --hello: send it S seconds after the connection is up (TLS included), and
                     nothing before it: a device whose hello a host's device gate waits for while the
                     Mac changes something (its gate gives up after 2 s)
The remote door (TLS 1.3, both keys pinned; PORT is the remote door's):
  --tls              a session (ALPN sill/1) with this client's identity, pinning the Mac's key saved by
                     an earlier pairing in --identity (or given with --pin)
  --identity=DIR     this client's P-256 key and certificate, made on first use with /usr/bin/openssl
                     (DIR/key.pem, DIR/cert.pem), and the paired Mac (DIR/mac.json); required with --tls
  --pair-url=URL     pair first with a sill://pair link (the QR path: the Mac is pinned to its k before
                     a byte is sent), save the Mac, then run the session
  --pair-code=CODE   pair first with the typed code (no pin: the proofs bind both keys), then the session
  --pin=FP|none      pin this base64url fingerprint instead of the saved one; none accepts any key
  --expect-tls-fail  the session must be refused (a TLS error, or closed before any message): exits 0
                     when it is, 1 when a session is served
Pairing at home (a TLS home door: SillHost --pairing, or the bare app; PORT is the home door's):
  --pair-ask[=cable] ask to pair first (kind 19 "ask", with "cable": true given =cable), taking any Mac
                     key (or --pin's), and print kind 20. An ok with method "cable" is accepted only for
                     =cable: its macID must be the Mac's key's and its recognition key 32 bytes; the Mac
                     is saved, then the session runs
  --then-code=FILE   after "shown", read the code from FILE (waiting up to 5 s for 12 digits) and pair with
                     it over the same door, pinned to the key the ask saw; with --pair-url instead, pair by
                     the link after "shown"
  --pair-hold=S      open a pairing connection (ALPN sill-pair/1) that sends nothing for S seconds, then
                     print whether the host closed it first (HOLD closed at T s, or HOLD open); nothing else
  --pair-v=N         the kind 19's v (1 unless given): a host answers any other closed, with no try
                     counted (the compatibility floor: a later method or proof comes with a later v)
  --expect-pair=R    the pairing's last kind 20 must be R: ok (a proof checked), cable, shown, openOnMac,
                     locked, closed, code, busy, expired or stopped; prints EXPECT-PAIR ok or EXPECT-PAIR
                     FAIL (exit 1). A match that is not a pairing ends the run with exit 0
A pin mismatch exits 3 before sending a byte. Kinds 18 (verified with `openssl dgst -sha256 -verify`
and against the Mac ID), 20 and 22 (its reason, then message, minimumVersion and reconnect when sent)
are printed one line each; a session prints the order of the
kinds it received first (the catalog). Pairing prints PAIR ok or PAIR FAIL with the reason.
At exit a LINK line gives the pong round trip (p50/p95/max over every pong), the keyframes' arrival
times, the frames received in each 5 s window, and the frames' age (host timestamp to arrival; the
same clock when both run on one Mac).
Once a second it prints the frames, their payload in kB (the encoder's output), ticks, cursor
shapes and the last ping's round trip. Every kind 16 (host settings) is printed on one line with
its arrival time; dw= is Direct Wireless
(1, 0, or - when the host did not report it: an older host). Flags may come in any
order after the positional arguments. Everything is checked before connecting: an unknown flag, a
--set or --expect key that is not one of theirs, or a value that does not parse stops the script
with status 2 (--raw17 goes out as written). Find PORT with: lsof -nP -iTCP -sTCP:LISTEN -a -p <pid>.
The --synthetic hosts do not advertise over Bonjour, so this is the only way to reach them."""
import json, re, socket, struct, sys, time

KIND = {0:"ps",1:"frame",2:"list",3:"thumb",4:"icon",5:"apps",11:"pong",13:"tick",14:"cursor",16:"settings",18:"macinfo",20:"pairresult",22:"goodbye"}
BOOL = {"1": True, "0": False, "true": True, "false": False, "on": True, "off": False, "yes": True, "no": False}
BOOL_KEYS = {"prioritizeSpeed", "virtualDisplay", "directWireless", "persistent", "virtualDisplayAvailable"}
# What --set may send: HostSettingsChange's six fields. The host drops any other key without a
# word, so a misspelt one would only show up as an unchanged answer.
SET_KEYS = {"maxFPS", "bitrate", "captureScale", "prioritizeSpeed", "virtualDisplay", "directWireless"}
EXPECT_KEYS = SET_KEYS | {"persistent", "virtualDisplayAvailable"}
TIMED = ("set", "raw17", "pick", "fps-after", "stop-ping", "stop-read", "pairing-wanted")
VALUED = ("host", "device", "big-payload", "flood", "identity", "pair-url", "pair-code", "pin", "hello", "hello-delay", "then-code",
          "pair-hold", "expect-pair", "pair-v")
PAIR_RESULTS = ("ok", "cable", "shown", "openOnMac", "locked", "closed", "code", "busy", "expired", "stopped")

def msg(kind, payload=b"", key=False):
    return struct.pack(">BdBI", kind, time.time(), 1 if key else 0, len(payload)) + payload

def source(spec):
    if spec == "desktop": return {"desktop": {}}
    if spec == "none": return {"none": {}}
    if spec.startswith("window:") and spec[7:].isdigit(): return {"window": {"_0": int(spec[7:])}}
    raise ValueError(f"not a source: {spec!r} (desktop, none or window:ID)")

def number(v, what, kind=int):
    try: return kind(v)
    except ValueError: raise ValueError(f"{what}: not a number: {v!r}") from None

def value(k, v):
    if k in BOOL_KEYS:
        if v.lower() not in BOOL: raise ValueError(f"{k}: not a boolean: {v!r} (1/0/true/false/on/off)")
        return BOOL[v.lower()]
    if k == "captureScale":
        f = number(v, k, float); return int(f) if f.is_integer() else f   # an integer, as a device-less script would send it
    return number(v, k)

def pairs(body, keys, flag):
    out = {}
    for kv in body.split(","):
        k, eq, v = kv.partition("=")
        if not eq: raise ValueError(f"{flag}: expected K=V, got {kv!r}")
        if k not in keys: raise ValueError(f"{flag}: unknown key {k!r} (keys: {', '.join(sorted(keys))})")
        out[k] = value(k, v)
    return out

def unescape(text):
    """\\n, \\t, \\r, \\\\, \\xHH and \\uXXXX in a --device value, so a test can send control and bidi characters."""
    def repl(m):
        e = m.group(0)
        if e[1] in "xu": return chr(int(e[2:], 16))
        return {"n": "\n", "t": "\t", "r": "\r", "\\": "\\"}[e[1]]
    return re.sub(r"\\(x[0-9a-fA-F]{2}|u[0-9a-fA-F]{4}|[ntr\\])", repl, text)

# MARK: the remote door's crypto (standard library, and /usr/bin/openssl for keys and signatures)
import base64, hashlib, hmac, os, ssl, subprocess, tempfile, urllib.parse
def b64u(b): return base64.urlsafe_b64encode(b).decode().rstrip("=")
def b64u_decode(t):
    if not re.fullmatch(r"[A-Za-z0-9_-]*", t or ""): raise ValueError(f"not base64url: {t!r}")
    return base64.urlsafe_b64decode(t + "=" * (-len(t) % 4))
CROCK = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
def macid(fp):
    n = int.from_bytes(fp[:10], "big")
    return "".join(CROCK[(n >> (75 - 5 * i)) & 31] for i in range(16))
DAMM = [[0,3,1,7,5,9,8,6,4,2],[7,0,9,2,1,5,4,8,6,3],[4,2,0,6,8,7,1,3,5,9],[1,7,5,0,9,8,3,4,2,6],[6,1,2,3,0,4,5,9,7,8],
        [3,6,7,4,2,0,9,5,8,1],[5,8,6,9,7,2,0,1,3,4],[8,9,4,5,3,6,2,0,1,7],[9,4,3,8,6,1,7,2,0,5],[2,5,8,1,4,3,6,7,9,0]]
def damm(digits):
    i = 0
    for d in digits: i = DAMM[i][int(d)]
    return i
def tlv(b, i):
    tag = b[i]; n = b[i + 1]; i += 2
    if n & 0x80:
        k = n & 0x7F; n = int.from_bytes(b[i:i + k], "big"); i += k
    return tag, i, i + n
def spki(der):
    """A certificate's SubjectPublicKeyInfo TLV: the 6th field of TBSCertificate after the optional [0] version."""
    _, cs, _ = tlv(der, 0); _, ts, te = tlv(der, cs)
    fields, i = [], ts
    while i < te:
        tag, _, end = tlv(der, i); fields.append((tag, i, end)); i = end
    if fields[0][0] == 0xA0: fields = fields[1:]
    _, start, end = fields[5]
    return der[start:end]
SPKI_PREFIX = bytes.fromhex("3059301306072a8648ce3d020106082a8648ce3d030107034200")
def parse_link(url):
    u = urllib.parse.urlsplit(url)
    if u.scheme.lower() != "sill" or u.netloc.lower() != "pair": raise ValueError("--pair-url: not a sill://pair link")
    q = urllib.parse.parse_qs(u.query, keep_blank_values=True)
    one = lambda k: (q.get(k) or [None])[0] if len(q.get(k, [])) == 1 else None
    if one("v") != "1": raise ValueError("--pair-url: v is not 1")
    k = b64u_decode(one("k") or ""); sec = b64u_decode(one("s") or "")
    if len(k) != 32 or len(sec) != 16: raise ValueError("--pair-url: k or s malformed")
    if one("m") != macid(k): raise ValueError("--pair-url: m is not the Mac ID of k")
    p = int(one("p") or "0")
    if not 1 <= p <= 65535: raise ValueError("--pair-url: p malformed")
    return {"fp": k, "secret": sec, "port": p, "name": one("n") or "Mac", "addresses": q.get("a", []), "macID": one("m")}
def ensure_identity(d):
    os.makedirs(d, mode=0o700, exist_ok=True)
    key, cert = os.path.join(d, "key.pem"), os.path.join(d, "cert.pem")
    if not os.path.exists(cert):
        subprocess.run(["/usr/bin/openssl", "ecparam", "-name", "prime256v1", "-genkey", "-noout", "-param_enc", "named_curve", "-out", key],
                       check=True, capture_output=True)
        os.chmod(key, 0o600)
        subprocess.run(["/usr/bin/openssl", "req", "-x509", "-new", "-key", key, "-subj", "/CN=sillclient", "-days", "3650", "-out", cert],
                       check=True, capture_output=True)
    der = base64.b64decode("".join(l for l in open(cert).read().splitlines() if "-----" not in l))
    return key, cert, hashlib.sha256(spki(der)).digest()
def tls_connect(alpn, pin):
    """TLS 1.3 to the remote door with this client's identity and one ALPN. `pin` (32 bytes) must equal
    the Mac's SPKI hash or the script exits 3 before sending a byte; None accepts any key (the typed
    pairing path, and --pin=none). Returns (socket, the Mac's fingerprint)."""
    key, cert, _ = ensure_identity(identity_dir)
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ctx.minimum_version = ssl.TLSVersion.TLSv1_3; ctx.maximum_version = ssl.TLSVersion.TLSv1_3
    ctx.check_hostname = False; ctx.verify_mode = ssl.CERT_NONE        # trust is the pin below
    ctx.load_cert_chain(cert, key)
    ctx.set_alpn_protocols([alpn])
    raw = socket.create_connection((host, port), timeout=10)
    s = ctx.wrap_socket(raw, server_hostname="sill")
    fp = hashlib.sha256(spki(s.getpeercert(binary_form=True))).digest()
    if pin is not None and fp != pin:
        print(f"PIN MISMATCH: the Mac presented {b64u(fp)[:10]}…, expected {b64u(pin)[:10]}…; nothing sent"); s.close(); sys.exit(3)
    got = s.selected_alpn_protocol()
    if got != alpn:
        print(f"ALPN MISMATCH: {got!r}"); s.close(); sys.exit(4)
    print(f"  tls {s.version()} {s.cipher()[0]} alpn {got}, the Mac {b64u(fp)[:10]}…{' (pinned)' if pin else ''}")
    return s, fp
def read_message(s, timeout):
    s.settimeout(timeout); buf = b""
    while len(buf) < 14:
        c = s.recv(14 - len(buf))
        if not c: return None
        buf += c
    kind, ts, key, ln = struct.unpack(">BdBI", buf)
    payload = b""
    while len(payload) < ln:
        c = s.recv(ln - len(payload))
        if not c: return None
        payload += c
    return kind, payload
def verify_macinfo(payload, pin):
    """kind 18: the signature with openssl over the exact info bytes, the Mac ID against the key,
    and the key against the pin when there is one. Returns (verified, info dict)."""
    d = json.loads(payload)
    info = base64.b64decode(d["info"]); point = base64.b64decode(d["key"]); sig = base64.b64decode(d["sig"])
    spki_der = SPKI_PREFIX + point
    with tempfile.TemporaryDirectory() as t:
        open(os.path.join(t, "pub.pem"), "w").write("-----BEGIN PUBLIC KEY-----\n" + base64.encodebytes(spki_der).decode() + "-----END PUBLIC KEY-----\n")
        open(os.path.join(t, "info"), "wb").write(info); open(os.path.join(t, "sig"), "wb").write(sig)
        r = subprocess.run(["/usr/bin/openssl", "dgst", "-sha256", "-verify", os.path.join(t, "pub.pem"), "-signature", os.path.join(t, "sig"),
                            os.path.join(t, "info")], capture_output=True, text=True)
    fp = hashlib.sha256(spki_der).digest(); i = json.loads(info)
    ok = r.returncode == 0 and "Verified OK" in r.stdout and i.get("macID") == macid(fp) and (pin is None or fp == pin)
    return ok, i
pair_results = []      # every kind 20 of the pairing phase, in order (--expect-pair checks the last)
def pair(url=None, code=None, pin=None):
    """One pairing connection (ALPN sill-pair/1): kind 19 out, kind 20 back. Saves the Mac on ok.
    `url` pairs by the QR link (pinned to its k), `code` by the typed code (pinned to `pin` when the
    ask saw the Mac's key, else to nothing: the proofs bind both keys)."""
    url = url if url is not None else pair_url
    code = code if code is not None else pair_code
    key, cert, fp_dev = ensure_identity(identity_dir)
    if url:
        lk = parse_link(url) if url != pair_url else link
        s, fp_mac = tls_connect("sill-pair/1", lk["fp"])
        k, method = lk["secret"], "qr"
    else:
        s, fp_mac = tls_connect("sill-pair/1", pin)
        t0 = time.time()
        k = hashlib.pbkdf2_hmac("sha256", code.encode(), b"sill-pair-v1" + fp_mac, 600_000, 32); method = "code"
        print(f"  code key derived in {1000 * (time.time() - t0):.0f} ms")
    proof = hmac.new(k, b"sill-pair-v1 device\x00" + fp_dev + fp_mac, hashlib.sha256).digest()
    req = {"v": pair_v, "method": method, "proof": b64u(proof), "name": device, "model": "sillclient"}
    s.sendall(msg(19, json.dumps(req).encode()))
    try:
        m = read_message(s, 15)
    except (OSError, ssl.SSLError) as e:
        print(f"PAIR FAIL: {e}"); return False
    s.close()
    if m is None or m[0] != 20: print(f"PAIR FAIL: no kind 20 ({m[0] if m else 'EOF'})"); return False
    r = json.loads(m[1]); print(f"  pairResult: {json.dumps(r, sort_keys=True)}")
    pair_results.append(r)
    if not r.get("ok"): print(f"PAIR FAIL: {r.get('reason')}"); return False
    want = hmac.new(k, b"sill-pair-v1 mac\x00" + fp_mac + fp_dev, hashlib.sha256).digest()
    if not hmac.compare_digest(b64u_decode(r.get("proof", "")), want): print("PAIR FAIL: proof_M does not check"); return False
    if r.get("macID") != macid(fp_mac): print("PAIR FAIL: macID is not the Mac's key"); return False
    with open(os.path.join(identity_dir, "mac.json"), "w") as f:
        json.dump({"fingerprint": b64u(fp_mac), "macID": r["macID"], "name": r.get("name"), "recognitionKey": r.get("recognitionKey")}, f)
    print(f"PAIR ok: {r.get('name')} ({r['macID']}), proof_M checked, pin saved")
    return True

def ask(cable, pin=None):
    """The home door's "pair me" (kind 19 "ask"): returns (kind 20 as a dict or None, the Mac's key).
    A proof-less ok is taken only as the answer to an ask that said cable: true, with the macID of
    the key this connection saw and a 32-byte recognition key; then the Mac is saved."""
    ensure_identity(identity_dir)
    s, fp_mac = tls_connect("sill-pair/1", pin)
    req = {"v": pair_v, "method": "ask", "proof": "", "name": device, "model": "sillclient"}
    if cable: req["cable"] = True
    s.sendall(msg(19, json.dumps(req).encode()))
    try:
        m = read_message(s, 15)
    except (OSError, ssl.SSLError) as e:
        print(f"ASK FAIL: {e}"); return None, fp_mac
    s.close()
    if m is None or m[0] != 20: print(f"ASK FAIL: no kind 20 ({m[0] if m else 'EOF'})"); return None, fp_mac
    r = json.loads(m[1]); print(f"  pairResult: {json.dumps(r, sort_keys=True)}")
    if not r.get("ok"):
        pair_results.append(r)
        print(f"ASK {r.get('reason')}"); return r, fp_mac
    # An ok this client refuses counts as "refused" for --expect-pair, never as a pairing.
    if not cable or r.get("method") != "cable" or r.get("proof"):
        pair_results.append({"ok": False, "reason": "refused"})
        print("ASK FAIL: an ok without a proof for an ask that did not claim the cable; nothing saved"); return None, fp_mac
    rk = b64u_decode(r.get("recognitionKey") or "")
    if r.get("macID") != macid(fp_mac) or len(rk) != 32:
        pair_results.append({"ok": False, "reason": "refused"})
        print("ASK FAIL: the cable's ok names another Mac key, or no recognition key; nothing saved"); return None, fp_mac
    pair_results.append(r)
    with open(os.path.join(identity_dir, "mac.json"), "w") as f:
        json.dump({"fingerprint": b64u(fp_mac), "macID": r["macID"], "name": r.get("name"), "recognitionKey": r.get("recognitionKey")}, f)
    print(f"PAIR ok: {r.get('name')} ({r['macID']}) over the cable, pin saved")
    return r, fp_mac

def read_code(path, wait=5.0):
    """--then-code: the 12 digits in `path`, waiting up to `wait` s for the file to hold them."""
    deadline = time.time() + wait
    while True:
        try:
            text = re.sub(r"[ -]", "", open(path).read().strip())
            if re.fullmatch(r"\d{12}", text) and damm(text) == 0: return text
        except OSError:
            pass
        if time.time() >= deadline: return None
        time.sleep(0.05)

def result_word(r):
    if r is None: return None
    if r.get("ok"): return "cable" if r.get("method") == "cable" else "ok"
    return r.get("reason")

def check_expect_pair():
    """--expect-pair: the pairing phase's last kind 20 against the wanted word; exits 1 on a miss."""
    got = result_word(pair_results[-1]) if pair_results else None
    if got == expect_pair: print("EXPECT-PAIR ok"); return True
    print(f"EXPECT-PAIR FAIL: want {expect_pair}, got {got}"); sys.exit(1)

args = sys.argv[1:]
pos = [a for a in args if not a.startswith("--")]
flags = [a for a in args if a.startswith("--")]
# Timed sends as (time, argument order, name, text, parsed), sorted: equal times go out in the
# order given. Every body is parsed here, before connecting, so a bad one fails at once instead of
# after the stream has started.
events = []
try:
    if not pos: raise ValueError("no PORT (usage: sillclient.py PORT [seconds] [desktop|none|window:ID] [flags...])")
    port = number(pos[0], "PORT"); dur = number(pos[1], "seconds", float) if len(pos) > 1 else 12
    sel = source(pos[2] if len(pos) > 2 else "desktop")
    for i, a in enumerate(flags):
        bare = re.fullmatch(r"--(stop-ping|stop-read|pairing-wanted)@([^=]*)", a)     # timed flags without a value
        name, _, body = (bare.group(1), "", "@" + bare.group(2)) if bare else a[2:].partition("=")
        if name in TIMED:
            text, at, t = body.rpartition("@")
            if not at: raise ValueError(f"--{name}: no @T (seconds in) in {a!r}")
            if name in ("stop-ping", "stop-read", "pairing-wanted") and text: raise ValueError(f"--{name}@T takes no value")
            parsed = (pairs(text, SET_KEYS, "--set") if name == "set" else source(text) if name == "pick"
                      else number(text, "--fps-after") if name == "fps-after" else text)
            events.append((number(t, f"--{name}'s @T", float), i, name, text, parsed))
        elif name in VALUED:
            if not body: raise ValueError(f"--{name} needs a value")
            if name in ("big-payload", "flood") and number(body, f"--{name}") < 1: raise ValueError(f"--{name} must be at least 1")
        elif a not in ("--junk", "--stats", "--tls", "--expect-tls-fail", "--pair-ask", "--pair-ask=cable") \
                and not a.startswith(("--fps=", "--expect=")):
            raise ValueError(f"unknown flag {a!r}")
    events.sort(key=lambda e: (e[0], e[1]))
    expect = next((pairs(a[9:], EXPECT_KEYS, "--expect") for a in flags if a.startswith("--expect=")), None)
    fps_now = next((number(a[6:], "--fps") for a in flags if a.startswith("--fps=")), None)
    def valued(name, default=None):
        return next((a.partition("=")[2] for a in flags if a.startswith(f"--{name}=")), default)
    host = valued("host", "127.0.0.1")
    device = unescape(valued("device")) if valued("device") is not None else None
    big_payload = number(valued("big-payload"), "--big-payload") if valued("big-payload") else None
    flood = number(valued("flood"), "--flood") if valued("flood") else 0
    pair_ask = "--pair-ask" in flags or "--pair-ask=cable" in flags
    ask_cable = "--pair-ask=cable" in flags
    then_code = valued("then-code"); expect_pair = valued("expect-pair")
    pair_v = number(valued("pair-v"), "--pair-v") if valued("pair-v") is not None else 1
    pair_hold = number(valued("pair-hold"), "--pair-hold", float) if valued("pair-hold") else None
    tls = ("--tls" in flags or valued("pair-url") is not None or valued("pair-code") is not None or pair_ask
           or pair_hold is not None)
    identity_dir = valued("identity")
    pair_url = valued("pair-url"); pair_code = valued("pair-code"); pin_arg = valued("pin")
    expect_tls_fail = "--expect-tls-fail" in flags
    if tls and not identity_dir: raise ValueError("--tls, --pair-url, --pair-code, --pair-ask and --pair-hold need --identity=DIR")
    if pair_url and pair_code: raise ValueError("--pair-url or --pair-code, not both")
    if then_code and not pair_ask: raise ValueError("--then-code needs --pair-ask")
    if then_code and (pair_url or pair_code): raise ValueError("--then-code, --pair-url or --pair-code after an ask, not two")
    if pair_ask and pair_code: raise ValueError("--pair-ask with --then-code=FILE (its code is read after the ask), not --pair-code")
    if expect_pair is not None and expect_pair not in PAIR_RESULTS: raise ValueError(f"--expect-pair: one of {', '.join(PAIR_RESULTS)}")
    if expect_pair is not None and not (pair_ask or pair_url or pair_code): raise ValueError("--expect-pair needs --pair-ask, --pair-url or --pair-code")
    if pair_hold is not None and (pair_hold <= 0 or pair_ask or pair_url or pair_code): raise ValueError("--pair-hold=S (S > 0) runs alone")
    if pair_url: link = parse_link(pair_url)
    if pair_code:
        pair_code = re.sub(r"[ -]", "", pair_code)
        if not re.fullmatch(r"\d{12}", pair_code): raise ValueError("--pair-code: 12 digits")
        if damm(pair_code) != 0: raise ValueError("--pair-code: the check digit does not match (a typo)")
    if pin_arg and pin_arg != "none" and len(b64u_decode(pin_arg)) != 32: raise ValueError("--pin: a base64url SHA-256 or none")
    hello_arg = valued("hello")
    if hello_arg is not None and hello_arg != "none":
        hv, _, hp = hello_arg.partition(",")
        if not hv: raise ValueError("--hello: VERSION[,PROTOCOL] or none")
        if hp: number(hp, "--hello's protocol")
    hello_delay = number(valued("hello-delay"), "--hello-delay", float) if valued("hello-delay") else 0
    if hello_delay and hello_arg is None: raise ValueError("--hello-delay needs --hello")
    if hello_delay < 0: raise ValueError("--hello-delay must be 0 or more")
except ValueError as e:
    print(f"sillclient.py: {e}", file=sys.stderr); sys.exit(2)
stats = "--stats" in flags or device is not None
device = device if device is not None else "sillclient"
# The hello (kind 23), the first message of the session when asked for: a device from 2026-09-25 on.
hello = None
if hello_arg == "none":
    hello = {}
elif hello_arg is not None:
    hv, _, hp = hello_arg.partition(",")
    hello = {"appVersion": hv, **({"protocol": int(hp)} if hp else {}), "device": device}

if flood:
    # Connections that are reset before a byte is sent: the door must not keep them (no descriptor
    # growth) and must not log them as clients.
    for _ in range(flood):
        f = socket.create_connection((host, port), timeout=5)
        f.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack("ii", 1, 0))
        f.close()
    print(f"  flood: {flood} connections opened and reset before sending")
mac_pin = None
if pair_hold is not None:
    # A pairing connection still pending: TLS up (ALPN sill-pair/1), then silence. The host's
    # admission deadline (10 s) or a Direct Wireless change may close it first.
    ensure_identity(identity_dir)
    hs, _ = tls_connect("sill-pair/1", b64u_decode(pin_arg) if pin_arg and pin_arg != "none" else None)
    t_hold = time.time(); closed_at = None
    hs.settimeout(0.1)
    while time.time() - t_hold < pair_hold:
        try:
            c = hs.recv(65536)
            if not c: closed_at = time.time() - t_hold; break
        except socket.timeout: pass
        except (OSError, ssl.SSLError): closed_at = time.time() - t_hold; break
    hs.close()
    print(f"HOLD closed at {closed_at:.2f} s" if closed_at is not None else f"HOLD open for {pair_hold:.0f} s")
    sys.exit(0)
if tls:
    ask_pin = b64u_decode(pin_arg) if pin_arg and pin_arg != "none" else None
    if pair_ask:
        r, asked_fp = ask(ask_cable, ask_pin)
        word = result_word(r)
        if word == "shown" and then_code:
            code_text = read_code(then_code)
            if code_text is None: print(f"PAIR FAIL: no code in {then_code}"); sys.exit(1)
            if not pair(code=code_text, pin=asked_fp) and expect_pair is None: sys.exit(1)
        elif word == "shown" and pair_url:
            if not pair() and expect_pair is None: sys.exit(1)
        elif word != "cable" and expect_pair is None:
            sys.exit(1)
    elif pair_url or pair_code:
        if not pair() and expect_pair is None: sys.exit(1)
    if expect_pair is not None:
        check_expect_pair()
        if result_word(pair_results[-1] if pair_results else None) not in ("ok", "cable"): sys.exit(0)
    saved = os.path.join(identity_dir, "mac.json")
    if pin_arg == "none": mac_pin = None
    elif pin_arg: mac_pin = b64u_decode(pin_arg)
    elif os.path.exists(saved): mac_pin = b64u_decode(json.load(open(saved))["fingerprint"])
    elif pair_url: mac_pin = link["fp"]
    else: print("sillclient.py: no saved Mac in --identity; pair first or give --pin", file=sys.stderr); sys.exit(2)
    if dur <= 0: sys.exit(0)
    try:
        s, _ = tls_connect("sill/1", mac_pin)
    except (OSError, ssl.SSLError) as e:
        print(f"TLS refused: {e}"); sys.exit(0 if expect_tls_fail else 1)
else:
    s = socket.create_connection((host, port), timeout=5)
s.settimeout(0.25)
try:
    if hello is not None:
        if hello_delay:
            time.sleep(hello_delay)
        s.sendall(msg(23, json.dumps(hello).encode())); print(f"  sent hello {json.dumps(hello)}" + (f" after {hello_delay:g} s" if hello_delay else ""))
    s.sendall(msg(6, json.dumps(sel).encode()))
except (OSError, ssl.SSLError) as e:
    print(f"TLS refused: {e}"); sys.exit(0 if expect_tls_fail else 1)
if big_payload:
    # A header that announces far more than any client message; nothing of it follows.
    s.sendall(struct.pack(">BdBI", 200, time.time(), 0, big_payload))
    print(f"  sent a header announcing {big_payload} payload bytes")
if "--junk" in flags:
    # Kinds this host does not know: it must skip their payloads and keep serving.
    s.sendall(msg(200, b"hello") + msg(201) + msg(6, json.dumps(sel).encode()))
    print("  sent two unknown-kind messages (200 with 5 bytes, 201 empty)")
def viewport(fps):
    return msg(9, json.dumps({"width": 1117, "height": 642, "scale": None, "fps": fps}).encode())
if fps_now is not None:
    s.sendall(viewport(fps_now)); print(f"  sent viewport fps={fps_now}")

def describe(d):
    st = d.get("settings", {})
    b = lambda x: 1 if x else 0
    stream = d.get("stream")
    running = (f"{stream['width']}x{stream['height']}@{stream['fps']}/{stream['mbps']}Mbps" + (" vd" if stream.get("onVirtualDisplay") else "")
               if stream else "none")
    note = d.get("virtualDisplayNote")
    dw = "-" if st.get("directWireless") is None else b(st.get("directWireless"))   # "-": an older host
    return (f"maxFPS={st.get('maxFPS')} bitrate={st.get('bitrate')} scale={st.get('captureScale')} speed={b(st.get('prioritizeSpeed'))} "
            f"vd={b(st.get('virtualDisplay'))} dw={dw} persistent={b(d.get('persistent'))} vdAvail={b(d.get('virtualDisplayAvailable'))} "
            f"sw={b(d.get('softwareEncoder'))} stream={running}" + (f" note={note!r}" if note else ""))

buf = b""; t0 = time.time(); last = t0; nextping = t0; nextstats = t0
per = {}; tot = {}; frames = 0; keys = 0; kb = 0; kb_sec = 0; rtt = None; first_frame = None; ps_seen = []
token = 1; last_state = None; settings_msgs = 0
pinging = True; reading = True; rtts = []; key_times = []; window_frames = {}; first_kinds = []; served = False; ages = []
def bump(k, n=1):
    per[k] = per.get(k, 0) + n; tot[k] = tot.get(k, 0) + n
def fire(e, now):
    global token
    _, _, name, text, parsed = e
    at = f"{now - t0:.3f}s"
    if name == "set":
        change = {"token": token, **parsed}; token += 1
        s.sendall(msg(17, json.dumps(change).encode())); print(f"  sent change {json.dumps(change)} at {at}")
    elif name == "raw17":
        s.sendall(msg(17, text.encode())); print(f"  sent raw kind 17 {text} at {at}")
    elif name == "pick":
        s.sendall(msg(6, json.dumps(parsed).encode())); print(f"  sent pick {text} at {at}")
    elif name == "fps-after":
        s.sendall(viewport(parsed)); print(f"  sent viewport fps={parsed} at {at}")
    elif name == "stop-ping":
        global pinging; pinging = False; print(f"  stopped pinging at {at}")
    elif name == "stop-read":
        global reading; reading = False; print(f"  stopped reading at {at}")
    elif name == "pairing-wanted":
        s.sendall(msg(21)); print(f"  sent kind 21 (pairing wanted) at {at}")
while time.time() - t0 < dur:
    now = time.time()
    while events and now - t0 >= events[0][0]:
        fire(events.pop(0), now)
    try:
        if pinging and now >= nextping:
            s.sendall(msg(10, struct.pack(">d", now))); nextping = now + 1
        if pinging and stats and now >= nextstats:
            s.sendall(msg(12, json.dumps({"fps": 0, "frameAgeMs": 0, "rttMs": 0, "device": device}).encode())); nextstats = now + 1
    except OSError as e:
        print(f"send failed at {now - t0:.2f}s: {e}"); break
    if not reading:
        # A client that stopped draining: nothing is read, so the host's queue to it fills.
        time.sleep(0.25 if not events else min(0.25, max(0.001, t0 + events[0][0] - now)))
        if now - last >= 1: print(f"t={now-t0:4.1f}s (not reading)"); last = now
        continue
    # Wake in time for the next timed send (a few ms matter for the race checks).
    wait = 0.25 if not events else min(0.25, max(0.001, t0 + events[0][0] - now))
    s.settimeout(wait)
    try:
        chunk = s.recv(1 << 20)
        if not chunk: print(f"EOF from host at {time.time() - t0:.2f}s"); break
        buf += chunk
    except socket.timeout: pass
    except OSError as e:
        print(f"read failed at {time.time() - t0:.2f}s: {e}"); break
    while len(buf) >= 14:
        kind, ts, key, ln = struct.unpack(">BdBI", buf[:14])
        if len(buf) < 14 + ln: break
        payload = buf[14:14+ln]; buf = buf[14+ln:]
        name = KIND.get(kind, str(kind)); bump(name); served = True
        if len(first_kinds) < 400 and kind not in (0, 1, 3, 11, 13): first_kinds.append(kind)
        if kind == 1:
            frames += 1; kb += ln / 1024; kb_sec += ln / 1024
            ages.append((time.time() - ts) * 1000)       # the host's clock is this Mac's: a true age
            w = int((time.time() - t0) // 5); window_frames[w] = window_frames.get(w, 0) + 1
            if key: keys += 1; key_times.append(round(time.time() - t0, 2))
            if first_frame is None:
                first_frame = time.time() - t0; print(f"  first frame at {first_frame:.2f}s, {ln} bytes, key={key}")
        elif kind == 0:
            ps_seen.append(round(time.time() - t0, 2)); print(f"  parameter sets at {ps_seen[-1]}s ({ln} bytes)")
        elif kind == 11:
            rtt = (time.time() - struct.unpack(">d", payload)[0]) * 1000; rtts.append(rtt)
        elif kind == 2:
            d = json.loads(payload); print(f"  windowList: {len(d.get('windows', []))} windows, active={d.get('active')}")
        elif kind == 18:
            ok, i = verify_macinfo(payload, mac_pin)
            addrs = ",".join(f"{a['host']}{':' + str(a['port']) if a.get('port') else ''}/{a['kind']}/{a['via']}" for a in i.get("addresses", []))
            print(f"  macInfo at {time.time()-t0:.3f}s: verified={1 if ok else 0} macID={i.get('macID')} name={i.get('name')!r} "
                  f"remoteAccess={1 if i.get('remoteAccess') else 0} port={i.get('remotePort')} internet={1 if i.get('internet') else 0} addresses=[{addrs}]")
        elif kind == 20:
            print(f"  pairResult at {time.time()-t0:.3f}s: {payload.decode(errors='replace')}")
        elif kind == 22:
            g = json.loads(payload)
            extra = "".join(f"; {k}: {json.dumps(g[k], ensure_ascii=False)}" for k in ("message", "minimumVersion", "reconnect") if k in g)
            print(f"  goodbye at {time.time()-t0:.3f}s: {g.get('reason')}{extra}")
        elif kind == 16:
            settings_msgs += 1
            try:
                d = json.loads(payload)
            except ValueError:
                print(f"  settings at {time.time()-t0:.3f}s: undecodable {payload[:80]!r}"); continue
            last_state = d
            print(f"  settings at {time.time()-t0:.3f}s answering={d.get('answering')} {describe(d)}")
    if now - last >= 1:
        f = per.get("frame", 0)
        # kB: the frames' payload this second (the encoder's output; ×8/1000 for Mbps).
        print(f"t={now-t0:4.1f}s frames={f:3d} kB={kb_sec:6.0f} ticks={per.get('tick',0):3d} cursor={per.get('cursor',0)} "
              f"rtt={rtt:.1f}ms" if rtt is not None else f"t={now-t0:4.1f}s frames={f:3d} kB={kb_sec:6.0f} ticks={per.get('tick',0):3d}")
        per = {}; kb_sec = 0; last = now
print(f"TOTAL {frames} frames ({keys} key) {kb:.0f} kB in {dur:.0f}s = {frames/dur:.1f} fps; kinds={tot}")
print(f"settings messages: {settings_msgs}")
def runs(ks):
    out = []
    for k in ks:
        if out and out[-1][0] == k: out[-1][1] += 1
        else: out.append([k, 1])
    return " ".join(f"{k}×{n}" if n > 1 else str(k) for k, n in out)
print(f"first kinds: {runs(first_kinds[:200])}")
if expect_tls_fail:
    print("EXPECT-TLS-FAIL ok: refused" if not served else "EXPECT-TLS-FAIL FAIL: a session was served")
    if served: sys.exit(1)
def pct(v, q):
    v = sorted(v); return v[min(len(v) - 1, int(round(q * (len(v) - 1))))] if v else float("nan")
windows = [window_frames.get(w, 0) for w in range(int(dur // 5))]
print(f"LINK rtt p50 {pct(rtts, .5):.1f} p95 {pct(rtts, .95):.1f} max {max(rtts) if rtts else float('nan'):.1f} ms over {len(rtts)} pongs; "
      f"keyframes at {key_times}; frames per 5 s {windows}; frame age p50 {pct(ages, .5):.2f} p95 {pct(ages, .95):.2f} ms")
s.close()
if expect is not None:
    problems = []
    if last_state is None:
        problems.append("no settings received")
    else:
        for k, want in expect.items():
            got = last_state.get(k) if k in ("persistent", "virtualDisplayAvailable") else last_state.get("settings", {}).get(k)
            same = (got == want) if isinstance(want, bool) else (got is not None and not isinstance(got, bool) and float(got) == float(want))
            if not same: problems.append(f"{k}: want {want}, got {got}")
    print("EXPECT ok" if not problems else "EXPECT FAIL " + "; ".join(problems))
    if problems: sys.exit(1)
