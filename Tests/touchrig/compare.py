#!/usr/bin/env python3
"""H7 (docs/trackpad-gestures-plan.md §9.4): the touch rig's logs judged.

usage: compare.py BASE.log NEW.log [OFF.log]

BASE is the surfaces before the gestures, NEW this branch's with the device's switch on, OFF the same
with it off. A run's events are compared with their times left out; runs of pointer moves and of
scroll deltas are compared by their count and their last move or their sum, and a coast's steps
(between momentumBegan and momentumEnded, paced by the display) only as being there.
  - One- and two-finger strokes, and a third finger that joins a scroll late: NEW's events are BASE's.
  - Every other stroke of three to five fingers: after its third finger lands, nothing but its one
    gesture (and a scroll it had begun, closed at once without a coast), and the gesture expected.
  - OFF: NEW's events, less the gesture going out: nothing else at all.
Exits 1 on any failure."""
import re, sys

def load(path):
    runs, cur = {}, None
    for line in open(path, errors="replace"):
        line = line.rstrip("\n")
        if line.startswith("=== "):
            cur = line[4:]; runs[cur] = []; continue
        m = re.match(r"\s*-?\d+ (.*)$", line)
        if cur is not None and m: runs[cur].append(m.group(1))
    return runs

def normal(events):
    """The events a surface sent, times and touch lines gone; runs of moves by count and last
    position, live scroll deltas by count and sum, a coast's steps only as being there (the display
    paces them)."""
    out, coasting = [], False
    for e in events:
        if e.startswith("[touch]"): continue
        who, _, what = e.partition(" send ")
        who = who.strip()
        if not what:
            out.append(" ".join(e.split())); continue
        if what.startswith("scrollGesture.momentumBegan"): coasting = True
        if what.startswith("scrollGesture.momentumEnded"): coasting = False
        m = re.match(r"(pointer\.move|scroll)\(([-\d.]+),([-\d.]+)\)", what)
        if m:
            kind, x, y = m.group(1), float(m.group(2)), float(m.group(3))
            key = f"{who} {kind}" + (" (coast)" if coasting and kind == "scroll" else "")
            if out and isinstance(out[-1], list) and out[-1][0] == key:
                run = out[-1]; run[1] += 1
                if kind == "scroll": run[2] += x; run[3] += y
                else: run[2], run[3] = x, y
            else:
                out.append([key, 1, x, y])
            continue
        out.append(f"{who} {what}")
    shown = []
    for o in out:
        if isinstance(o, list):
            key, n, x, y = o
            shown.append(f"{key} ×{n} → ({x:.3f},{y:.3f})" if "(coast)" not in key else f"{key}")
        else:
            shown.append(o)
    return shown

def sends(events):
    return normal(events)

def after_third(events):
    """What the surface sent after the touch line that brought three fingers down."""
    for i, e in enumerate(events):
        m = re.search(r"^\[touch\].*→ (\d+) down", e)
        if m and int(m.group(1)) >= 3:
            return normal(events[i + 1:])
    return []

EXPECT = {   # scenario → the one gesture after the third finger (None: nothing)
    "3-finger swipe up, landing 16 ms apart": "swipeUp fingers 3",
    "3-finger swipe up, landing together": "swipeUp fingers 3",
    "3-finger swipe left, landing 16 ms apart": "swipeLeft fingers 3",
    "3-finger swipe right, landing 16 ms apart": "swipeRight fingers 3",
    "3-finger swipe down, landing 50 ms apart": "swipeDown fingers 3",
    "3-finger pinch in (to 0.45)": "pinch fingers 3",
    "3-finger spread (to 1.8)": "spread fingers 3",
    "3-finger rest 0.6 s, then swipe up": "swipeUp fingers 3",
    "3-finger tap": None,
    "3-finger swipe up, first finger moves 12 pt before the others land": "swipeUp fingers 3",
    "3 fingers move 60, one lifts, two move 120 more": "swipeUp fingers 3",
    "4-finger swipe up, landing 16 ms apart": "swipeUp fingers 4",
    "5-finger swipe up, landing 16 ms apart": None,
    "3-finger swipe up then cancelled mid-way": None,
}
UNCHANGED = ["1-finger tap", "1-finger drag right 120", "1-finger hold 0.6 s, then move 60 and lift",
             "2-finger scroll up 150 (flick)", "2-finger scroll down 90, slowly", "2-finger tap",
             "2 fingers scroll 60, a 3rd lands 133 ms after the first, all move 120 more"]

def main():
    if len(sys.argv) not in (3, 4):
        print(__doc__); sys.exit(2)
    base, new = load(sys.argv[1]), load(sys.argv[2])
    off = load(sys.argv[3]) if len(sys.argv) == 4 else None
    fails = checks = 0
    def check(ok, what):
        nonlocal fails, checks
        checks += 1
        if not ok: fails += 1
        print(("ok   " if ok else "FAIL ") + what)
    for surface in ("TRACKPAD", "OVERLAY"):
        for s in UNCHANGED:
            t = f"{surface} {s}"
            a, b = sends(base.get(t, [])), sends(new.get(t, []))
            # The overlay has no two-finger tap: nothing, before and now.
            empty = surface == "OVERLAY" and s == "2-finger tap"
            check(t in base and t in new and a == b and (len(a) > 0 or empty), f"{t}: the same events as before ({len(b)})")
            if a != b:
                for x, y in zip(a + ["-"] * (len(b) - len(a)), b + ["-"] * (len(a) - len(b))):
                    print(f"       before: {x}\n       now:    {y}")
        for s, want in EXPECT.items():
            t = f"{surface} {s}"
            after = after_third(new.get(t, []))
            gestures = [e for e in after if " gesture " in e]
            others = [e for e in after if " gesture " not in e]
            # A scroll the stroke had begun before its third finger is closed at arming, no coast.
            closed = [e for e in others if e.endswith("scrollGesture.ended")]
            stray = [e for e in others if not e.endswith("scrollGesture.ended")]
            got = gestures[0].split(" gesture ", 1)[1] if gestures else None
            ok = t in new and len(gestures) == (1 if want else 0) and got == want and not stray and len(closed) <= 1
            check(ok, f"{t}: {'one gesture, ' + want if want else 'no gesture'}; nothing else after the third finger"
                      + (f" (a scroll closed at arming)" if closed else ""))
            if not ok:
                for e in after: print(f"       {e}")
            if closed:
                check(not any("momentum" in e for e in after), f"{t}: the closed scroll does not coast")
            if off is not None:
                o = sends(off.get(t, []))
                n = [e.replace(" (switch off: not sent)", "") for e in sends(new.get(t, []))]
                o = [e.replace(" (switch off: not sent)", "") for e in o]
                check(o == n, f"{t}, the switch off: the same stroke, the gesture refused, nothing else")
    if off is not None:
        for surface in ("TRACKPAD", "OVERLAY"):
            for s in UNCHANGED:
                t = f"{surface} {s}"
                check(sends(off.get(t, [])) == sends(new.get(t, [])), f"{t}, the switch off: the same events")
    print(f"{checks} checks, {fails} failed")
    sys.exit(1 if fails else 0)

main()
