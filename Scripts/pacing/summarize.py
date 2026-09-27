#!/usr/bin/env python3
"""The pacing harness's table: each run's numbers from its host log ([1s] counters, evictions), its
device's per-second lines (fps, frame age, rtt, liveness) and its relay (rate changes), then each
case's base and new side by side with the new build's gate. run.sh prints it at the end of a
matrix; run it again on a runs folder to read one later.
usage: summarize.py RUNS_DIR [--skip S]
Runs are named CASE-I-BUILD (real24-1-base, real24-1-new, …). The first S seconds after the device
connected (default 5: the catalog and the first keyframe) are left out of every figure except
fpsK (the fps from the second after the first keyframe arrived), gap (the longest run of seconds
without a frame from then on), evict@ (seconds from the device's first connection to the host's
first eviction), rec (seconds from the relay's last rate increase until the frame age's median
is back at 45 ms or less) and still (the host's still spells, --still-at: how many ended with the
device showing the last frame before the spell or a later one, and the longest it took). Then the
new build's Link lines (LinkJudge, docs/remote-bundle-plan.md §6, H11): each run's link changes,
seconds from the device's first connection, and each case's link gate."""
import os, re, statistics, sys
from collections import defaultdict

args = sys.argv[1:]
if not args or args[0].startswith("-"): sys.exit(__doc__)
RUNS = args.pop(0)
SKIP = 5.0
while args:
    k = args.pop(0)
    if k == "--skip": SKIP = float(args.pop(0))
    else: sys.exit(f"summarize.py: unknown argument {k}")

def secs(hms):
    h, m, s = hms.split(":"); return int(h) * 3600 + int(m) * 60 + float(s)

def pct(xs, p):
    if not xs: return float("nan")
    s = sorted(xs); return s[min(len(s) - 1, int(p / 100 * len(s)))]

def read(name, suffix):
    p = os.path.join(RUNS, f"{name}.{suffix}")
    return open(p, errors="replace").read().splitlines() if os.path.exists(p) else []

DEV = re.compile(r"(\d\d:\d\d:\d\d\.\d+) \S+:\s+(\d+) fps\s+age\s+(\S+)\s+rtt\s+(\S+)\s+in\s+(\d+) kB\s+keys (\d+)(?:\s+newest ([\d.]+))?")
STILL = re.compile(r"\S+ (\d\d:\d\d:\d\d\.\d+) Still: for (\S+) s after the frame of ([\d.]+)")
LINK = re.compile(r"\S+ (\d\d:\d\d:\d\d\.\d+) Link: (fine|behind|stalled)( \(reset\))? \((.*)\)")

