#!/usr/bin/env python3
"""Harness photos on the agents' own simulators: the iOS app's DEBUG layout harness (-SillLayout and
the mock's arguments, ContentView's contract) photographed for a list of cases, for one commit and,
if asked, a baseline commit, compared pixel by pixel. For agents and Noah: one shared pair of
simulators instead of a new one per agent, one build per commit, one simulator booted at a time.

    Scripts/agent-simulators.sh create            once: "Sill agents Duo" (iPhone Duo, iOS 27.1) and
                                                  "Sill agents iPad" (iPad Pro 13-inch (M5), iOS 27.0:
                                                  the 27.1 runtimes take only the Duo), left shut down
    Scripts/agent-simulators.sh list              them, their state and their size on disk
    Scripts/harness-photos.sh CASES [options]     photograph each case of the CASES file

Options of harness-photos.sh:
    --commit REV      the commit to photograph (default HEAD). Its committed tree is built, never the
                      working tree's changes: commit them first (a WIP commit will do)
    --baseline REV    also photograph REV with the same cases and compare each pair pixel by pixel
    --device duo|ipad the agents' simulator to use (default duo, iOS 27.1; larger fake screens are
                      drawn scaled down there). A case at one of the Duo's sizes, or with -SillHinge,
                      runs on the Duo only (Noah, 2026-10-27: every Duo photo on iOS 27.1)
    --repo DIR        the repository (default the one the current folder is in: an agent can run
                      this script from another checkout against its own branch)
    --out DIR         photos, differences and report.txt (default <repo>/.build/harness-photos/<run>)
    --wait S          seconds from a launch to its photo (default 4; a case can say its own)
    --tolerance N     a channel difference up to N counts as the same (default 0: exact)

A CASES file has one photo a line: a name, then the app's launch arguments, as a shell would split
them; `--wait=S` among them sets that photo's wait and `--pose=NAME` the Duo's pose (Tests/duorig's:
flat-portrait by default, so the inner display shows the app at 669x951 points; closed-upright and
closed-side photograph the cover), neither passed on; `#` starts a comment.
Scripts/harness-photos/example.cases has some.

    duo-landscape-drawer  -SillLayout 951x669 -SillHinge flat -SillDrawer 1

The rules it keeps itself (and refuses to run otherwise):
- It runs inside the heavy lock: through ~/Downloads/sill-handoff/tools/heavy.sh (SILL_HEAVY to name
  another) unless a process above it already holds that lock; without heavy.sh it says so and goes on.
- Only the agents' simulators: a name that does not start with "Sill agents " is refused, and so is
  one on another runtime than its own (the Duo iOS 27.1, the iPad iOS 27.0).
- Never beside another simulator: it refuses while any simulator but its own is booted, and shuts
  its own down when it ends, whatever happens.
- It never taps or types: launch arguments and `simctl io screenshot` only. Every case must have
  -SillLayout (the mock harness) and none of the arguments that dial a host or send input (-SillLive,
  -SillConnect, -SillInputScript, ...), so no photo ever reaches a Mac: Scripts/encoder-check/no-
  device.sh is not needed (no host, no encoder; a screenshot is a still picture, never a recording).
- Disk: it refuses to build, to boot a simulator for the first time, or to create one while `df -g /`
  shows less than 25 GB free.
- A photo of one colour is a photo of a display the app was not on (or had not drawn): the report says
  BLANK and the run fails, so an empty comparison never passes as "identical".

Where things are: ~/Library/Caches/SillAgents/ (SILL_AGENTS_CACHE): apps/<commit>-<Xcode build>/Sill.app,
the builds kept (the newest 8), DerivedData (one, shared by every build), src (the tree being built)
and bin/pixeldiff. The photos and report go to --out.
"""
import json
import os
import shlex
import shutil
import subprocess
import sys
import tempfile
import time

