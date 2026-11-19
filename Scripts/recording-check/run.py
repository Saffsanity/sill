#!/usr/bin/env python3
"""The recording rig's cases and gates (docs/recording-plan.md, gate G3; run.sh builds and calls this).

usage: run.py ROOT OUT [case ...]

Each case starts a synthetic SillHost on 127.0.0.1 alone (SILL_TEST_LOOPBACK, SILL_TEST_SOFTWARE_ENCODER,
SILL_TEST_NO_ROUTER, SILL_TEST_NO_SCREEN, and the case's own TEST ONLY variables), runs recordcheck against it (the
device: the count, the asks, the light, the stop, StreamRecorder writing into OUT/<case>), stops the host, reads every
movie with moviecheck, and checks the case's gates. One line per gate (ok / FAIL); the exit status is the number of
failures. Everything stays in OUT: the hosts' and devices' logs, summary.json, the movies, moviecheck's reports."""
import json, os, re, signal, subprocess, sys, threading, time

ROOT, OUT = sys.argv[1], sys.argv[2]
ONLY = sys.argv[3:]
HOST = os.path.join(ROOT, ".build/release/SillHost")
RIG = os.path.join(ROOT, ".build/recording-check")
ENV = {"SILL_TEST_LOOPBACK": "1", "SILL_TEST_SOFTWARE_ENCODER": "1", "SILL_TEST_NO_ROUTER": "1", "SILL_TEST_NO_SCREEN": "1"}
DISPLAYS = "Built-in Retina Display:1512x982@2:120:0,0;DELL U2723QE:2560x1440@1:60:1512,0"
failures = 0

# name: (host env, host args, recordcheck args, seconds, what it shows). Start at 2 s: the ask at 4 s, the light at 5 s.
CASES = {
    "plain": ({}, ["--audio"], ["--sound", "--start", "2", "--stop", "25"], 30,
              "20 s with the test tone: two tracks; the length the stop's; the keyframes the only sync samples; every click within 5 ms"),
    "still": ({"SILL_TEST_STILL_AFTER": "3"}, [], ["--start", "4", "--stop", "20"], 25,
              "a window still before the start: the movie lasts to the stop on its last picture"),
    "still-sound": ({"SILL_TEST_STILL_AFTER": "3"}, ["--audio"], ["--sound", "--start", "4", "--stop", "20"], 25,
                    "the same with the tone: the sound runs on while the picture is still, neither input stalls the other"),
    "parts": ({"SILL_TEST_DISPLAYS": DISPLAYS}, [], ["--start", "2", "--stop", "16", "--next-display-at", "9"], 20,
              "the Desktop steps to a display of another size at 9 s: two movies, the second (2), each from a keyframe"),
    "oldmac-still": ({"SILL_TEST_STILL_AFTER": "0.01", "SILL_TEST_KEYFRAME_IGNORE": "1000"}, [], ["--start", "3", "--stop", "15"], 20,
                     "a Mac that skips the asks, its picture still since its keyframe: the movie starts at the light from that keyframe"),
    "oldmac-gaveup": ({"SILL_TEST_STILL_AFTER": "1", "SILL_TEST_KEYFRAME_IGNORE": "1000"}, [], ["--start", "3", "--stop", "25"], 25,
                      "the same with frames since its keyframe: Starting…, three asks at the recovery's wait, the give-up at 10 s, no movie"),
    "oldmac-moving": ({"SILL_TEST_KEYFRAME_IGNORE": "1000"}, [], ["--start", "2", "--stop", "18"], 22,
                      "a Mac that skips the asks, its picture moving: the movie starts at its next keyframe"),
    "kill": ({}, ["--audio"], ["--sound", "--start", "2", "--stop", "30", "--kill-at", "14"], 20,
             "the rig killed 9 s into the recording: the movie still opens (fragments every 4 s)"),
    "full": ({"SILL_TEST_PATTERN": "noise"}, [], ["--start", "2", "--stop", "40", "--free-start", "1030000000", "--free-scale", "3"], 45,
             "30 MB above the stop's floor: low at once, then the recording stops itself, the movie whole"),
    "lock": ({"SILL_TEST_LOCKED_FILE": "@lock"}, [], ["--start", "2", "--stop", "22"], 26,
             "the Mac switched to another user at 9 s and back at 14 s: the placeholder in a part of its own"),
}


def expect(ok, what):
    global failures
    print(("ok   " if ok else "FAIL ") + what, flush=True)
    if not ok:
        failures += 1