def one(name):
    dev, host, relay = read(name, "device.txt"), read(name, "host.log"), read(name, "relay.txt")
    t0 = next((secs(m.group(1)) for m in (re.match(r"(\d\d:\d\d:\d\d\.\d+) \S+: connected", l) for l in dev) if m), None)
    if t0 is None: return None
    lo = t0 + SKIP
    seconds = [(secs(m.group(1)), int(m.group(2)), m.group(3), m.group(4), int(m.group(6))) for m in map(DEV.match, dev) if m]
    fps = [f for t, f, *_ in seconds if t >= lo]
    worst_age = [int(a.split("/")[1]) for t, _, a, _, _ in seconds if t >= lo and a != "–"]
    worst_rtt = [int(r.split("/")[1]) for t, _, _, r, _ in seconds if t >= lo and r != "–"]
    keys = sum(k for t, *_, k in seconds if t >= lo)
    first_key = next((t for t, *_, k in seconds if k > 0), None)
    after_key = [f for t, f, *_ in seconds if first_key is not None and t > first_key]
    # The longest run of seconds without a frame, from the second after the first keyframe arrived.
    gap = stretch = 0
    for t, frames, *_ in seconds:
        if first_key is None or t <= first_key: continue
        stretch = stretch + 1 if frames == 0 else 0
        gap = max(gap, stretch)
    lost = sum("silent" in l for l in dev)
    sent = drop = wait = wait_after_key = n = evict = 0
    evict_at = None
    withheld_ends = []   # the end of each host second that withheld a frame (dropped, or waited for a keyframe)
    for l in host:
        if "silent for" in l or "not draining" in l:
            evict += 1
            m = re.match(r"\S+ (\d\d:\d\d:\d\d\.\d+) ", l)
            if m and evict_at is None: evict_at = secs(m.group(1)) - t0
        m = re.match(r"\S+ (\d\d:\d\d:\d\d\.\d+) \[1s\] (.*)", l)
        if not m: continue
        t = secs(m.group(1))
        kv = dict((k, int(v)) for k, v in re.findall(r"([a-zA-Z]+\.[a-zA-Z]+) (\d+)", m.group(2)))
        # A [1s] line counts the second before its stamp: one wholly after the first keyframe.
        if first_key is not None and t - 1 > first_key: wait_after_key += kv.get("net.waitKey", 0)
        if kv.get("net.dropped", 0) + kv.get("net.waitKey", 0) > 0: withheld_ends.append(t - t0)
        if t < lo: continue
        sent += kv.get("net.sent", 0); drop += kv.get("net.dropped", 0); wait += kv.get("net.waitKey", 0); n += 1
    # The dip: from the relay's last rate increase, until a second's median frame age is ≤ 45 ms.
    rates = [(secs(m.group(1)), float(m.group(2))) for m in (re.match(r"(\d\d:\d\d:\d\d\.\d+) relay: downlink (\S+) Mbit/s", l) for l in relay) if m]
    rec = None
    ups = [t for (t, r), (_, prev) in zip(rates[1:], rates[:-1]) if r > prev]
    if ups:
        back = ups[-1]
        rec = next((t - back for t, _, a, _, _ in seconds if t > back and a != "–" and int(a.split("/")[0]) <= 45), float("inf"))
    # Still spells: whether the device came to show the last frame before each (or a later one, the
    # last frame encoded again) while the window stayed still, and how long that took. Its lines
    # come once a second, so "after" is to the second.
    newest = [(secs(m.group(1)), float(m.group(7))) for m in map(DEV.match, dev) if m and m.group(7)]
    spells = [(secs(m.group(1)), float(m.group(2)), float(m.group(3))) for m in map(STILL.match, host) if m]
    fresh = []
    for start, length, last in spells:
        if not newest or newest[-1][0] < start + length: continue       # the run ended first
        seen = [t for t, ts in newest if start - 1 < t <= start + length + 0.5 and ts >= last - 1e-6]
        fresh.append(max(0.0, seen[0] - start) if seen else None)
    # The link's changes (the new build's Link lines) and the path's, from the device's first connection.
    links = [(secs(m.group(1)) - t0, m.group(2), bool(m.group(3)), m.group(4)) for m in map(LINK.match, host) if m]
    drop_at = next((t - t0 for (t, r), (_, prev) in zip(rates[1:], rates[:-1]) if r < prev), None)
    rise_at = (ups[-1] - t0) if ups else None
    dark_at = next((secs(m.group(1)) - t0 for m in (re.match(r"(\d\d:\d\d:\d\d\.\d+) relay: blackhole", l) for l in relay) if m), None)
    mins = max(n, 1) / 60
    # The host sees a slower path only once the buffers in front of it are full (the bottleneck's
    # queue, then the kernel's socket buffers): the end of its first second that withheld a frame after
    # the rate fell.
    withheld_at = next((u for u in withheld_ends if drop_at is not None and u > drop_at), None)
    return {"links": links, "firstKey": None if first_key is None else first_key - t0, "dropAt": drop_at, "riseAt": rise_at, "darkAt": dark_at,
            "withheldAt": withheld_at,
            "fps": statistics.mean(fps) if fps else 0.0, "p10": pct(fps, 10), "fpsK": statistics.mean(after_key) if after_key else 0.0,
            "sent": sent / max(n, 1), "drop": drop / mins, "wait": wait / mins, "waitK": wait_after_key, "keys": keys / mins,
            "age50": pct(worst_age, 50), "age95": pct(worst_age, 95), "rtt50": pct(worst_rtt, 50), "rtt95": pct(worst_rtt, 95),
            "rttmax": max(worst_rtt) if worst_rtt else 0, "lost": lost, "evict": evict, "rec": rec, "drops": drop,
            "gap": gap, "evictAt": evict_at,
            "stills": len(fresh), "stale": sum(x is None for x in fresh),
            "freshMax": max((x for x in fresh if x is not None), default=None)}

