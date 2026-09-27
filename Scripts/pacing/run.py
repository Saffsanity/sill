#!/usr/bin/env python3
"""One pacing-harness run: a host (base or new, from build.sh) → bottleneck.py → device.py, for S
seconds. run.sh runs the cases; this is one of them.
usage: run.py NAME BUILD SECONDS [host args...] -- [relay args...] -- [device args...]
BUILD is base or new (build.sh's), or any other package made the same way under .build/pacing.
Writes NAME.host.log (the host's lines with Sill.log's timestamps), NAME.host.out (its stdout),
NAME.relay.txt and NAME.device.txt into $PACING_RUNS (default .build/pacing/runs). DOOR=Home waits
for the host's home door (give the host --home and the device --plain) instead of its remote door;
every door and the relay listen on 127.0.0.1 only. Every process is started in its own session and
killed by PID at the end: none is left running."""
import os, queue, re, signal, subprocess, sys, threading, time

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.environ.get("PACING_OUT") or os.path.abspath(os.path.join(HERE, "..", "..", ".build", "pacing"))
RUNS = os.environ.get("PACING_RUNS") or os.path.join(OUT, "runs")
os.makedirs(RUNS, exist_ok=True)
name, which, seconds = sys.argv[1], sys.argv[2], float(sys.argv[3])
parts = [[]]
for a in sys.argv[4:]:
    if a == "--": parts.append([])
    else: parts[-1].append(a)
while len(parts) < 3: parts.append([])
host_args, relay_args, dev_args = parts
binary = os.path.join(OUT, which, ".build", "release", "Harness")
if not os.path.exists(binary): sys.exit(f"run.py: no {binary}: run Scripts/pacing/build.sh first (it makes base and new)")
env = dict(os.environ, PACING_OUT=OUT)
path = lambda suffix: os.path.join(RUNS, f"{name}.{suffix}")
if os.path.exists(path("host.log")): os.remove(path("host.log"))
procs = []

def start(cmd, **kw):
    p = subprocess.Popen(cmd, start_new_session=True, env=env, **kw)
    procs.append(p)
    return p

def stop_all():
    for p in reversed(procs):
        if p.poll() is None:
            p.terminate()
            try: p.wait(timeout=3)
            except subprocess.TimeoutExpired:
                p.kill(); p.wait()

def follow(p, sink):
    """Copies p's output to sink as it comes, and hands each line to the returned queue."""
    lines = queue.Queue()
    def drain():
        for line in p.stdout:
            sink.write(line); sink.flush(); lines.put(line)
    threading.Thread(target=drain, daemon=True).start()
    return lines

def wait_for(lines, pattern, what, limit=15):
    deadline = time.time() + limit
    while time.time() < deadline:
        try: line = lines.get(timeout=max(0.01, deadline - time.time()))
        except queue.Empty: break
        m = re.search(pattern, line)
        if m: return int(m.group(1))
    stop_all()
    sys.exit(f"run.py {name}: no {what}")

# A TERM (run.sh stopped) or an interrupt ends the run through `finally`, so the host, the relay and
# the device, each in its own session, are killed too rather than left running.
signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))
try:
    host_out = open(path("host.out"), "w")
    host = start([binary, "--seconds", str(seconds + 6), "--log", path("host.log")] + host_args,
                 stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    door = os.environ.get("DOOR", "Remote")
    port = wait_for(follow(host, host_out), door + r" door listening on port (\d+)", f"{door.lower()} door")
    relay_out = open(path("relay.txt"), "w")
    relay = start([sys.executable, os.path.join(HERE, "bottleneck.py"), "--listen", "0", "--to", f"127.0.0.1:{port}"] + relay_args,
                  stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    rport = wait_for(follow(relay, relay_out), r"listening on 127\.0\.0\.1:(\d+)", "relay")
    with open(path("device.txt"), "w") as dev_out:
        dev = start([sys.executable, os.path.join(HERE, "device.py"), str(rport), "--seconds", str(seconds)] + dev_args,
                    stdout=dev_out, stderr=subprocess.STDOUT, text=True)
        dev.wait(timeout=seconds + 60)
    time.sleep(1.5)
finally:
    stop_all()
print(f"run {name}: {RUNS}")
