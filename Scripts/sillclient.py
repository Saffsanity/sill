#!/usr/bin/env python3
"""Minimal Sill wire-format client for testing a host without a device.

usage: sillclient.py PORT [seconds] [desktop|window:ID] [--junk] [--fps=N] [--fps-after=N@T]
  --junk          also send two unknown message kinds (the host must skip them)
  --fps=N         send a viewport asking for N fps right after the select
  --fps-after=N@T send a second viewport asking for N fps after T seconds
Find PORT with: lsof -nP -iTCP -sTCP:LISTEN -a -p <SillHost pid>. The --synthetic host does not
advertise over Bonjour, so this is the only way to reach it."""
import json, socket, struct, sys, time
port = int(sys.argv[1]); dur = float(sys.argv[2]) if len(sys.argv) > 2 else 12
src = sys.argv[3] if len(sys.argv) > 3 else "desktop"
KIND = {0:"ps",1:"frame",2:"list",3:"thumb",4:"icon",5:"apps",11:"pong",13:"tick",14:"cursor"}
def msg(kind, payload=b"", key=False):
    return struct.pack(">BdBI", kind, time.time(), 1 if key else 0, len(payload)) + payload
s = socket.create_connection(("127.0.0.1", port), timeout=5); s.settimeout(0.25)
sel = {"desktop":{}} if src == "desktop" else {"window":{"_0": int(src.split(":")[1])}}
s.sendall(msg(6, json.dumps(sel).encode()))
if "--junk" in sys.argv:
    # Kinds this host does not know: it must skip their payloads and keep serving.
    s.sendall(msg(200, b"hello") + msg(201) + msg(6, json.dumps(sel).encode()))
    print("  sent two unknown-kind messages (200 with 5 bytes, 201 empty)")
def viewport(fps):
    return msg(9, json.dumps({"width": 1117, "height": 642, "scale": None, "fps": fps}).encode())
fps_now = None; fps_later = None; fps_later_at = None
for a in sys.argv:
    if a.startswith("--fps="): fps_now = int(a[6:])
    if a.startswith("--fps-after="):   # e.g. --fps-after=60@3  (send fps 60 after 3 s)
        v, t = a[12:].split("@"); fps_later, fps_later_at = int(v), float(t)
if fps_now is not None:
    s.sendall(viewport(fps_now)); print(f"  sent viewport fps={fps_now}")
buf = b""; t0 = time.time(); last = t0; nextping = t0
per = {}; tot = {}; frames = 0; keys = 0; kb = 0; rtt = None; first_frame = None; ps_seen = []
def bump(k, n=1):
    per[k] = per.get(k, 0) + n; tot[k] = tot.get(k, 0) + n
while time.time() - t0 < dur:
    now = time.time()
    if fps_later is not None and now - t0 >= fps_later_at:
        s.sendall(viewport(fps_later)); print(f"  sent viewport fps={fps_later} at {now-t0:.1f}s"); fps_later = None
    if now >= nextping:
        s.sendall(msg(10, struct.pack(">d", now))); nextping = now + 1
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
    if now - last >= 1:
        f = per.get("frame", 0)
        print(f"t={now-t0:4.1f}s frames={f:3d} ticks={per.get('tick',0):3d} cursor={per.get('cursor',0)} "
              f"rtt={rtt:.1f}ms" if rtt is not None else f"t={now-t0:4.1f}s frames={f:3d} ticks={per.get('tick',0):3d}")
        per = {}; last = now
print(f"TOTAL {frames} frames ({keys} key) {kb:.0f} kB in {dur:.0f}s = {frames/dur:.1f} fps; kinds={tot}")
s.close()