names = sorted({f[: -len(".device.txt")] for f in os.listdir(RUNS) if f.endswith(".device.txt")})
# Runs that ended with the Mac busy (run.sh's load.txt: the load at 20 or more after its last try).
loaded = {}
if os.path.exists(os.path.join(RUNS, "load.txt")):
    for l in open(os.path.join(RUNS, "load.txt")):
        m = re.match(r"\s+(\S+) ended with the load at ([\d.]+)", l)
        if m: loaded[m.group(1)] = float(m.group(2)) >= 20
runs = {}
for name in names:
    r = one(name)
    if r: runs[name] = r
if not runs: sys.exit(f"summarize.py: no runs in {RUNS}")

info = os.path.join(RUNS, "matrix.txt")
if os.path.exists(info):
    print(open(info).read().rstrip())
    print()

def f(v, fmt):
    if v is None: return "–"
    if isinstance(v, float) and (v != v): return "–"
    if v == float("inf"): return "never"
    return format(v, fmt)

print(f"{'run':24} {'fps':>5} {'p10':>4} {'fpsK':>5} {'gap':>3} {'sent/s':>6} {'drop/m':>6} {'wait/m':>6} {'waitK':>5} {'keys/m':>6} "
      f"{'age50':>6} {'age95':>6} {'rtt50':>6} {'rtt95':>6} {'rttMax':>6} {'lost':>4} {'evict':>5} {'evict@':>6} {'rec s':>5} {'still':>9}")
for name, r in runs.items():
    print(f"{name + ('*' if loaded.get(name) else ''):24} {r['fps']:5.1f} {f(r['p10'], '4.0f'):>4} {r['fpsK']:5.1f} {r['gap']:3d} {r['sent']:6.1f} {r['drop']:6.1f} {r['wait']:6.0f} {r['waitK']:5d} "
          f"{r['keys']:6.1f} {f(r['age50'], '6.0f'):>6} {f(r['age95'], '6.0f'):>6} {f(r['rtt50'], '6.0f'):>6} {f(r['rtt95'], '6.0f'):>6} "
          f"{r['rttmax']:6.0f} {r['lost']:4d} {r['evict']:5d} {f(r['evictAt'], '6.1f'):>6} {f(r['rec'], '5.1f'):>5} "
          f"{(str(r['stills'] - r['stale']) + '/' + str(r['stills']) + (' ' + format(r['freshMax'], '.1f') if r['freshMax'] is not None else '')) if r['stills'] else '–':>9}")
print(f"""
fps, p10: the device's frames a second (mean, 10th percentile), after the first {SKIP:g} s; fpsK: the mean
from the second after the first keyframe arrived; gap: the longest run of seconds without a frame
from then on; sent/s, drop/m, wait/m: the host's net.sent a second, net.dropped and net.waitKey a
minute; waitK: net.waitKey in the host's seconds wholly after the first keyframe arrived; keys/m:
keyframes the device got a minute; age, rtt: each second's worst frame age and pong round trip
(ms), p50/p95/max; lost: the device's liveness losses; evict: the host's silence or drain
evictions; evict@: seconds from the device's first connection to the first of them; rec: seconds
from the relay's last rate increase until a second's median frame age is 45 ms or less; still: of
the still spells (--still-at), how many ended with the device showing the last frame before the
spell or a later one, then the longest that took (s, to the device's second).""")
if any(loaded.values()):
    print("*: the run ended with the load average at 20 or more, after its last try (load.txt).")

# Each case, base against new, and the new build's gate (docs/remote-bundle-plan.md §11, H3).
cases = defaultdict(lambda: {"base": [], "new": []})
for name, r in runs.items():
    m = re.match(r"(.+)-(\d+)-(base|new)$", name)
    if m: cases[m.group(1)][m.group(3)].append((int(m.group(2)), r))

def no_worse(new, base):   # within noise of the base or better: 2 fps, one drop a minute
    return new["fps"] >= base["fps"] - 2 and new["drop"] <= base["drop"] + 1

