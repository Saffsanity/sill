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
At exit a LINK line gives the pong round trip (p50/p95/max over every pong), the keyframes' arrival
times, and the frames received in each 5 s window.
Every kind 16 (host settings) is printed on one line with its arrival time; dw= is Direct Wireless
(1, 0, or - when the host did not report it: an older host). Flags may come in any
order after the positional arguments. Everything is checked before connecting: an unknown flag, a
--set or --expect key that is not one of theirs, or a value that does not parse stops the script
with status 2 (--raw17 goes out as written). Find PORT with: lsof -nP -iTCP -sTCP:LISTEN -a -p <pid>.
The --synthetic hosts do not advertise over Bonjour, so this is the only way to reach them."""
import json, re, socket, struct, sys, time

KIND = {0:"ps",1:"frame",2:"list",3:"thumb",4:"icon",5:"apps",11:"pong",13:"tick",14:"cursor",16:"settings"}
BOOL = {"1": True, "0": False, "true": True, "false": False, "on": True, "off": False, "yes": True, "no": False}
BOOL_KEYS = {"prioritizeSpeed", "virtualDisplay", "directWireless", "persistent", "virtualDisplayAvailable"}
# What --set may send: HostSettingsChange's six fields. The host drops any other key without a
# word, so a misspelt one would only show up as an unchanged answer.
SET_KEYS = {"maxFPS", "bitrate", "captureScale", "prioritizeSpeed", "virtualDisplay", "directWireless"}
EXPECT_KEYS = SET_KEYS | {"persistent", "virtualDisplayAvailable"}
TIMED = ("set", "raw17", "pick", "fps-after", "stop-ping", "stop-read")
VALUED = ("host", "device", "big-payload", "flood")

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
        bare = re.fullmatch(r"--(stop-ping|stop-read)@([^=]*)", a)     # timed flags without a value
        name, _, body = (bare.group(1), "", "@" + bare.group(2)) if bare else a[2:].partition("=")
        if name in TIMED:
            text, at, t = body.rpartition("@")
            if not at: raise ValueError(f"--{name}: no @T (seconds in) in {a!r}")
            if name in ("stop-ping", "stop-read") and text: raise ValueError(f"--{name}@T takes no value")
            parsed = (pairs(text, SET_KEYS, "--set") if name == "set" else source(text) if name == "pick"
                      else number(text, "--fps-after") if name == "fps-after" else text)
            events.append((number(t, f"--{name}'s @T", float), i, name, text, parsed))
        elif name in VALUED:
            if not body: raise ValueError(f"--{name} needs a value")
            if name in ("big-payload", "flood") and number(body, f"--{name}") < 1: raise ValueError(f"--{name} must be at least 1")
        elif a not in ("--junk", "--stats") and not a.startswith(("--fps=", "--expect=")):
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
except ValueError as e:
    print(f"sillclient.py: {e}", file=sys.stderr); sys.exit(2)
stats = "--stats" in flags or device is not None
device = device if device is not None else "sillclient"

if flood:
    # Connections that are reset before a byte is sent: the door must not keep them (no descriptor
    # growth) and must not log them as clients.
    for _ in range(flood):
        f = socket.create_connection((host, port), timeout=5)
        f.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack("ii", 1, 0))
        f.close()
    print(f"  flood: {flood} connections opened and reset before sending")
s = socket.create_connection((host, port), timeout=5); s.settimeout(0.25)
s.sendall(msg(6, json.dumps(sel).encode()))
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
per = {}; tot = {}; frames = 0; keys = 0; kb = 0; rtt = None; first_frame = None; ps_seen = []
token = 1; last_state = None; settings_msgs = 0
pinging = True; reading = True; rtts = []; key_times = []; window_frames = {}
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
        name = KIND.get(kind, str(kind)); bump(name)
        if kind == 1:
            frames += 1; kb += ln / 1024
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
        print(f"t={now-t0:4.1f}s frames={f:3d} ticks={per.get('tick',0):3d} cursor={per.get('cursor',0)} "
              f"rtt={rtt:.1f}ms" if rtt is not None else f"t={now-t0:4.1f}s frames={f:3d} ticks={per.get('tick',0):3d}")
        per = {}; last = now
print(f"TOTAL {frames} frames ({keys} key) {kb:.0f} kB in {dur:.0f}s = {frames/dur:.1f} fps; kinds={tot}")
print(f"settings messages: {settings_msgs}")
def pct(v, q):
    v = sorted(v); return v[min(len(v) - 1, int(round(q * (len(v) - 1))))] if v else float("nan")
windows = [window_frames.get(w, 0) for w in range(int(dur // 5))]
print(f"LINK rtt p50 {pct(rtts, .5):.1f} p95 {pct(rtts, .95):.1f} max {max(rtts) if rtts else float('nan'):.1f} ms over {len(rtts)} pongs; "
      f"keyframes at {key_times}; frames per 5 s {windows}")
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
