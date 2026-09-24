#!/usr/bin/env python3
"""Minimal Sill wire-format client for testing a host without a device.

usage: sillclient.py PORT [seconds] [desktop|none|window:ID] [flags...]
  --junk             also send two unknown message kinds (the host must skip them)
  --fps=N            send a viewport asking for N fps right after the select
  --fps-after=N@T    send a second viewport asking for N fps after T seconds
  --set=K=V[,K=V]@T  send a settings change (kind 17) T seconds in, with integer tokens 1, 2, 3...
                     in send order. Keys: maxFPS, bitrate, captureScale, prioritizeSpeed,
                     virtualDisplay; booleans accept 1/0/true/false/on/off
  --raw17=JSON@T     send this literal kind 17 payload T seconds in (split on the last @)
  --pick=SRC@T       a timed selectSource: none, desktop or window:ID
  --stats            send ClientStats (kind 12) once a second as device "sillclient", so the host
                     logs a name for this client
  --expect=K=V[,...] at exit, compare the last kind 16's settings (and its top-level persistent
                     and virtualDisplayAvailable): prints EXPECT ok or EXPECT FAIL, exits 1 on failure
Every kind 16 (host settings) is printed on one line with its arrival time. Flags may come in any
order after the positional arguments. Everything is checked before connecting: an unknown flag, a
--set or --expect key that is not one of theirs, or a value that does not parse stops the script
with status 2 (--raw17 goes out as written). Find PORT with: lsof -nP -iTCP -sTCP:LISTEN -a -p <pid>.
The --synthetic hosts do not advertise over Bonjour, so this is the only way to reach them."""
import json, socket, struct, sys, time

KIND = {0:"ps",1:"frame",2:"list",3:"thumb",4:"icon",5:"apps",11:"pong",13:"tick",14:"cursor",16:"settings"}
BOOL = {"1": True, "0": False, "true": True, "false": False, "on": True, "off": False, "yes": True, "no": False}
BOOL_KEYS = {"prioritizeSpeed", "virtualDisplay", "persistent", "virtualDisplayAvailable"}
# What --set may send: HostSettingsChange's five fields. The host drops any other key without a
# word, so a misspelt one would only show up as an unchanged answer.
SET_KEYS = {"maxFPS", "bitrate", "captureScale", "prioritizeSpeed", "virtualDisplay"}
EXPECT_KEYS = SET_KEYS | {"persistent", "virtualDisplayAvailable"}
TIMED = ("set", "raw17", "pick", "fps-after")

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
        name, _, body = a[2:].partition("=")
        if name in TIMED:
            text, at, t = body.rpartition("@")
            if not at: raise ValueError(f"--{name}: no @T (seconds in) in {a!r}")
            parsed = (pairs(text, SET_KEYS, "--set") if name == "set" else source(text) if name == "pick"
                      else number(text, "--fps-after") if name == "fps-after" else text)
            events.append((number(t, f"--{name}'s @T", float), i, name, text, parsed))
        elif a not in ("--junk", "--stats") and not a.startswith(("--fps=", "--expect=")):
            raise ValueError(f"unknown flag {a!r}")
    events.sort(key=lambda e: (e[0], e[1]))
    expect = next((pairs(a[9:], EXPECT_KEYS, "--expect") for a in flags if a.startswith("--expect=")), None)
    fps_now = next((number(a[6:], "--fps") for a in flags if a.startswith("--fps=")), None)
except ValueError as e:
    print(f"sillclient.py: {e}", file=sys.stderr); sys.exit(2)
stats = "--stats" in flags

s = socket.create_connection(("127.0.0.1", port), timeout=5); s.settimeout(0.25)
s.sendall(msg(6, json.dumps(sel).encode()))
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
    return (f"maxFPS={st.get('maxFPS')} bitrate={st.get('bitrate')} scale={st.get('captureScale')} speed={b(st.get('prioritizeSpeed'))} "
            f"vd={b(st.get('virtualDisplay'))} persistent={b(d.get('persistent'))} vdAvail={b(d.get('virtualDisplayAvailable'))} "
            f"sw={b(d.get('softwareEncoder'))} stream={running}" + (f" note={note!r}" if note else ""))

buf = b""; t0 = time.time(); last = t0; nextping = t0; nextstats = t0
per = {}; tot = {}; frames = 0; keys = 0; kb = 0; rtt = None; first_frame = None; ps_seen = []
token = 1; last_state = None; settings_msgs = 0
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
while time.time() - t0 < dur:
    now = time.time()
    while events and now - t0 >= events[0][0]:
        fire(events.pop(0), now)
    if now >= nextping:
        s.sendall(msg(10, struct.pack(">d", now))); nextping = now + 1
    if stats and now >= nextstats:
        s.sendall(msg(12, json.dumps({"fps": 0, "frameAgeMs": 0, "rttMs": 0, "device": "sillclient"}).encode())); nextstats = now + 1
    # Wake in time for the next timed send (a few ms matter for the race checks).
    wait = 0.25 if not events else min(0.25, max(0.001, t0 + events[0][0] - now))
    s.settimeout(wait)
    try:
        chunk = s.recv(1 << 20)
        if not chunk: print("EOF from host"); break
        buf += chunk
    except socket.timeout: pass
    while len(buf) >= 14:
        kind, ts, key, ln = struct.unpack(">BdBI", buf[:14])
        if len(buf) < 14 + ln: break
        payload = buf[14:14+ln]; buf = buf[14+ln:]
        name = KIND.get(kind, str(kind)); bump(name)
        if kind == 1:
            frames += 1; kb += ln / 1024
            if key: keys += 1
            if first_frame is None:
                first_frame = time.time() - t0; print(f"  first frame at {first_frame:.2f}s, {ln} bytes, key={key}")
        elif kind == 0:
            ps_seen.append(round(time.time() - t0, 2)); print(f"  parameter sets at {ps_seen[-1]}s ({ln} bytes)")
        elif kind == 11:
            rtt = (time.time() - struct.unpack(">d", payload)[0]) * 1000
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