class Host:
    """A synthetic test host on 127.0.0.1 alone: its lines, its port."""
    def __init__(self, label, env, args, out):
        e = dict(os.environ); e.update(ENV); e.update(env)
        self.log = open(os.path.join(out, label + "-host.log"), "w")
        self.p = subprocess.Popen(["nice", "-n", "10", HOST, "--synthetic", *args], stdout=self.log, stderr=subprocess.STDOUT,
                                  env=e, start_new_session=True)
        self.port = None
        for _ in range(150):
            time.sleep(0.1)
            r = subprocess.run(["lsof", "-nP", "-a", "-p", str(self.p.pid), "-iTCP", "-sTCP:LISTEN"], capture_output=True, text=True)
            if re.findall(r"(\*|\[::\]|0\.0\.0\.0):(\d+) \(LISTEN\)", r.stdout):
                self.stop(); raise SystemExit(f"{label}: a listener not on loopback")
            ports = re.findall(r"127\.0\.0\.1:(\d+) \(LISTEN\)", r.stdout)
            if ports:
                self.port = ports[0]; break
        if self.port is None:
            self.stop(); raise SystemExit(f"{label}: no listening port")

    def stop(self):
        if self.p.poll() is None:
            os.killpg(self.p.pid, signal.SIGTERM)
            try: self.p.wait(5)
            except subprocess.TimeoutExpired: os.killpg(self.p.pid, signal.SIGKILL); self.p.wait()
        self.log.close()


def movie_report(path, mac_start):
    args = [os.path.join(RIG, "moviecheck"), path] + (["--mac-start", repr(mac_start)] if mac_start is not None else [])
    r = subprocess.run(args, capture_output=True, text=True, timeout=120)
    try:
        return json.loads(r.stdout.strip().splitlines()[-1])
    except (ValueError, IndexError):
        return {"error": (r.stdout + r.stderr)[-300:]}


def run_case(name):
    env, host_args, rec_args, seconds, what = CASES[name]
    out = os.path.join(OUT, name)
    os.makedirs(out, exist_ok=True)
    env = dict(env)
    lock_file = None
    if env.get("SILL_TEST_LOCKED_FILE") == "@lock":
        lock_file = os.path.join(out, "locked"); open(lock_file, "w").write("0\n")
        env["SILL_TEST_LOCKED_FILE"] = lock_file
    print(f"== {name}: {what}", flush=True)
    host = Host(name, env, host_args, out)
    t0 = time.time()
    timers = []
    if lock_file:
        for at, v in ((9, "2"), (14, "0")):
            t = threading.Timer(at, lambda v=v: open(lock_file, "w").write(v + "\n")); t.start(); timers.append(t)
    with open(os.path.join(out, "recordcheck.log"), "w") as log:
        r = subprocess.run([os.path.join(RIG, "recordcheck"), host.port, out, str(seconds), *rec_args], stdout=log, stderr=subprocess.STDOUT,
                           timeout=seconds + 30)
    for t in timers: t.cancel()
    host.stop()
    summary_path = os.path.join(out, "summary.json")
    summary = json.load(open(summary_path)) if os.path.exists(summary_path) else None
    movies = sorted(p for p in os.listdir(out) if p.endswith(".mov"))
    starts = (summary or {}).get("partStarts", [])
    by_path = {m: i for i, m in enumerate((summary or {}).get("movies", []))}
    reports = []
    for m in movies:
        path = os.path.join(out, m)
        i = by_path.get(path)
        reports.append(movie_report(path, starts[i] if i is not None and i < len(starts) else None))
    json.dump({"summary": summary, "movies": reports, "exit": r.returncode, "seconds": time.time() - t0}, open(os.path.join(out, "report.json"), "w"), indent=1)
    return summary, reports, r.returncode, movies


def video_ok(rep):
    v = rep.get("video") or {}
    samples = v.get("samples") or []
    times = [s[0] for s in samples]
    return v.get("codec") == "hvc1" and len(samples) > 0 and all(b > a for a, b in zip(times, times[1:])) and samples[0][1]


def light_to_stop(summary):
    """The recording's length by the rig's clock: from the light (or the start) to the stop."""
    prog = [p for p in summary.get("progress", []) if "seconds" in p]
    return prog[-1]["seconds"] if prog else None