PREFIX = "Sill agents "
# The iOS 27.1 runtimes take only the iPhone Duo (simctl create answers "Incompatible device" for an
# iPad), so the iPad is on 27.0, as docs/iphone-duo-plan.md's 0.6.1 results were.
DEVICES = {
    "duo": ("Sill agents Duo", "com.apple.CoreSimulator.SimDeviceType.iPhone-Duo",
            "com.apple.CoreSimulator.SimRuntime.iOS-27-1"),
    "ipad": ("Sill agents iPad", "com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB",
             "com.apple.CoreSimulator.SimRuntime.iOS-27-0"),
}
DUO_SIZES = {"951x669", "669x951", "466x678", "678x466"}
# The Duo's poses (Tests/duorig) and the display each shows: the cover is "primary", the inner "primary-1".
DUO_POSES = {"closed-upright": "primary", "closed-side": "primary", "flat-portrait": "primary-1",
             "flat-landscape": "primary-1", "laptop": "primary-1", "book": "primary-1"}
DUO_DEFAULT_POSE = "flat-portrait"
BUNDLE = "me.saffer.sill"
FLOOR_GB = 25
FIRST_BOOT_GB = 3          # a simulator's first boot writes about 2.4 GB of its own
KEEP_BUILDS = 8
CACHE = os.path.expanduser(os.environ.get("SILL_AGENTS_CACHE", "~/Library/Caches/SillAgents"))
HEAVY = os.path.expanduser(os.environ.get("SILL_HEAVY", "~/Downloads/sill-handoff/tools/heavy.sh"))
HERE = os.path.dirname(os.path.abspath(__file__))
TOOL_ROOT = os.path.dirname(os.path.dirname(HERE))      # the repository this script is in (Tests/duorig)
# Arguments that make the app dial a host, pair, or send input: never in a harness photo.
NETWORK_ARGS = {
    "-SillLive", "-SillConnect", "-SillInputScript", "-SillInputTest", "-SillPairURL", "-SillPairCode",
    "-SillPairAddress", "-SillDialSaved", "-SillTapRow", "-SillHomeLink", "-SillHomeCode",
    "-SillOverlayCode", "-SillMoveTest", "-SillWiredTest", "-SillPathTest", "-SillServiceType",
    "-SillSettingsScript", "-SillMoveHomeTest", "-SillCableTest", "-SillHomeDoor",
}


def say(msg):
    print(f"harness-photos: {msg}", flush=True)


def die(msg, code=1):
    print(f"harness-photos: {msg}", file=sys.stderr, flush=True)
    sys.exit(code)


def run(cmd, check=True, **kw):
    r = subprocess.run(cmd, capture_output=True, text=True, **kw)
    if check and r.returncode != 0:
        die(f"{' '.join(shlex.quote(c) for c in cmd)} failed ({r.returncode}): {(r.stderr or r.stdout).strip()[:600]}")
    return r


def free_gb():
    out = run(["df", "-g", "/"]).stdout.split("\n")[1].split()
    return int(out[3])


def need_disk(what, extra=0):
    gb = free_gb()
    if gb < FLOOR_GB + extra:
        die(f"refused: {gb} GB free on /, under the {FLOOR_GB} GB floor{f' + {extra} GB' if extra else ''} "
            f"for {what}. Clean your own build products first (rm -rf {CACHE}/DerivedData is this tool's).")
    return gb


# ------------------------------------------------------------------------------------- the lock

def lock_held_above():
    """Whether a process above this one holds heavy.sh's lock (an agent ran us under heavy.sh)."""
    lock = os.path.join(os.path.dirname(HEAVY), ".heavy.lock.d")
    try:
        holder = int(open(os.path.join(lock, "pid")).read().strip())
    except (OSError, ValueError):
        return False
    pid = os.getpid()
    for _ in range(64):
        if pid == holder:
            return True
        r = subprocess.run(["ps", "-o", "ppid=", "-p", str(pid)], capture_output=True, text=True)
        try:
            pid = int(r.stdout.strip())
        except ValueError:
            return False
        if pid <= 1:
            return False
    return False


def in_heavy_lock(argv, label):
    """Re-runs this command under heavy.sh unless the lock is held above us already."""
    if os.environ.get("SILL_HARNESS_PHOTOS_LOCKED") == "1" or lock_held_above():
        return
    if not os.path.exists(HEAVY):
        say(f"no {HEAVY}: running without the heavy lock (one heavy job at a time is the rule on Noah's Mac)")
        return
    env = dict(os.environ, SILL_HARNESS_PHOTOS_LOCKED="1")
    os.execve("/bin/zsh", ["/bin/zsh", HEAVY, label, "--", sys.executable, *argv], env)


# ---------------------------------------------------------------------------------- simulators