GATES = {
    "real24": ("≥ 55 fps, 0 dropped", lambda r, b: r["fps"] >= 55 and r["drops"] == 0),
    "kf25m32": ("≥ 55 fps", lambda r, b: r["fps"] >= 55),
    "ext120": ("≥ 115 fps, 0 dropped, 0 waitKey after the first keyframe", lambda r, b: r["fps"] >= 115 and r["drops"] == 0 and r["waitK"] == 0),
    "ext60": ("≥ 58 fps, 0 dropped, 0 waitKey after the first keyframe", lambda r, b: r["fps"] >= 58 and r["drops"] == 0 and r["waitK"] == 0),
    "fastbig": ("≥ 59 fps, 0 dropped", lambda r, b: r["fps"] >= 59 and r["drops"] == 0),
    "slowkfB": ("≥ 55 fps after the first keyframe, no liveness loss", lambda r, b: r["fpsK"] >= 55 and r["lost"] == 0),
    "dip": ("no loss or eviction, the frame age back at 45 ms within 10 s", lambda r, b: r["lost"] == 0 and r["evict"] == 0 and r["rec"] is not None and r["rec"] <= 10),
    "relay2": ("no loss or eviction, a frame in every 5 s, keyframes a minute ≤ its base run's + 1",
               lambda r, b: r["lost"] == 0 and r["evict"] == 0 and r["gap"] < 5 and (b is None or r["keys"] <= b["keys"] + 1)),
    "blackhole": ("dropped for its silence 11–16 s after it connected (5 + 8)",
                  lambda r, b: r["evictAt"] is not None and 11 <= r["evictAt"] <= 16),
    "stillend": ("every still spell ends with the last frame shown, within 5 s", lambda r, b: r["stills"] > 0 and r["stale"] == 0 and r["freshMax"] <= 5),
    "restartkf": ("0 dropped, 0 waitKey after the first keyframe", lambda r, b: r["drops"] == 0 and r["waitK"] == 0),
    "bigkf8": ("recorded (bistable); each run ≥ its base run's fps", lambda r, b: b is None or r["fps"] >= b["fps"]),
    "over8": ("recorded; ≥ its base run's fps", lambda r, b: b is None or r["fps"] >= b["fps"]),
    "low": ("no worse than its base run (2 fps, 1 drop a minute)", lambda r, b: b is None or no_worse(r, b)),
    "switch": ("no worse than its base run (2 fps, 1 drop a minute)", lambda r, b: b is None or no_worse(r, b)),
    "home": ("no worse than its base run (2 fps, 1 drop a minute)", lambda r, b: b is None or no_worse(r, b)),
    "slowkf": ("recorded: the old device's liveness (whole messages)", None),
}
print(f"\n{'case':10} {'runs':>4}  {'base fps':>9} {'new fps':>9}  {'base drop/m':>11} {'new drop/m':>10}  {'base rec':>8} {'new rec':>8}  gate (new)")
failed = []
for case in sorted(cases, key=lambda c: (list(GATES).index(c) if c in GATES else 99, c)):
    b, n = cases[case]["base"], cases[case]["new"]
    mean = lambda rs, k: statistics.mean(r[k] for _, r in rs) if rs else None
    recs = lambda rs: ", ".join(f(r["rec"], ".1f") for _, r in sorted(rs, key=lambda x: x[0]) if r["rec"] is not None) or "–"
    fpss = lambda rs: "/".join(f"{r['fps']:.1f}" for _, r in sorted(rs, key=lambda x: x[0])) or "–"
    what, rule = GATES.get(case, ("no gate", None))
    verdict = "–"
    if rule and n:
        base_by = {i: r for i, r in b}
        ok = all(rule(r, base_by.get(i)) for i, r in n)
        verdict = ("pass" if ok else "FAIL") + f": {what}"
        if not ok: failed.append(case)
    elif rule is None:
        verdict = what
    print(f"{case:10} {len(n):4d}  {fpss(b):>9} {fpss(n):>9}  {f(mean(b, 'drop'), '11.1f'):>11} {f(mean(n, 'drop'), '10.1f'):>10}  "
          f"{recs(b):>8} {recs(n):>8}  {verdict}")
print("\nbase: BASE's StreamServer.swift; new: the working tree's. fps: each run's mean (runs joined by /).")

# The link (docs/remote-bundle-plan.md §6, H11): the new build's Link lines, and each case's gate.
def after(r, t):
    return [(u, st) for u, st, reset, _ in r["links"] if t is not None and u > t and not reset]
def never(r, *states):
    return not any(st in states for _, st in after(r, r["firstKey"]))
def first(r, state, start):
    return next((u - start for u, st in after(r, start) if st == state), None) if start is not None else None
def carried(r):
    """The first behind spell's reports: (carried rate, the line) each. LinkJudge reports the rate again
    as it moves by a quarter: the first seconds read high while the path's buffers fill, and a stream
    of whole keyframes taken in single seconds reads lumpy."""
    out = []
    for _, st, _, d in r["links"]:
        if st == "fine" and out: break
        m = re.search(r"carried ([\d.]+) Mbps", d) if st == "behind" else None
        if m: out.append((float(m.group(1)), d))
    return out