def gates(name, summary, reports, code, movies):
    if name == "kill":
        # Killed mid-recording: no summary, only what its movie's fragments kept.
        print(f"     kill: movies {movies}, reports {[{k: r.get(k) for k in ('movie', 'duration', 'error')} for r in reports]}", flush=True)
        expect(code in (-9, 137), f"kill: the rig was killed ({code})")
        d = reports[0].get("duration") if reports else None
        expect(len(movies) == 1 and d is not None and d >= 3.5, f"kill: the movie opens with what its fragments kept ({d} s)")
        expect(len(reports) == 1 and video_ok(reports[0]), "kill: its picture is hvc1, from a sync sample, its times increasing")
        return
    expect(summary is not None, f"{name}: recordcheck wrote its summary (exit {code})")
    if summary is None:
        return
    lengths = [rep.get("duration") for rep in reports]
    print(f"     {name}: start {summary['start']}, ending {summary['ending']}, asks at {[round(a, 2) for a in summary['asks']]}, "
          f"movies {[os.path.basename(m) for m in movies]}, durations {lengths}, failure {summary.get('failure')}", flush=True)
    for rep in reports:
        v = rep.get("video") or {}
        s = v.get("samples") or []
        sync = sum(1 for x in s if x[1])
        a = rep.get("audio") or {}
        print(f"     {rep.get('movie')}: {rep.get('duration')} s, video {v.get('codec')} {len(s)} samples ({sync} sync) from {s[0][0] if s else None}, "
              f"edits {v.get('edits')}, audio {a.get('codec')} {a.get('duration')} s, clicks {len(a.get('clicks') or [])}, "
              f"offsets ms {[round(x, 1) for x in (a.get('clickOffsetsMs') or [])][:30]}", flush=True)
    if name in ("plain", "still", "still-sound", "parts", "oldmac-still", "oldmac-moving", "lock"):
        expect(summary["ending"] == "stop", f"{name}: ended by Stop ({summary['ending']})")
        expect(summary.get("failure") is None and len(reports) >= 1 and all("error" not in r for r in reports), f"{name}: every movie opens")
        expect(all(video_ok(r) for r in reports), f"{name}: each movie's picture is hvc1, from a sync sample, its times increasing")
    if name in ("plain", "still", "still-sound", "oldmac-still"):
        want = light_to_stop(summary)
        got = reports[0].get("duration") if reports else None
        expect(want is not None and got is not None and abs(got - want) <= 1.2,
               f"{name}: the movie lasts the recording's time ({got} s against the light's last {want} s, a second apart at most)")
    if name == "plain":
        rep = reports[0] if reports else {}
        s = (rep.get("video") or {}).get("samples") or []
        expect(summary["start"] == "sinceAsk", f"plain: the movie starts at the light from the pre-roll ({summary['start']})")
        expect(sum(1 for x in s if x[1]) < len(s) / 4, "plain: deltas are not sync samples (fewer than a quarter are)")
        a = rep.get("audio") or {}
        offs = a.get("clickOffsetsMs") or []
        expect(a.get("codec") == "aac " and len(offs) >= 15, f"plain: an AAC track with the tone's clicks ({len(offs)})")
        expect(offs and max(abs(x) for x in offs) <= 5, f"plain: every click within 5 ms of its second (worst {max([abs(x) for x in offs] or [0]):.1f} ms)")
    if name == "still":
        s = ((reports[0] if reports else {}).get("video") or {}).get("samples") or []
        expect(0 < len(s) <= 5, f"still: a picture or a few, nothing streams ({len(s)} samples)")
    if name == "still-sound":
        a = (reports[0] if reports else {}).get("audio") or {}
        d = (reports[0] if reports else {}).get("duration") or 0
        expect(a.get("codec") == "aac " and a.get("duration") and abs(a["duration"] - d) <= 1.0,
               f"still-sound: the sound runs the movie's length ({a.get('duration')} of {d} s)")
        offs = a.get("clickOffsetsMs") or []
        expect(len(offs) >= 10 and max(abs(x) for x in offs) <= 5, f"still-sound: the clicks in place ({len(offs)}, worst {max([abs(x) for x in offs] or [0]):.1f} ms)")
    if name == "parts":
        expect(len(movies) == 2 and movies[1].endswith(" (2).mov"), f"parts: two movies, the second (2): {movies}")
    if name == "oldmac-still":
        expect(summary["start"] == "lastKeyframe", f"oldmac-still: from the last keyframe ({summary['start']})")
    if name == "oldmac-gaveup":
        expect(summary["start"] == "nextKeyframe" and summary["ending"] == "gaveUp" and not movies,
               f"oldmac-gaveup: Starting…, then gave up, no movie ({summary['start']}, {summary['ending']}, {movies})")
        asks = summary["asks"]
        expect(len(asks) == 3 and all(b - a >= 3.9 for a, b in zip(asks, asks[1:])),
               f"oldmac-gaveup: three asks at the recovery's wait: {asks}")
    if name == "oldmac-moving":
        # The Mac's own keyframe every 4 s may fall in the second before the light (the pre-roll), or come after it.
        light = 2 + 3
        waited = (summary.get("startedAt") or 99) - light
        expect(summary["start"] in ("nextKeyframe", "sinceAsk") and waited <= 4.6,
               f"oldmac-moving: from the Mac's own next keyframe, within its 4 s ({summary['start']}, 0:00 {waited:.2f} s after the light)")
    if name == "full":
        expect(summary["ending"] == "space", f"full: the recording stopped itself for space ({summary['ending']})")
        lows = [p for p in summary.get("progress", []) if str(p.get("space", "")).startswith("low")]
        expect(len(lows) > 0, f"full: space low before the stop ({len(lows)} seconds low)")
        expect(len(reports) == 1 and "error" not in reports[0] and video_ok(reports[0]), "full: the movie opens")
    if name == "lock":
        expect(len(movies) >= 2, f"lock: the placeholder in a part of its own: {movies}")


os.makedirs(OUT, exist_ok=True)
names = ONLY or list(CASES)
for name in names:
    if name not in CASES:
        print(f"no case {name}: {', '.join(CASES)}"); sys.exit(2)
    try:
        gates(name, *run_case(name))
    except Exception as e:     # a case that could not run fails, the others go on
        expect(False, f"{name}: could not run: {e}")
print(f"recording rig: {failures} gate(s) failed")
sys.exit(failures)