def devices():
    data = json.loads(run(["xcrun", "simctl", "list", "devices", "-j"]).stdout)
    out = []
    for runtime, devs in data["devices"].items():
        for d in devs:
            out.append(dict(d, runtime=runtime))
    return out


def agent_simulator(key):
    name, _, runtime = DEVICES[key]
    if not name.startswith(PREFIX):
        die(f"refused: {name} does not start with \"{PREFIX}\"")
    found = [d for d in devices() if d["name"] == name]
    if not found:
        die(f"no simulator named \"{name}\": run Scripts/agent-simulators.sh create (once)")
    found = [d for d in found if d["runtime"] == runtime]
    if len(found) != 1:
        die(f"refused: \"{name}\" must be one simulator on {runtime.rsplit('.', 1)[-1]}; found {len(found)} there")
    if not found[0].get("isAvailable", True):
        die(f"\"{name}\" is not available: {found[0].get('availabilityError', '')}")
    return found[0]


def size_of(path):
    r = subprocess.run(["du", "-sk", path], capture_output=True, text=True)
    try:
        return int(r.stdout.split()[0]) * 1024
    except (ValueError, IndexError):
        return 0


def simulators(argv):
    cmd = argv[0] if argv else "list"
    if cmd == "create":
        made = []
        for key, (name, devtype, runtime) in DEVICES.items():
            if [d for d in devices() if d["name"] == name and d["runtime"] == runtime]:
                say(f"{name}: there already, kept")
                continue
            need_disk(f"creating {name}")
            udid = run(["xcrun", "simctl", "create", name, devtype, runtime]).stdout.strip()
            made.append(name)
            say(f"{name}: created, {udid}, {runtime.rsplit('.', 1)[-1]}, shut down (about 20 MB until its "
                "first boot, about 2.4 GB after)")
        return 0
    if cmd == "list":
        for key, (name, _, _) in DEVICES.items():
            found = [d for d in devices() if d["name"] == name]
            if not found:
                print(f"{name:20} not created (Scripts/agent-simulators.sh create)")
            for d in found:
                path = d.get("dataPath", "")
                size = size_of(os.path.dirname(path)) if path else 0
                print(f"{name:20} {d['udid']}  {d['state']:9} {d['runtime'].rsplit('.', 1)[-1]:10} "
                      f"{size / 1e9:.2f} GB")
        builds = os.path.join(CACHE, "apps")
        if os.path.isdir(builds):
            print(f"builds: {len(os.listdir(builds))} in {builds}, {size_of(builds) / 1e9:.2f} GB; "
                  f"DerivedData {size_of(os.path.join(CACHE, 'DerivedData')) / 1e9:.2f} GB")
        return 0
    die("usage: Scripts/agent-simulators.sh create|list", 2)


def others_booted(mine):
    return [d for d in devices() if d["state"] == "Booted" and d["udid"] != mine]


# ------------------------------------------------------------------------------------ the build

def xcode_build_version():
    out = run(["xcodebuild", "-version"]).stdout.split()
    return out[-1] if out else "unknown"


def resolve(repo, rev):
    return run(["git", "-C", repo, "rev-parse", "--verify", f"{rev}^{{commit}}"]).stdout.strip()


