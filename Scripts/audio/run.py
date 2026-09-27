#!/usr/bin/env python3
"""One run of the encoder-free sound harness: its host (build.sh's) → a relay or none → audiocheck, all
on 127.0.0.1, for SECONDS. run.sh runs the gates; this is one of them.
usage: run.py NAME SECONDS [host args...] -- [relay args...] -- [device args...]
Env: DOOR=Home (default) or Remote, the host's door audiocheck dials (Remote adds --tls unless the host
was given --plain-remote); RELAY=none (default), bottleneck (Scripts/pacing/bottleneck.py) or sillrelay
(Scripts/sillrelay.py) on the path; HOSTENV="K=V;K=V" for the host's environment (SILL_TEST_AUDIO_*);
AUDIO_RUNS, where NAME.host.txt, NAME.relay.txt and NAME.device.txt go (default .build/audio/runs).
Every process is started in its own session and killed by PID at the end: none is left running. The
host's CPU (ps, once a second) goes to NAME.cpu.txt."""
import os, queue, re, signal, subprocess, sys, threading, time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, ".build", "audio")
RUNS = os.environ.get("AUDIO_RUNS") or os.path.join(OUT, "runs")
os.makedirs(RUNS, exist_ok=True)
name, seconds = sys.argv[1], float(sys.argv[2])
parts = [[]]
for a in sys.argv[3:]:
    if a == "--": parts.append([])
    else: parts[-1].append(a)
while len(parts) < 3: parts.append([])
host_args, relay_args, dev_args = parts
binary = os.path.join(OUT, "host", ".build", "release", "Harness")
checker = os.path.join(OUT, "audiocheck")
for b in (binary, checker):
    if not os.path.exists(b): sys.exit(f"run.py: no {b}: run Scripts/audio/build.sh first")
env = dict(os.environ)
for kv in os.environ.get("HOSTENV", "").split(";"):
    if "=" in kv:
        k, v = kv.split("=", 1); env[k] = v
path = lambda suffix: os.path.join(RUNS, f"{name}.{suffix}")
procs = []

def start(cmd, **kw):
    p = subprocess.Popen(cmd, start_new_session=True, **kw)
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
    lines = queue.Queue()
    def drain():
        for line in p.stdout:
            sink.write(line); sink.flush(); lines.put(line)
    threading.Thread(target=drain, daemon=True).start()
    return lines

def wait_for(lines, pattern, what, limit=20):
    deadline = time.time() + limit
    while time.time() < deadline:
        try: line = lines.get(timeout=max(0.01, deadline - time.time()))
        except queue.Empty: break
        m = re.search(pattern, line)
        if m: return int(m.group(1))
    stop_all()
    sys.exit(f"run.py {name}: no {what}")

signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))
try:
    host_out = open(path("host.txt"), "w")
    host = start([binary, "--seconds", str(seconds + 6)] + host_args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, env=env)
    door = os.environ.get("DOOR", "Home")
    lines = follow(host, host_out)
    port = wait_for(lines, door + r" door listening on port (\d+)", f"{door.lower()} door")
    relay = os.environ.get("RELAY", "none")
    if relay != "none":
        relay_py = {"bottleneck": os.path.join(ROOT, "Scripts", "pacing", "bottleneck.py"),
                    "sillrelay": os.path.join(ROOT, "Scripts", "sillrelay.py")}[relay]
        relay_out = open(path("relay.txt"), "w")
        r = start([sys.executable, relay_py, "--listen", "0", "--to", f"127.0.0.1:{port}"] + relay_args,
                  stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        port = wait_for(follow(r, relay_out), r"listening on 127\.0\.0\.1:(\d+)", "relay")
    tls = ["--tls"] if door == "Remote" and "--plain-remote" not in host_args else []
    cpu = open(path("cpu.txt"), "w")
    # DEVICES=N: N audiochecks at once (the second and later a second apart), NAME.device.txt, NAME.device2.txt…
    devices = []
    for i in range(int(os.environ.get("DEVICES", "1"))):
        if i: time.sleep(1)
        dev_out = open(path("device.txt" if i == 0 else f"device{i + 1}.txt"), "w")
        devices.append(start([checker, "127.0.0.1", str(port), str(seconds - i)] + tls + dev_args + ["--label", f"audiocheck{'' if i == 0 else i + 1}"],
                             stdout=dev_out, stderr=subprocess.STDOUT))
    end = time.time() + seconds + 10
    while any(d.poll() is None for d in devices) and time.time() < end:
        r = subprocess.run(["/bin/ps", "-o", "%cpu=", "-p", str(host.pid)], capture_output=True, text=True)
        cpu.write(f"{time.time():.1f} {r.stdout.strip()}\n"); cpu.flush()
        time.sleep(1)
finally:
    stop_all()