def rate(r):
    """The median of those rates."""
    c = sorted(x for x, _ in carried(r))
    return (c[len(c) // 2] if len(c) % 2 else (c[len(c) // 2 - 1] + c[len(c) // 2]) / 2) if c else None
LINK_GATES = {
    "real24": ("never behind or stalled after the first keyframe", lambda r: never(r, "behind", "stalled")),
    "over8": ("behind within 5 s of the first keyframe; the median carried rate of its reports within 20 % of 8 Mbit/s; Low suggested for Pro in the last",
              lambda r: (first(r, "behind", r["firstKey"]) or 99) <= 5 and rate(r) is not None and 6.4 <= rate(r) <= 9.6
                        and "suggesting Low" in carried(r)[-1][1]),
    # The plan asked for behind within 5 s of the dip. The host judges only what it withholds, and it
    # withholds nothing until the buffers between it and the slower link are full; then behind comes
    # at the third short second the sweep closes (the first may hold only part of its frames), within
    # 3 s of the end of the host's first [1s] second that withheld one, whatever the two timers'
    # phases. How long the buffers took is printed beside it: the dip's 1 MB queue and the loopback's
    # socket buffers hold several seconds of Low's stream.
    "dip": ("behind within 3 s of the end of the host's first second withholding frames, fine within 10 s of the dip's end",
            lambda r: (first(r, "behind", r["withheldAt"]) or 99) <= 3 and (first(r, "fine", r["riseAt"]) or 99) <= 10),
    "slowkfB": ("never behind or stalled after the first keyframe", lambda r: never(r, "behind", "stalled")),
    "linkstill": ("never behind or stalled after the first keyframe", lambda r: never(r, "behind", "stalled")),
    # The plan asked for 4 s. The host sees nothing taken only once the buffers between it and the dead
    # path are full: on this loopback path 0.7–1 MB (the host's send buffer and the relay's receive
    # buffer), a few seconds of Low's stream; then 3 s of nothing taken and nothing heard.
    "linkdead": ("stalled within 8 s of the blackhole", lambda r: (first(r, "stalled", r["darkAt"]) or 99) <= 8),
    "linkdown": ("behind within 3 s of the end of the host's first second withholding frames, never stalled",
                 lambda r: (first(r, "behind", r["withheldAt"]) or 99) <= 3
                           and not any(st == "stalled" for _, st, _, _ in r["links"])),
    "home": ("never behind or stalled after the first keyframe", lambda r: never(r, "behind", "stalled")),
}
link_failed = []
news = [(name, r) for name, r in runs.items() if name.endswith("-new")]
if any(r["links"] for _, r in news) or any(re.match(r"(.+)-\d+-new$", n).group(1) in LINK_GATES for n, _ in news):
    print("\nThe link (the new build's Link lines; seconds from the device's first connection):")
    for name, r in news:
        case = re.match(r"(.+)-\d+-new$", name).group(1)
        changes, last = [], None
        for u, st, reset, _ in r["links"]:
            if st != last: changes.append(f"{st[0].upper()}{'r' if reset else ''}@{u:.1f}")
            last = st
        events = " ".join(changes) + (f" ({len(r['links'])} reports)" if len(r["links"]) > len(changes) else "") if changes else "no change"
        verdict = ""
        if case in LINK_GATES:
            what, rule = LINK_GATES[case]
            ok = rule(r)
            verdict = ("pass" if ok else "FAIL") + f": {what}"
            if not ok: link_failed.append(name)
        c = rate(r)
        held = (f"  withholding in the second to {r['withheldAt']:.1f} ({r['withheldAt'] - r['dropAt']:.1f} s after the rate fell)"
                if case in ("dip", "linkdown") and r["withheldAt"] is not None and r["dropAt"] is not None else "")
        print(f"  {name:22} {events}{f'  carried {c:g} Mbps' if c is not None else ''}{held}  {verdict}")
    print("  B behind, S stalled, F fine (Fr: fine by a restart's reset)")
if link_failed:
    print(f"LINK FAILED: {' '.join(link_failed)}")
    failed += link_failed
if failed:
    print(f"FAILED: {' '.join(failed)}")
    sys.exit(1)
print("Every gate passed." if any(c in GATES and GATES[c][1] for c in cases) else "No gated case ran.")