def build(repo, sha, xcode):
    """The app at a commit, from the cache or built from that commit's tree (never the working tree's)."""
    apps = os.path.join(CACHE, "apps")
    key = f"{sha[:12]}-{xcode}"
    app = os.path.join(apps, key, "Sill.app")
    if os.path.exists(os.path.join(apps, key, "done")):
        os.utime(os.path.join(apps, key))
        say(f"{sha[:12]}: built before ({app})")
        return app
    need_disk(f"building {sha[:12]}")
    src = os.path.join(CACHE, "src")
    os.makedirs(src, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=CACHE) as t:
        archive = subprocess.run(["git", "-C", repo, "archive", sha], capture_output=True)
        if archive.returncode != 0:
            die(f"git archive {sha[:12]} failed: {archive.stderr.decode()[:300]}")
        subprocess.run(["tar", "-x", "-C", t], input=archive.stdout, check=True)
        # Only files whose bytes changed get a new date, so the shared DerivedData builds incrementally.
        run(["rsync", "-a", "--checksum", "--delete", f"{t}/", f"{src}/"])
    log = os.path.join(CACHE, "logs", f"build-{key}.log")
    os.makedirs(os.path.dirname(log), exist_ok=True)
    say(f"{sha[:12]}: building the app for the simulator (Debug, arm64, Xcode {xcode}); log {log}")
    started = time.time()
    with open(log, "w") as f:
        r = subprocess.run(["xcodebuild", "-project", os.path.join(src, "iOSClient/Sill.xcodeproj"),
                            "-scheme", "Sill", "-configuration", "Debug",
                            "-destination", "generic/platform=iOS Simulator",
                            "-derivedDataPath", os.path.join(CACHE, "DerivedData"),
                            "ARCHS=arm64", "CODE_SIGN_IDENTITY=-", "build"], stdout=f, stderr=subprocess.STDOUT)
    if r.returncode != 0:
        die(f"{sha[:12]}: the build failed; the end of {log}:\n" +
            "".join(open(log, errors="replace").readlines()[-25:]))
    product = os.path.join(CACHE, "DerivedData/Build/Products/Debug-iphonesimulator/Sill.app")
    staging = os.path.join(apps, key + ".tmp")
    shutil.rmtree(staging, ignore_errors=True)
    os.makedirs(staging)
    run(["ditto", product, os.path.join(staging, "Sill.app")])
    open(os.path.join(staging, "done"), "w").write(f"{sha}\n{xcode}\n{time.ctime()}\n")
    shutil.rmtree(os.path.join(apps, key), ignore_errors=True)
    os.rename(staging, os.path.join(apps, key))
    say(f"{sha[:12]}: built in {time.time() - started:.0f} s")
    kept = sorted((os.path.getmtime(os.path.join(apps, k)), k) for k in os.listdir(apps) if not k.endswith(".tmp"))
    for _, old in kept[:-KEEP_BUILDS]:
        shutil.rmtree(os.path.join(apps, old), ignore_errors=True)
    return app


# ------------------------------------------------------------------------------------ the cases

def read_cases(path, default_wait, device):
    cases = []
    for n, line in enumerate(open(path), 1):
        words = shlex.split(line, comments=True)
        if not words:
            continue
        name, args, wait, pose = words[0], [], default_wait, None
        for w in words[1:]:
            if w.startswith("--wait="):
                wait = float(w.split("=", 1)[1])
            elif w.startswith("--pose="):
                pose = w.split("=", 1)[1]
                if pose not in DUO_POSES:
                    die(f"{path}:{n}: {name}: no pose {pose!r} (one of {', '.join(DUO_POSES)})")
                if device != "duo":
                    die(f"{path}:{n}: {name}: --pose is the Duo's")
            else:
                args.append(w)
        if not all(c.isalnum() or c in "-_." for c in name):
            die(f"{path}:{n}: a case's name is letters, digits, - _ and . only: {name!r}")
        if "-SillLayout" not in args:
            die(f"{path}:{n}: {name}: refused: no -SillLayout, so the normal app would start, browse and "
                "could dial a Mac. Every harness photo has -SillLayout WxH")
        bad = [a for a in args if a in NETWORK_ARGS]
        if bad:
            die(f"{path}:{n}: {name}: refused: {' '.join(bad)} would dial a host, pair or send input; a "
                "harness photo never does")
        layout = args[args.index("-SillLayout") + 1].lower() if args.index("-SillLayout") + 1 < len(args) else ""
        if device != "duo" and (layout in DUO_SIZES or "-SillHinge" in args):
            die(f"{path}:{n}: {name}: refused on the iPad (iOS 27.0): a Duo size or -SillHinge is photographed "
                "on the Duo, iOS 27.1, only (Noah, 2026-10-27): --device duo")
        cases.append((name, args, wait, pose or (DUO_DEFAULT_POSE if device == "duo" else None)))
    if not cases:
        die(f"{path}: no cases")
    names = [c[0] for c in cases]
    if len(set(names)) != len(names):
        die(f"{path}: two cases share a name")
    return cases


# ---------------------------------------------------------------------------------- the photos

def set_pose(udid, pose):
    """The Duo folded or opened with Tests/duorig (the tool's own copy), which waits for it to settle."""
    rig = os.path.join(TOOL_ROOT, "Tests/duorig/run.sh")
    if not os.path.exists(rig):
        die(f"no {rig}: the Duo's poses need Tests/duorig")
    run([rig, udid, "pose", pose], timeout=120)


