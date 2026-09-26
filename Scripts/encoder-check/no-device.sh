#!/bin/zsh
# Exit 0 only when no device is connected to this Mac's Sill.app, read from its log: the LAST
# "[30s] idle · 0 clients" or "Client left" line is newer than the last "Client connected"/"Remote
# client connected" line, AND the last stats line is not a "[1s] … · N client(s)" line (N >= 1)
# from the last 60 s. "Last" is by each line's own timestamp, not by its place in the file: two
# Sill.app processes writing the log at once (a relaunch) interleave their lines (HostLog's file
# sink writes at its own offset), so file order is not time order.
# Stricter than that where two Sill.app processes run at once (one idle, one streaming): any
# "[1s] … · N client(s)" line in the last 60 s blocks, not only the newest stats line.
# With --since 'YYYY-MM-DD HH:MM:SS': also fail if any connect line is at or after that time.
# Why: a hardware encoder run beside a stream shares the Mac's one encoder engine with it (CLAUDE.md,
# "Busy, not stuck": the operational rule). SILL_LOG_DIR overrides ~/Library/Logs/Sill.
L=${SILL_LOG_DIR:-$HOME/Library/Logs/Sill}
cat $L/Sill.1.log $L/Sill.log 2>/dev/null | python3 -c '
import re, sys, datetime
since = sys.argv[1] if len(sys.argv) > 1 else None
def ts(s):
    try: return datetime.datetime.strptime(s[:23], "%Y-%m-%d %H:%M:%S.%f")
    except Exception: return None
free = conn = stat = recent = None
now = datetime.datetime.now()
for s in sys.stdin.read().splitlines():
    t = ts(s)
    if t is None: continue
    if re.search(r"\[30s\] idle · 0 clients|Client left", s) and (free is None or t >= free[0]): free = (t, s)
    if re.search(r"Client connected|Remote client connected", s) and (conn is None or t >= conn[0]): conn = (t, s)
    if re.match(r"\S+ \S+ \[(1s\]|30s\] idle)", s) and (stat is None or t >= stat[0]): stat = (t, s)
    m = re.search(r"\[1s\] .* · (\d+) clients?$", s)
    if m and int(m.group(1)) >= 1 and (now - t).total_seconds() < 60 and (recent is None or t >= recent[0]): recent = (t, s)
print("now:        ", now.strftime("%H:%M:%S"))
print("last free:  ", free[1][:120] if free else None)
print("last conn:  ", conn[1][:120] if conn else None)
print("last stats: ", stat[1][:120] if stat else None)
ok = True
if conn and (not free or free[0] < conn[0]):
    ok = False; print("NOT OK: a client connected after the last idle/left line")
if stat:
    m = re.search(r"\[1s\] .* · (\d+) clients?$", stat[1])
    if m and int(m.group(1)) >= 1 and (now - stat[0]).total_seconds() < 60:
        ok = False; print("NOT OK: the last stats line has %s client(s), %.0f s ago" % (m.group(1), (now - stat[0]).total_seconds()))
if recent:
    ok = False; print("NOT OK: a stats line with a client %.0f s ago: %s" % ((now - recent[0]).total_seconds(), recent[1][:90]))
if since and conn and conn[0] >= datetime.datetime.strptime(since, "%Y-%m-%d %H:%M:%S"):
    ok = False; print("NOT OK: a client connected since " + since)
print("OK: no device connected" if ok else "BLOCKED: do not use the hardware encoder")
sys.exit(0 if ok else 1)
' "$@"
