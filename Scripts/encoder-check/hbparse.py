#!/usr/bin/env python3
# AppleAVE2 HeartBeat lines (log show --info --debug --style compact, sender == "AppleAVE2") ->
# per 5 s window: each session's frames completed and fps, and the engine's counters per frame
# (C/F is what the 2026-09-25 investigation read as the time per frame on the encoder: 9.0 ms in
# the fast state, 14.0 in the slow one, alone on the engine at 3024×1964; the counters are the
# engine's, so C/F is only a session's own when it is alone on the engine). A/s: the first
# counter's growth a second. CLAUDE.md, "The 33 fps plateau".
# usage: hbparse.py FILE      (the output of the log show above)
import re, sys
res, prev = {}, None
for ln in open(sys.argv[1]):
    m = re.match(r'(\S+) (\S+) .*?\(AppleAVE2\) (\d+) \d+ (.*)', ln.strip())
    if not m: continue
    d, t, us, msg = m.groups()
    r = re.search(r'ID: (\d+) Resolution: (\d+x\d+).*?Priority: (\d+)', msg)
    if r:
        res[r.group(1)] = r.group(2) + ' p' + r.group(3)
        print(f'{t} session {r.group(1)} opened: {r.group(2)} priority {r.group(3)}')
        continue
    h = re.search(r'HeartBeat <private> (\d+) (\d+) (\d+) - (\d+) - (\d+) \| (\d+) \[(.*)\]', msg)
    if not h: continue
    a, c = int(h.group(3)), int(h.group(5))
    sess = {x[0]: (int(x[1]), int(x[2])) for x in re.findall(r'(\d+)\((\d+) \| (\d+)\)', h.group(7))}
    us = int(us)
    if prev and sess:
        dt = (us - prev['us']) / 1e6
        per = {k: v[1] - prev['sess'][k][1] for k, v in sess.items() if k in prev['sess']}
        new = [k for k in sess if k not in prev['sess']]
        dF = sum(per.values())
        parts = '  '.join(f"{k}({res.get(k, '?')}) {n/dt:5.1f} fps" for k, n in per.items()) + ''.join(f'  {k} new' for k in new)
        if dF > 0:
            print(f"{t} {parts}  | engine C/F {(c - prev['c'])/dF:5.2f} ms  A/s {(a - prev['a'])/dt:6.1f}"
                  + ("  (shared)" if len([n for n in per.values() if n > 0]) > 1 else ""))
        else:
            print(f"{t} {parts or 'no session'}  | idle window")
    elif sess:
        print(f"{t} first beat: " + ', '.join(f"{k}({res.get(k, '?')})" for k in sess))
    prev = dict(sess=sess, a=a, c=c, us=us)