def photograph(udid, app, cases, folder, blank):
    os.makedirs(folder, exist_ok=True)
    run(["xcrun", "simctl", "uninstall", udid, BUNDLE], check=False)     # fresh data for each commit
    run(["xcrun", "simctl", "install", udid, app])
    exe = pixeldiff()
    current = None
    for name, args, wait, pose in cases:
        run(["xcrun", "simctl", "launch", "--terminate-running-process", udid, BUNDLE, *args])
        # The app is in front before the Duo folds: closing over the Home Screen puts it to sleep.
        if pose and pose != current:
            set_pose(udid, pose)
            current = pose
        time.sleep(wait)
        path = os.path.join(folder, f"{name}.png")
        display = ["--display=" + DUO_POSES[pose]] if pose else []
        run(["xcrun", "simctl", "io", udid, "screenshot", "--type=png", *display, path])
        if subprocess.run([exe, "--uniform", path], capture_output=True).returncode == 0:
            blank.append(path)
            say(f"  {name}: {path}: BLANK (one colour: the app was not on that display, or not drawn yet)")
        else:
            say(f"  {name}: {path}" + (f" ({pose})" if pose else ""))
    run(["xcrun", "simctl", "terminate", udid, BUNDLE], check=False)


def pixeldiff():
    src = os.path.join(HERE, "pixeldiff.swift")
    digest = run(["shasum", "-a", "256", src]).stdout.split()[0][:16]
    exe = os.path.join(CACHE, "bin", f"pixeldiff-{digest}")
    if not os.path.exists(exe):
        os.makedirs(os.path.dirname(exe), exist_ok=True)
        run(["xcrun", "swiftc", "-O", src, "-o", exe])
        for old in os.listdir(os.path.dirname(exe)):         # the copies of older sources
            if old.startswith("pixeldiff-") and old != os.path.basename(exe):
                os.remove(os.path.join(os.path.dirname(exe), old))
    return exe


def compare(cases, base_dir, new_dir, out, tolerance):
    exe = pixeldiff()
    lines, same = [], 0
    for name, _, _, _ in cases:
        a, b = os.path.join(base_dir, f"{name}.png"), os.path.join(new_dir, f"{name}.png")
        diff = os.path.join(out, "differences", f"{name}.png")
        os.makedirs(os.path.dirname(diff), exist_ok=True)
        r = subprocess.run([exe, a, b, diff, "--tolerance", str(tolerance)], capture_output=True, text=True)
        try:
            d = json.loads(r.stdout)
        except ValueError:
            lines.append(f"{name}: could not compare: {r.stderr.strip()}")
            continue
        if not d.get("sameSize"):
            lines.append(f"{name}: DIFFERENT SIZE {d['base']['width']}x{d['base']['height']} against "
                         f"{d['new']['width']}x{d['new']['height']}")
        elif d["differingPixels"] == 0:
            same += 1
            lines.append(f"{name}: identical ({d['totalPixels']} pixels)")
        else:
            box = d["box"]
            lines.append(f"{name}: {d['differingPixels']} of {d['totalPixels']} pixels differ "
                         f"({100 * d['differingPixels'] / d['totalPixels']:.3f} %), the largest channel by "
                         f"{d['maxChannelDelta']} (mean {d['meanChannelDelta']:.1f}), within "
                         f"{box['width']}x{box['height']} at {box['x']},{box['y']}; {diff}")
    return lines, same


def photos(argv):
    opts = {"--commit": "HEAD", "--baseline": None, "--device": "duo", "--repo": None, "--out": None,
            "--wait": "4", "--tolerance": "0"}
    cases_path, rest = None, list(argv)
    while rest:
        a = rest.pop(0)
        if a in ("-h", "--help"):
            print(__doc__)
            return 0
        if "=" in a and a.split("=", 1)[0] in opts:
            k, v = a.split("=", 1)
            opts[k] = v
        elif a in opts:
            if not rest:
                die(f"{a} needs a value", 2)
            opts[a] = rest.pop(0)
        elif a.startswith("-"):
            die(f"unknown option {a} (--help)", 2)
        elif cases_path is None:
            cases_path = a
        else:
            die("one CASES file", 2)
    if cases_path is None:
        die("usage: Scripts/harness-photos.sh CASES [--commit REV] [--baseline REV] [--device duo|ipad] "
            "[--repo DIR] [--out DIR] [--wait S] [--tolerance N]", 2)
    if opts["--device"] not in DEVICES:
        die(f"--device is one of {', '.join(DEVICES)}", 2)
    cases_path = os.path.abspath(cases_path)
    repo = opts["--repo"] or run(["git", "rev-parse", "--show-toplevel"]).stdout.strip()
    repo = os.path.abspath(repo)
    cases = read_cases(cases_path, float(opts["--wait"]), opts["--device"])
    sha = resolve(repo, opts["--commit"])
    base = resolve(repo, opts["--baseline"]) if opts["--baseline"] else None
    sim = agent_simulator(opts["--device"])
    say("no-device.sh is not needed here: every case runs the DEBUG harness's mock (-SillLayout, no "
        "-SillLive and nothing that dials or sends input), so no photo reaches a Mac or its encoder, and "
        "simctl io screenshot takes a still picture, never a recording")
    # Everything from here waits for, and holds, the heavy lock.
    in_heavy_lock([os.path.abspath(__file__), *sys.argv[1:]], f"harness-photos {sha[:7]}")
    status = run(["git", "-C", repo, "status", "--porcelain", "--untracked-files=no"]).stdout
    if status and opts["--commit"] == "HEAD":
        say(f"note: the working tree has changes that are not committed; the photos are of {sha[:12]} as committed")
    xcode = xcode_build_version()
    apps = [(sha, build(repo, sha, xcode))] + ([(base, build(repo, base, xcode))] if base else [])
    udid = sim["udid"]
    sim = agent_simulator(opts["--device"])
    others = others_booted(udid)
    if others:
        die("refused: another simulator is booted: " + ", ".join(f"{d['name']} ({d['udid']})" for d in others)
            + ". One at a time: try again once it is shut down")
    if sim["state"] != "Booted" and size_of(os.path.dirname(sim.get("dataPath", "/nonexistent"))) < 200e6:
        need_disk(f"the first boot of {sim['name']}", FIRST_BOOT_GB)
    run_name = sha[:12] + (f"-vs-{base[:12]}" if base else "")
    out = os.path.abspath(opts["--out"] or os.path.join(repo, ".build/harness-photos", run_name))
    os.makedirs(out, exist_ok=True)
    started = time.time()
    blank = []
    try:
        if sim["state"] != "Booted":
            say(f"booting {sim['name']} ({udid})")
            run(["xcrun", "simctl", "boot", udid])
        run(["xcrun", "simctl", "bootstatus", udid, "-b"], timeout=600)
        if others_booted(udid):
            die("refused: another simulator booted meanwhile; stopping")
        run(["xcrun", "simctl", "status_bar", udid, "override", "--time", "9:41", "--batteryState",
             "charged", "--batteryLevel", "100", "--wifiBars", "3"], check=False)
        for commit, app in apps:
            say(f"photographing {commit[:12]} on {sim['name']}")
            photograph(udid, app, cases, os.path.join(out, commit[:12]), blank)
    finally:
        subprocess.run(["xcrun", "simctl", "shutdown", udid], capture_output=True)
        say(f"{sim['name']} shut down")
    report = [f"harness photos of {sha} on {sim['name']} ({udid}, {sim['runtime'].rsplit('.', 1)[-1]}), Xcode {xcode}, "
              f"{len(cases)} cases from {cases_path}, {time.time() - started:.0f} s with the simulator"]
    if base:
        lines, same = compare(cases, os.path.join(out, base[:12]), os.path.join(out, sha[:12]), out,
                              int(opts["--tolerance"]))
        report += [f"against {base}: {same} of {len(cases)} identical" +
                   (f" (a channel difference up to {opts['--tolerance']} counted as the same)" if int(opts["--tolerance"]) else "")]
        report += lines
    if blank:
        report += [f"BLANK: {len(blank)} photo(s) of one colour, so they prove nothing: " + ", ".join(blank)]
    text = "\n".join(report) + "\n"
    open(os.path.join(out, "report.txt"), "w").write(text)
    print(text, end="")
    say(f"photos and report in {out}")
    return 1 if blank else 0


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "simulators":
        sys.exit(simulators(sys.argv[2:]))
    sys.exit(photos(sys.argv[1:]))
